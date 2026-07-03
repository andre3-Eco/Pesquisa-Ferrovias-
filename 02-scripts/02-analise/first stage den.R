# ==============================================================================
# Etapa 10
# FIRST-STAGE: DENSIDADE BUFFER SINTÉTICA vs REAL — SEM PONTAS (POR ANO)
# Baseline OLS 
# ==============================================================================

library(tidyverse)
library(fixest)

if (!exists("data.wd")) {
  data.wd <- normalizePath(file.path(getwd(), "..", ".."))
}
setwd(data.wd)

cat("========================================================================\n")
cat("FIRST-STAGE: DENSIDADE BUFFER DINÂMICA — SEM PONTAS (SEM SPATIAL LAG)\n")
cat("========================================================================\n\n")

# ------------------------------------------------------------------------------
# 1. CARREGAMENTO DA BASE UNIFICADA E PAINEL DE PONTAS
# ------------------------------------------------------------------------------

base <- readRDS("01-dados/processados/base_completa_integrada_buffer.rds")

ne_states <- c("MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA")

base <- base |>
  filter(state_abbr %in% ne_states)

cat(sprintf("   AMCs Nordeste na base: %d\n", nrow(base)))

painel_pontas <- read_csv(
  "01-dados/processados/painel_amcs_pontas_ano_a_ano.csv",
  show_col_types = FALSE
)

pontas_por_ano <- painel_pontas |>
  select(code_amc, ano_corte) |>
  distinct()

# ------------------------------------------------------------------------------
# 2. IDENTIFICAR ANOS DISPONÍVEIS
# ------------------------------------------------------------------------------

cols <- colnames(base)
dens_real_cols <- grep("^densidade_buffer_real_[0-9]+$", cols, value = TRUE)
years <- sort(as.integer(sub("densidade_buffer_real_", "", dens_real_cols)))

cat(sprintf("   %d anos disponíveis: %d–%d\n\n", length(years), min(years), max(years)))

# ------------------------------------------------------------------------------
# 3. LOOP PRINCIPAL: PRIMEIRO ESTÁGIO POR ANO
# ------------------------------------------------------------------------------

fixed_controls <- paste(
  "bio_1", "bio_12", "bio_15",
  "dist_rio_km", "densidade_hidro_km_km2",
  "pct_solo_latossolos", "pct_solo_neossolos",
  sep = " + "
)

resultados <- list()

for (ano in years) {
  
  endo_var    <- paste0("densidade_buffer_real_",      ano)
  inst_var    <- paste0("densidade_buffer_sintetica_", ano)
  
  if (!all(c(endo_var, inst_var) %in% cols)) next
  
  if (sum(base[[inst_var]], na.rm = TRUE) == 0) {
    cat(sprintf("  ⚠ Ano %d ignorado: densidade sintética toda zero.\n", ano))
    next
  }
  
  # AMCs que eram pontas NESTE ano específico
  codes_pontas_ano <- pontas_por_ano |>
    filter(ano_corte == ano) |>
    pull(code_amc) |>
    unique()
  
  # Montar dados da regressão filtrando pontas e dados faltantes
  df <- base |>
    select(
      code_amc, state_abbr,
      all_of(endo_var),
      all_of(inst_var),
      bio_1, bio_12, bio_15,
      dist_rio_km, densidade_hidro_km_km2,
      pct_solo_latossolos, pct_solo_neossolos
    ) |>
    filter(!(code_amc %in% codes_pontas_ano)) |>
    filter(
      is.finite(.data[[endo_var]]),
      is.finite(.data[[inst_var]]),
      !is.na(state_abbr)
    )
  
  if (nrow(df) < 10) next
  
  n_excluidas <- sum(base$code_amc %in% codes_pontas_ano)
  
  # Formula: endo ~ inst + controles | fixed_effects
  form_str <- sprintf(
    "%s ~ %s + %s | state_abbr",
    endo_var, inst_var, fixed_controls
  )
  
  tryCatch({
    modelo <- feols(as.formula(form_str), data = df, se = "hetero")
    
    coef_inst <- coef(modelo)[[inst_var]]
    se_inst   <- se(modelo)[[inst_var]]
    t_inst    <- coef_inst / se_inst
    p_inst    <- 2 * pt(abs(t_inst), df = nrow(df) - length(coef(modelo)) - 1,
                        lower.tail = FALSE)
    f_stat    <- t_inst^2  
    
    resultados[[as.character(ano)]] <- tibble(
      ano                  = ano,
      variavel_endogena    = endo_var,
      variavel_instrumento = inst_var,
      coeficiente          = coef_inst,
      erro_padrao          = se_inst,
      t_estatistica        = t_inst,
      p_valor              = p_inst,
      F_estatistica        = f_stat,
      n_observacoes        = nrow(df),
      n_pontas_excluidas   = n_excluidas
    )
  }, error = function(e) {
    cat(sprintf("  ⚠ Erro no ano %d: %s\n", ano, e$message))
  })
  
  if (which(years == ano) %% 15 == 0) {
    cat(sprintf("  → Ano %d (%d/%d) | n=%d | pontas excluídas: %d\n",
                ano, which(years == ano), length(years), nrow(df), n_excluidas))
  }
}

# ------------------------------------------------------------------------------
# 4. COMPILAR E SALVAR
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
    coeficiente_sig   = sprintf("%+.4f%s", coeficiente, significancia),
    instrumento_forte = F_estatistica >= 10
  )

# Garantir que a pasta existe antes de salvar (previne erro silencioso)
dir.create("03-resultados/csv", showWarnings = FALSE, recursive = TRUE)

output_file <- "03-resultados/csv/first_stage_buffer_density_sem_pontas_baseline.csv"
write_csv(resultados_df, output_file)
cat(sprintf("   ✓ Resultados salvos em: %s\n\n", output_file))

