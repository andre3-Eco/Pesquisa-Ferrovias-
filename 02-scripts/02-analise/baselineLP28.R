# ==============================================================================
# Etapa 28 - REVISADA da 11 (Foco em Persistência de Longo Prazo)
#
# SECOND-STAGE IV (2SLS): DENSIDADE BUFFER SINTÉTICA → REAL — SEM PONTAS
# Tratamentos Históricos: 1880, 1911, 1936, 1950
# Outcomes (Persistência): 1970 a 2023 (PIB e População)
# Baseline: USANDO BASE UNIFICADA COM DADOS RECENTES
# ==============================================================================

library(tidyverse)
library(fixest)

if (!exists("data.wd")) {
  data.wd <- normalizePath(file.path(getwd(), "..", ".."))
}
setwd(data.wd)

# ------------------------------------------------------------------------------
# 1. CARREGAMENTO DA BASE
# ------------------------------------------------------------------------------
base <- read_csv("01-dados/processados/base_completa_integrada_buffer_com_pib_recente.csv", show_col_types = FALSE)

ne_states <- c("MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA")
base <- base |> filter(state_abbr %in% ne_states)

painel_pontas <- read_csv(
  "01-dados/processados/painel_amcs_pontas_ano_a_ano.csv",
  show_col_types = FALSE
)

pontas_por_ano <- painel_pontas |>
  select(code_amc, ano_corte) |>
  distinct()

# ------------------------------------------------------------------------------
# 2. DEFINIÇÃO DOS ANOS DE TRATAMENTO E VETOR DE OUTCOMES DE LONGO PRAZO
# ------------------------------------------------------------------------------


anos_tratamento <- c(1880, 1911, 1936, 1950)

# Controles geográficos e climáticos exógenos
fixed_controls <- paste(
  "bio_1", "bio_12", "bio_15",
  "dist_rio_km", "densidade_hidro_km_km2",
  "pct_solo_latossolos", "pct_solo_neossolos",
  sep = " + "
)

# Vetor com todos os outcomes de 1970 até o presente para testar a persistência
outcomes_alvo <- c(
  "log(pib_1970)", "log(pop_total_1970)",
  "log(pib_1980)", "log(pop_total_1980)",
  "log(pop_total_1991)", 
  "log(pib_2000)", "log(pop_total_2000)",
  "log(pib_2010)", "log(pop_total_2010)",
  "log(pib_2021)", 
  "log(pop_total_2022)", 
  "log(pib_2023)"
)

# ------------------------------------------------------------------------------
# 3. FUNÇÃO AUXILIAR: RODAR 2SLS (fixest::feols) COM LOGS EXPLÍCITOS
# ------------------------------------------------------------------------------

rodar_2sls <- function(df, endo_var, inst_var, outcome_var, ano_trat) {
  
  outcome_col <- gsub("log\\(|\\)", "", outcome_var)
  
  if (!(outcome_col %in% names(df))) {
    cat(sprintf("  ⚠ Pulo [Tratamento=%d]: Outcome '%s' não existe na base.\n", ano_trat, outcome_col))
    return(NULL)
  }
  
  vals <- df[[outcome_col]]
  if (sum(!is.na(vals) & vals > 0, na.rm = TRUE) < 10) {
    cat(sprintf("  ⚠ Pulo [Tratamento=%d, Outcome=%s]: Menos de 10 observações válidas > 0.\n", ano_trat, outcome_var))
    return(NULL)
  }
  
  if (var(df[[inst_var]], na.rm = TRUE) == 0) {
    cat(sprintf("  ⚠ Pulo [Tratamento=%d, Outcome=%s]: Instrumento sem variância espacial (tudo igual a zero).\n", ano_trat, outcome_var))
    return(NULL)
  }
  
  form_str <- sprintf(
    "%s ~ %s | state_abbr | %s ~ %s",
    outcome_var, fixed_controls, endo_var, inst_var
  )
  
  tryCatch({
    mod <- feols(as.formula(form_str), data = df, se = "hetero")
    ct <- summary(mod)$coeftable
    
    nome_coef <- paste0("fit_", endo_var)
    if (!(nome_coef %in% rownames(ct))) {
      if (endo_var %in% rownames(ct)) {
        nome_coef <- endo_var
      } else {
        cat(sprintf("  ⚠ Pulo [Tratamento=%d, Outcome=%s]: Coeficiente descartado pelo modelo (multicolinearidade).\n", ano_trat, outcome_var))
        return(NULL)
      }
    }
    
    f_stat <- tryCatch({ fitstat(mod, "ivf")[[1]]$stat }, error = function(e) NA_real_)
    
    tibble(
      ano_tratamento       = ano_trat,
      outcome_var          = outcome_var,
      variavel_endogena    = endo_var,
      variavel_instrumento = inst_var,
      coeficiente          = ct[nome_coef, 1],
      erro_padrao          = ct[nome_coef, 2],
      t_estatistica        = ct[nome_coef, 3],
      p_valor              = ct[nome_coef, 4],
      F_stat_1estagio      = f_stat,
      n_observacoes        = nrow(df)
    )
  }, error = function(e) {
    cat(sprintf("  ⚠ Erro [Tratamento=%d, Outcome=%s]: %s\n", ano_trat, outcome_var, e$message))
    NULL
  })
}

# ------------------------------------------------------------------------------
# 4. LOOP PRINCIPAL: SEGUNDO ESTÁGIO 
# ------------------------------------------------------------------------------
cat("Iniciando estimações 2SLS (Persistência Histórica)...\n")
resultados <- list()
contador   <- 0

for (ano_trat in anos_tratamento) {
  
  cat(sprintf("\nProcessando Tratamento Histórico: %d\n", ano_trat))
  
  endo_var <- paste0("densidade_buffer_real_", ano_trat)
  inst_var <- paste0("densidade_buffer_sintetica_", ano_trat)
  
  if (!all(c(endo_var, inst_var) %in% names(base))) {
    cat(sprintf("  ⚠ Variáveis de densidade ausentes para %d. Pulando.\n", ano_trat))
    next
  }
  
  # Remove as AMCs que eram "pontas de linha" no ano do tratamento
  codes_pontas_ano <- pontas_por_ano |>
    filter(ano_corte == ano_trat) |>
    pull(code_amc) |>
    unique()
  
  df <- base |>
    filter(!(code_amc %in% codes_pontas_ano)) |>
    filter(
      is.finite(.data[[endo_var]]),
      is.finite(.data[[inst_var]]),
      !is.na(state_abbr)
    )
  
  if (nrow(df) < 10) next
  
  # Roda a regressão IV para todos os outcomes de longo prazo mapeados
  for (oc_var in outcomes_alvo) {
    res <- rodar_2sls(df, endo_var, inst_var, oc_var, ano_trat)
    if (!is.null(res)) {
      contador <- contador + 1
      resultados[[paste0("t_", ano_trat, "_", oc_var)]] <- res
    }
  }
}

# ------------------------------------------------------------------------------
# 5. COMPILAR E SALVAR RESULTADOS
# ------------------------------------------------------------------------------


if (length(resultados) == 0) stop("Nenhuma regressão bem-sucedida.")

resultados_df <- bind_rows(resultados) |>
  mutate(
    significancia = case_when(
      p_valor < 0.01 ~ "***",
      p_valor < 0.05 ~ "**",
      p_valor < 0.10 ~ "*",
      TRUE           ~ ""
    ),
    coeficiente_sig = sprintf("%+.4f%s", coeficiente, significancia)
  )

dir.create("03-resultados/csv", showWarnings = FALSE, recursive = TRUE)

output_file <- "03-resultados/csv/second_stage_persistencia_longo_prazo.csv"
write_csv(resultados_df, output_file)
