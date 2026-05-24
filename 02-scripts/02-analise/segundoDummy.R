# ==============================================================================
# BATERIA V — SEGUNDO ESTÁGIO (TRATAMENTO: DUMMY 1969 | INCREMENTAL)
# ==============================================================================

library(sf)
library(dplyr)
library(spdep)
library(fixest)
library(stringr)
library(readr)
library(tidyr)

sf_use_s2(FALSE)
if (!exists("data.wd")) data.wd <- getwd()

cat("\n", strrep("=", 80), "\n")
cat("BATERIA V: SEGUNDO ESTÁGIO IV (DUMMY 1969 | SEM PONTAS | INCREMENTAL)\n")
cat(strrep("=", 80), "\n\n")

# ==============================================================================
# SEÇÃO 1: CARREGAMENTO E FILTROS (Mantendo sua estrutura original)
# ==============================================================================
cat("ETAPA 1 & 2: Carregando dados e aplicando filtros...\n")

# [A carga de dados permanece igual à sua versão original]
outcomes_wide <- readRDS("01-dados/processados/outcomes/outcomes_amc_wide.rds")
ctrl_clima    <- readRDS("01-dados/processados/controles_clima_amcs_nordeste.rds")
ctrl_rios     <- readRDS("01-dados/processados/controles_rios_amcs_nordeste.rds")
ctrl_solo     <- readRDS("01-dados/processados/controles_solo_amcs_nordeste.rds")

base_mestre <- base_iv_sf |>
  inner_join(outcomes_wide, by = "code_amc") |>
  left_join(ctrl_clima |> select(code_amc, bio_1, bio_12, bio_15), by = "code_amc") |>
  left_join(ctrl_rios |> select(code_amc, dist_rio_km, densidade_hidro_km_km2), by = "code_amc") |>
  left_join(ctrl_solo |> select(code_amc, pct_solo_latossolos, pct_solo_neossolos), by = "code_amc")

codes_pontas <- lista_amcs_pontas$amcs_codigo |>
  stringr::str_split(" e ") |> unlist() |> as.numeric() |> na.omit() |> unique()

df_limpo <- base_mestre |>
  filter(!is.na(dist_rail_real_1969)) |>
  filter(dist_rail_real_1969 <= 200) |>
  filter(!(code_amc %in% codes_pontas))

vizinhos <- poly2nb(df_limpo, queen = TRUE)
pesos    <- nb2listw(vizinhos, style = "W", zero.policy = TRUE)
df_limpo$dist_sintetica_vizinhos <- lag.listw(pesos, df_limpo$dist_rail_sintetica_km, zero.policy = TRUE)

df_reg <- st_drop_geometry(df_limpo)

# ==============================================================================
# SEÇÃO 3: CONFIGURAÇÃO DO TRATAMENTO (APENAS DUMMY)
# ==============================================================================
# Definindo apenas a Dummy
tratamento <- list(nome = "Dummy", endo = "dummy_atendida_real_1969", inst = "dummy_atendida_sintetica")

outcomes_config <- list(
  list(escopo="1_PIB", nome="PIB Total (2000)",   col="pib_2000", transf="log"),
  list(escopo="1_PIB", nome="PIB Total (2010)",   col="pib_2010", transf="log"),
  list(escopo="1_PIB", nome="PIB p.c. (2000)",    col="pib_percapita_2000", transf="log"),
  list(escopo="1_PIB", nome="PIB p.c. (2010)",    col="pib_percapita_2010", transf="log"),
  list(escopo="2_Pop", nome="Pop. Total (1991)",  col="pop_total_1991", transf="log"),
  list(escopo="2_Pop", nome="Pop. Total (2000)",  col="pop_total_2000", transf="log"),
  list(escopo="2_Pop", nome="Pop. Total (2010)",  col="pop_total_2010", transf="log"),
  list(escopo="2_Pop", nome="Tx. Urban. (2010)",  col="tx_urbanizacao_2010", transf="nivel"),
  list(escopo="3_PAM", nome="Val. Prod. (2000)",  col="valor_producao_mil_reais_2000", transf="log"),
  list(escopo="3_PAM", nome="Val. Prod. (2010)",  col="valor_producao_mil_reais_2010", transf="log"),
  list(escopo="4_Soc", nome="IDHM (2000)",        col="adh_idhm_2000", transf="nivel"),
  list(escopo="4_Soc", nome="IDHM (2010)",        col="adh_idhm_2010", transf="nivel"),
  list(escopo="4_Soc", nome="Renda p.c. (2000)",  col="adh_rdpc_2000", transf="log"),
  list(escopo="4_Soc", nome="Renda p.c. (2010)",  col="adh_rdpc_2010", transf="log"),
  list(escopo="4_Soc", nome="% Pobres (2010)",    col="adh_pmpob_2010", transf="nivel")
)

especificacoes <- list(
  list(id = "M1", nome = "Base", controles = "1"),
  list(id = "M2", nome = "+ Lag", controles = "dist_sintetica_vizinhos"),
  list(id = "M3", nome = "+ Clima", controles = "dist_sintetica_vizinhos + bio_1 + bio_12 + bio_15"),
  list(id = "M4", nome = "+ Geo",   controles = "dist_sintetica_vizinhos + bio_1 + bio_12 + bio_15 + dist_rio_km + pct_solo_latossolos")
)

# ==============================================================================
# SEÇÃO 4: LOOP DE REGRESSÃO (DUMMY ONLY)
# ==============================================================================
cat("ETAPA 4: Estimando Modelos 2SLS...\n\n")
resultados_2sls <- data.frame()
contador <- 0
total_regs <- length(outcomes_config) * length(especificacoes)

for (out in outcomes_config) {
  if (!(out$col %in% names(df_reg))) next
  
  for (esp in especificacoes) {
    contador <- contador + 1
    
    df_iter <- df_reg |> 
      filter(!is.na(.data[[out$col]]), !is.na(.data[[tratamento$endo]]), !is.na(.data[[tratamento$inst]]))
    
    if (out$transf == "log") {
      df_iter <- df_iter |> filter(.data[[out$col]] > 0)
      lhs <- paste0("log(", out$col, ")")
    } else {
      lhs <- out$col
    }
    
    # Fórmula: Y ~ Controles | FE | Endogena ~ Instrumento
    form_str <- sprintf("%s ~ %s | state_abbr | %s ~ %s", lhs, esp$controles, tratamento$endo, tratamento$inst)
    
    tryCatch({
      modelo_iv <- feols(as.formula(form_str), data = df_iter, se = "hetero")
      
      coefs <- coef(modelo_iv)
      ses   <- se(modelo_iv)
      
      # O fixest no IV geralmente prefixa o nome do coeficiente com "fit_"
      nome_coef <- paste0("fit_", tratamento$endo)
      if (!nome_coef %in% names(coefs)) nome_coef <- tratamento$endo
      
      res <- data.frame(
        Outcome = out$nome,
        Modelo  = esp$id,
        Coef    = as.numeric(coefs[nome_coef]),
        DP      = as.numeric(ses[nome_coef]),
        P       = 2 * (1 - pnorm(abs(as.numeric(coefs[nome_coef]) / as.numeric(ses[nome_coef])))),
        F_Stat  = as.numeric(fitstat(modelo_iv, "ivf")[[1]]),
        N       = nobs(modelo_iv)
      )
      
      resultados_2sls <- bind_rows(resultados_2sls, res)
      cat(sprintf("\rProgresso: [%d/%d] Estimando %s...", contador, total_regs, out$nome))
      
    }, error = function(e) {})
  }
}

# ==============================================================================
# SEÇÃO 5: TABELA FINAL
# ==============================================================================
tabela_final <- resultados_2sls |>
  mutate(Sig = case_when(P < 0.01 ~ "***", P < 0.05 ~ "**", P < 0.10 ~ "*", TRUE ~ "")) |>
  mutate(Valor = sprintf("%+.4f%s\n(%.4f)", Coef, Sig, DP)) |>
  select(Outcome, Modelo, Valor) |>
  pivot_wider(names_from = Modelo, values_from = Valor)

print(tabela_final)
write_csv(resultados_2sls, "03-resultados/csv/resultados_dummy_final.csv")



