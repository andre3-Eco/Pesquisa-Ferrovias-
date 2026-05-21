# ==============================================================================
# DIAGNÓSTICO DO PRIMEIRO ESTÁGIO (FIRST STAGE) — 3 TRATAMENTOS
# ==============================================================================

library(sf)
library(dplyr)
library(spdep)
library(fixest)
library(stringr)

sf_use_s2(FALSE)
if (!exists("data.wd")) data.wd <- getwd()

cat("\n", strrep("=", 80), "\n")
cat("DIAGNÓSTICO DO PRIMEIRO ESTÁGIO (ANO BASE: 1985 | SEM PONTAS | <= 200km)\n")
cat(strrep("=", 80), "\n\n")

# ==============================================================================
# 1. CARREGAR E PREPARAR DADOS
# ==============================================================================

base_completa <- read_csv("01-dados/processados/base_completa_integrada.csv")
base_iv_sf <- amcs_geometria |>
  inner_join(base_completa, by = "code_amc")

if (!exists("base_iv_sf")) stop("ERRO: 'base_iv_sf' não encontrado.")
if (!exists("lista_amcs_pontas")) stop("ERRO: 'lista_amcs_pontas' não encontrado.")

if (!exists("ctrl_clima")) ctrl_clima <- readRDS("01-dados/processados/controles_clima_amcs_nordeste.rds")
if (!exists("ctrl_rios"))  ctrl_rios  <- readRDS("01-dados/processados/controles_rios_amcs_nordeste.rds")
if (!exists("ctrl_solo"))  ctrl_solo  <- readRDS("01-dados/processados/controles_solo_amcs_nordeste.rds")

# Unir controles
base_mestre <- base_iv_sf |>
  left_join(ctrl_clima |> select(code_amc, bio_1, bio_12, bio_15), by = "code_amc") |>
  left_join(ctrl_rios |> select(code_amc, dist_rio_km, densidade_hidro_km_km2), by = "code_amc") |>
  left_join(ctrl_solo |> select(code_amc, pct_solo_latossolos, pct_solo_neossolos), by = "code_amc")

# Extrair AMCs das pontas
codes_pontas <- lista_amcs_pontas$amcs_codigo |>
  stringr::str_split(" e ") |> unlist() |> as.numeric() |> na.omit() |> unique()

# Filtrar base (Apenas 1985 para teste geral, <= 200km, sem pontas)
df_fs <- base_mestre |>
  filter(dist_rail_real_1985 <= 200) |>
  filter(!(code_amc %in% codes_pontas))

# Recalcular lag espacial para a amostra limpa
vizinhos <- poly2nb(df_fs, queen = TRUE)
pesos    <- nb2listw(vizinhos, style = "W", zero.policy = TRUE)
df_fs$dist_sintetica_vizinhos <- lag.listw(pesos, df_fs$dist_rail_sintetica_km, zero.policy = TRUE)

df_fs <- sf::st_drop_geometry(df_fs)

# ==============================================================================
# 2. CONFIGURAR MODELOS DE PRIMEIRO ESTÁGIO
# ==============================================================================
controles_str <- "dist_sintetica_vizinhos + bio_1 + bio_12 + bio_15 + dist_rio_km + pct_solo_latossolos"

tratamentos <- list(
  list(nome = "Distância Contínua", endo = "dist_rail_real_1985", inst = "dist_rail_sintetica_km"),
  list(nome = "Dummy de Atendimento", endo = "dummy_atendida_real_1985", inst = "dummy_atendida_sintetica"),
  list(nome = "Densidade Ferroviária", endo = "densidade_real_1985", inst = "densidade_sintetica")
)

resultados_fs <- data.frame()

# ==============================================================================
# 3. ESTIMAR E EXTRAIR
# ==============================================================================
for (trat in tratamentos) {
  
  # Fórmula do Primeiro Estágio: Endógena ~ Instrumento + Controles | Efeitos Fixos
  form_str <- sprintf("%s ~ %s + %s | state_abbr", trat$endo, trat$inst, controles_str)
  
  tryCatch({
    modelo_fs <- feols(as.formula(form_str), data = df_fs, se = "hetero")
    
    coef_inst <- coef(modelo_fs)[trat$inst]
    se_inst   <- se(modelo_fs)[trat$inst]
    t_inst    <- coef_inst / se_inst
    p_inst    <- 2 * (1 - pnorm(abs(t_inst)))
    
    # Em modelos just-identified com 1 instrumento, F = t^2
    f_stat <- t_inst^2 
    
    res <- data.frame(
      Tratamento  = trat$nome,
      Coeficiente = coef_inst,
      DP          = se_inst,
      `T-Stat`    = t_inst,
      `P-Valor`   = p_inst,
      `F-Stat`    = f_stat,
      N_Obs       = nobs(modelo_fs),
      check.names = FALSE
    )
    
    resultados_fs <- bind_rows(resultados_fs, res)
    
  }, error = function(e) {
    cat(sprintf("Erro ao rodar modelo para %s: %s\n", trat$nome, e$message))
  })
}

# ==============================================================================
# 4. EXIBIR RESULTADOS
# ==============================================================================
tabela_fmt <- resultados_fs |>
  mutate(
    Sig = case_when(`P-Valor` < 0.01 ~ "***", `P-Valor` < 0.05 ~ "**", `P-Valor` < 0.10 ~ "*", TRUE ~ ""),
    Coeficiente = sprintf("%+.4f%s", Coeficiente, Sig),
    DP          = sprintf("(%.4f)", DP),
    `F-Stat`    = sprintf("%.1f", `F-Stat`),
    `T-Stat`    = sprintf("%+.2f", `T-Stat`),
    `P-Valor`   = sprintf("%.4f", `P-Valor`)
  ) |>
  select(Tratamento, Coeficiente, DP, `T-Stat`, `P-Valor`, `F-Stat`, N_Obs)

print(tabela_fmt, row.names = FALSE)
cat("\nSignificância: *** p<0.01, ** p<0.05, * p<0.10")
cat("\nRegra de Bolso: O F-Stat deve ser preferencialmente superior a 10 (Regra de Staiger-Stock).\n")