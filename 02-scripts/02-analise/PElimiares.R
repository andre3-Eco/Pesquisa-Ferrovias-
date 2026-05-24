# ==============================================================================
# DIAGNÓSTICO DO PRIMEIRO ESTÁGIO — SENSIBILIDADE DA DUMMY DE ATENDIMENTO
# ==============================================================================

library(sf)
library(dplyr)
library(spdep)
library(fixest)
library(stringr)
library(readr)

sf_use_s2(FALSE)
if (!exists("data.wd")) data.wd <- getwd()

cat("\n", strrep("=", 80), "\n")
cat("DIAGNÓSTICO DO PRIMEIRO ESTÁGIO: TESTE DE MÚLTIPLOS LIMIARES (ANO: 2003)\n")
cat("Variável Endógena: Dummy de Atendimento Real\n")
cat("Instrumento:       Dummy de Atendimento Sintética\n")
cat(strrep("=", 80), "\n\n")

# ==============================================================================
# 1. CARREGAR DADOS BASE E CONTROLES (FIXOS)
# ==============================================================================
cat("Etapa 1: Preparando base mestre e defasagem espacial (calculado 1 única vez)...\n")

# Assumindo que amcs_geometria e base_completa já existem no seu Environment
base_completa <- read_csv("01-dados/processados/base_completa_integrada.csv", show_col_types = FALSE)
base_iv_sf <- amcs_geometria |> inner_join(base_completa, by = "code_amc")

ctrl_clima <- readRDS("01-dados/processados/controles_clima_amcs_nordeste.rds")
ctrl_rios  <- readRDS("01-dados/processados/controles_rios_amcs_nordeste.rds")
ctrl_solo  <- readRDS("01-dados/processados/controles_solo_amcs_nordeste.rds")

base_mestre <- base_iv_sf |>
  left_join(ctrl_clima |> select(code_amc, bio_1, bio_12, bio_15), by = "code_amc") |>
  left_join(ctrl_rios |> select(code_amc, dist_rio_km, densidade_hidro_km_km2), by = "code_amc") |>
  left_join(ctrl_solo |> select(code_amc, pct_solo_latossolos, pct_solo_neossolos), by = "code_amc")

# Filtrar Pontas
codes_pontas <- lista_amcs_pontas$amcs_codigo |>
  stringr::str_split(" e ") |> unlist() |> as.numeric() |> na.omit() |> unique()

df_base <- base_mestre |> filter(!(code_amc %in% codes_pontas))

# Calcular Lag Espacial (Fixo para a rede sintética)
vizinhos <- poly2nb(df_base, queen = TRUE)
pesos    <- nb2listw(vizinhos, style = "W", zero.policy = TRUE)
df_base$dist_sintetica_vizinhos <- lag.listw(pesos, df_base$dist_rail_sintetica_km, zero.policy = TRUE)

df_base <- sf::st_drop_geometry(df_base)

# ==============================================================================
# 2. LOOP DE ESTIMAÇÃO PELOS LIMIARES
# ==============================================================================
cat("Etapa 2: Estimando First Stage para cada limiar...\n\n")

# Defina os limiares que você gerou no script anterior
limiares_km <- c(10, 25, 50, 100)
resultados_fs_limiares <- data.frame()

controles_str <- "dist_sintetica_vizinhos + bio_1 + bio_12 + bio_15 + dist_rio_km + pct_solo_latossolos"

for (limiar in limiares_km) {
  
  # Carregar a base de dummies específica deste limiar
  arquivo_dummy <- sprintf("%s/01-dados/processados/limiares_atendimento/base_dummy_simples_%dkm.csv", data.wd, limiar)
  
  if (!file.exists(arquivo_dummy)) {
    cat(sprintf("[AVISO] Arquivo não encontrado para %d km. Pulando...\n", limiar))
    next
  }
  
  base_dummy <- read_csv(arquivo_dummy, show_col_types = FALSE) |> 
    select(code_amc, dummy_atendida_sintetica, dummy_atendida_real_2003)
  
  # Juntar as dummies com a base mestre preparada
  df_fs <- df_base |> 
    # Remove as antigas para não duplicar, se existirem
    select(-any_of(c("dummy_atendida_sintetica", "dummy_atendida_real_2003"))) |> 
    inner_join(base_dummy, by = "code_amc") |>
    filter(!is.na(dummy_atendida_real_2003), !is.na(dummy_atendida_sintetica))
  
  # Fórmula: Dummy Real ~ Dummy Sintética + Controles | FE UF
  form_str <- sprintf("dummy_atendida_real_2003 ~ dummy_atendida_sintetica + %s | state_abbr", controles_str)
  
  tryCatch({
    modelo_fs <- feols(as.formula(form_str), data = df_fs, se = "hetero")
    
    coef_inst <- coef(modelo_fs)["dummy_atendida_sintetica"]
    se_inst   <- se(modelo_fs)["dummy_atendida_sintetica"]
    t_inst    <- coef_inst / se_inst
    p_inst    <- 2 * (1 - pnorm(abs(t_inst)))
    
    # F-Stat do instrumento
    fs_obj <- fitstat(modelo_fs, "ivf")[[1]]
    f_stat <- if (is.list(fs_obj)) fs_obj$stat else as.numeric(fs_obj)
    
    # Se fitstat falhar por não ser modelo IV, computar T^2
    if (is.na(f_stat) || is.null(f_stat)) {
      f_stat <- t_inst^2 
    }
    
    res <- data.frame(
      Limiar_km   = paste0(limiar, " km"),
      Coeficiente = coef_inst,
      DP          = se_inst,
      `T-Stat`    = t_inst,
      `P-Valor`   = p_inst,
      `F-Stat`    = f_stat,
      N_Obs       = nobs(modelo_fs),
      check.names = FALSE
    )
    
    resultados_fs_limiares <- bind_rows(resultados_fs_limiares, res)
    cat(sprintf("  ✓ Limiar %d km estimado com sucesso (F-Stat: %.1f)\n", limiar, f_stat))
    
  }, error = function(e) {
    cat(sprintf("  [ERRO] Falha ao rodar modelo para limiar %d km: %s\n", limiar, e$message))
  })
}

# ==============================================================================
# 3. EXIBIR RESULTADOS
# ==============================================================================
cat("\n")
cat(strrep("-", 80), "\n")
cat("RESULTADO FINAL: SENSIBILIDADE DO PRIMEIRO ESTÁGIO (DUMMY 2003)\n")
cat(strrep("-", 80), "\n")

tabela_fmt <- resultados_fs_limiares |>
  mutate(
    Sig = case_when(`P-Valor` < 0.01 ~ "***", `P-Valor` < 0.05 ~ "**", `P-Valor` < 0.10 ~ "*", TRUE ~ ""),
    Coeficiente = sprintf("%+.4f%s", Coeficiente, Sig),
    DP          = sprintf("(%.4f)", DP),
    `F-Stat`    = sprintf("%.1f", `F-Stat`),
    `T-Stat`    = sprintf("%+.2f", `T-Stat`),
    `P-Valor`   = sprintf("%.4f", `P-Valor`)
  ) |>
  select(Limiar_km, Coeficiente, DP, `T-Stat`, `P-Valor`, `F-Stat`, N_Obs)

print(tabela_fmt, row.names = FALSE)
cat("\nSignificância: *** p<0.01, ** p<0.05, * p<0.10")
cat("\nRegra de Staiger-Stock (1997): F-Stat > 10 indica um instrumento forte.\n")
cat("Regra de Olea-Pflueger (2013): F-Stat > 23 (aprox.) para rejeitar viés a 5%.\n")