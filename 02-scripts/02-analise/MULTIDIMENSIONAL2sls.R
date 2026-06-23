# ==============================================================================
# SECOND-STAGE IV (2SLS): MULTIDIMENSIONAL ANALYSIS
# Escopos: PIBs Setoriais, Urbanização e IDH (Decomposto)
# ==============================================================================

library(dplyr)
library(tidyverse)
library(fixest)
library(stringr)
library(readr)

if (!exists("data.wd")) {
  data.wd <- normalizePath(file.path(getwd(), "..", ".."))
}
setwd(data.wd)

cat("========================================================================\n")
cat("SECOND-STAGE IV: MULTIDIMENSIONAL (PIB, URBAN, IDH)\n")
cat("========================================================================\n\n")

# ------------------------------------------------------------------------------
# 1. CARREGAR BASES
# ------------------------------------------------------------------------------
cat("1. Carregando bases...\n")

base_main <- read_csv("01-dados/processados/base_completa_integrada.csv", show_col_types = FALSE)
base_densidade <- read_csv("01-dados/processados/base_densidade_buffer_unificada.csv", show_col_types = FALSE)
painel_pontas <- read_csv("01-dados/processados/painel_amcs_pontas_ano_a_ano.csv", show_col_types = FALSE)
outcomes_interp <- readRDS("01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.rds")

ne_states <- c("MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA")

base <- base_main |>
  filter(state_abbr %in% ne_states) |>
  select(-starts_with("densidade_real_"), -starts_with("densidade_sintetica")) |>
  left_join(base_densidade, by = "code_amc")

pontas_por_ano <- painel_pontas |> select(code_amc, ano_corte) |> distinct()

# Controles
ctrl_clima <- readRDS("01-dados/processados/controles_clima_amcs_nordeste.rds")
ctrl_rios  <- readRDS("01-dados/processados/controles_rios_amcs_nordeste.rds")
ctrl_solo  <- readRDS("01-dados/processados/controles_solo_amcs_nordeste.rds")

base <- base |>
  left_join(ctrl_clima |> select(code_amc, bio_1, bio_12, bio_15),             by = "code_amc") |>
  left_join(ctrl_rios  |> select(code_amc, dist_rio_km, densidade_hidro_km_km2), by = "code_amc") |>
  left_join(ctrl_solo  |> select(code_amc, pct_solo_latossolos, pct_solo_neossolos), by = "code_amc")

base <- base |> left_join(outcomes_interp, by = "code_amc")

# ------------------------------------------------------------------------------
# 2. DEFINIÇÃO DOS ESCOPOS (O CORAÇÃO DO SCRIPT)
# ------------------------------------------------------------------------------

# A. Escopo PIB Setorial (Exemplo usando os prefixos encontrados)
# Vamos testar PIB Total, Agro, Indústria e Serviços
pib_setorial_vars <- c(
  "pib", "pibag", "pibi", "pibse"
)

# B. Escopo Urbanização
# Taxa de urbanização e População Urbana
urban_vars <- c(
  "tx_urbanizacao", "pop_urbana"
)

# C. Escopo IDH (Decomposição)
# IDH Geral e seus 3 pilares
idh_vars <- c(
  "adh_idhm", "adh_idhm_e", "adh_idhm_l", "adh_idhm_r"
)

# ------------------------------------------------------------------------------
# 3. FUNÇÃO DE EXECUÇÃO E LOOP
# ------------------------------------------------------------------------------

# (A função rodar_2sls seria a mesma do seu baseline, adaptada para log)
rodar_2sls <- function(df, endo_var, inst_var, outcome_prefix, ano, escopo) {
  
  # Tenta encontrar a coluna que combina prefixo + ano
  # Ex: pibag_1980 ou tx_urbanizacao_2000
  col_name <- paste0(outcome_prefix, "_", ano)
  
  # Se for IDH, o ano está no nome (ex: adh_idhm_1991)
  # Se for urbanização/pib, o ano está no nome (ex: pibag_1980)
  # O padrão parece ser prefixo_ano.
  
  if (!(col_name %in% names(df))) return(NULL)
  
  # Seleciona a coluna para teste de validade
  vals <- df[[col_name]]
  if (sum(!is.na(vals) & vals > 0, na.rm = TRUE) < 15) return(NULL)

  # Define se precisa de LOG (PIB e População geralmente precisam, IDH e Taxas não)
  # Regra: Se o prefixo for pib, pop, ou agro/ind/serv, aplica log.
  needs_log <- str_detect(outcome_prefix, "^pib|^pop")
  
  outcome_formula <- if(needs_log) {
    sprintf("log(%s) ~ %s | state_abbr | %s ~ %s", 
            col_name, fixed_controls, endo_var, inst_var)
  } else {
    sprintf("%s ~ %s | state_abbr | %s ~ %s", 
            col_name, fixed_controls, endo_var, inst_var)
  }

  tryCatch({
    mod <- feols(as.formula(outcome_formula), data = df, se = "hetero")
    ct <- summary(mod)$coeftable
    nome_endo_fixest <- paste0("fit_", endo_var)
    
    if (!(nome_endo_fixest %in% rownames(ct))) return(NULL)
    
    tibble(
      ano = ano,
      escopo = escopo,
      outcome_var = col_name,
      coeficiente = ct[nome_endo_fixest, 1],
      p_valor = ct[nome_endo_fixest, 4],
      F_stat_1estagio = tryCatch({fitstat(mod, "ivf")[[1]]$stat}, error = function(e) NA_real_),
      n_obs = nrow(df)
    )
  }, error = function(e) NULL)
}

# ------------------------------------------------------------------------------
# 4. LOOP PRINCIPAL
# ------------------------------------------------------------------------------

fixed_controls <- "bio_1 + bio_12 + bio_15 + dist_rio_km + densidade_hidro_km_km2 + pct_solo_latossolos + pct_solo_neossolos"
years <- sort(as.integer(sub("densidade_buffer_real_", "", grep("^densidade_buffer_real_[0-9]+$", colnames(base), value = TRUE))))

resultados_finais <- list()

for (ano in years) {
  endo_var <- paste0("densidade_buffer_real_", ano)
  inst_var <- paste0("densidade_buffer_sintetica_", ano)
  
  # Filtro de Pontas
  codes_pontas <- pontas_por_ano |> filter(ano_corte == ano) |> pull(code_amc)
  df_sub <- base |> filter(!(code_amc %in% codes_pontas)) |> 
    filter(is.finite(.data[[endo_var]]), is.finite(.data[[inst_var]]))

  if (nrow(df_sub) < 20) next

  # --- TESTE ESCOPO A: PIB SETORIAL ---
  for (p in pib_setorial_vars) {
    res <- rodar_2sls(df_sub, endo_var, inst_var, p, ano, "PIB_Setorial")
    if (!is.null(res)) resultados_finais[[length(resultados_finais)+1]] <- res
  }

  # --- TESTE ESCOPO B: URBANIZAÇÃO ---
  for (u in urban_vars) {
    res <- rodar_2sls(df_sub, endo_var, inst_var, u, ano, "Urbanizacao")
    if (!is.null(res)) resultados_finais[[length(resultados_finais)+1]] <- res
  }

  # --- TESTE ESCOPO C: IDH ---
  # Nota: IDH tem anos específicos (1991, 2000, 2010). 
  # O loop de anos vai tentar rodar, mas só funcionará quando o 'ano' do loop bater com o ano do IDH.
  for (i in idh_vars) {
    res <- rodar_2sls(df_sub, endo_var, inst_var, i, ano, "IDH_Decomposto")
    if (!is.null(res)) resultados_finais[[length(resultados_finais)+1]] <- res
  }
  
  cat(sprintf("Ano %d concluído...\n", ano))
}

# Salvar
df_res <- bind_rows(resultados_finais)
write_csv(df_res, "03-resultados/csv/second_stage_multidimensional_results.csv")
cat("✅ Concluído! Resultados em 03-resultados/csv/second_stage_multidimensional_results.csv\n")