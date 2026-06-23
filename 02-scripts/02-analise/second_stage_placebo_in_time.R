# ==============================================================================
# SECOND-STAGE IV (2SLS) — PLACEBO IN-TIME (FUTURE DENSITY)
# ==============================================================================
# Lógica:
#   Para cada ano T, usamos a densidade de ferrovias inauguradas APÓS T como
#   variável de tratamento (instrumentada pela densidade sintética futura).
#   Testamos se essa "densidade futura" prediz o PIB/população no próprio ano T.
#
#   Interpretação:
#   - Se future_density_T prediz PIB_T → lugares que receberão ferrovias no
#     futuro já eram mais prósperos em T → evidência de endogeneidade no
#     placement das ferrovias (reverse causality).
#   - Se coeficiente ≈ 0 e p > 0.10 → placebo aprovado → instrumento exógeno.
#
# Pré-requisito:
#   Rodar 02-scripts/01-preparacao/base_buffer_future.R para gerar
#   01-dados/processados/base_densidade_buffer_future.csv
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
cat("SECOND-STAGE IV: PLACEBO IN-TIME (FUTURE DENSITY)\n")
cat("========================================================================\n\n")

# ------------------------------------------------------------------------------
# 1. CARREGAR BASES
# ------------------------------------------------------------------------------
cat("1. Carregando bases de dados...\n")

base_main <- read_csv(
  "01-dados/processados/base_completa_integrada.csv",
  show_col_types = FALSE
)

# Base de densidade FUTURA gerada por base_buffer_future.R
future_file <- "01-dados/processados/base_densidade_buffer_future.csv"
if (!file.exists(future_file)) {
  stop(paste(
    "Arquivo não encontrado:", future_file,
    "\nRode primeiro: 02-scripts/01-preparacao/base_buffer_future.R"
  ))
}
base_future <- read_csv(future_file, show_col_types = FALSE)

painel_pontas <- read_csv(
  "01-dados/processados/painel_amcs_pontas_ano_a_ano.csv",
  show_col_types = FALSE
)

outcomes_interp <- readRDS(
  "01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.rds"
)

ne_states <- c("MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA")

# ------------------------------------------------------------------------------
# 2. MONTAR BASE ANALÍTICA
# ------------------------------------------------------------------------------
cat("2. Montando base analítica...\n")

base <- base_main |>
  filter(state_abbr %in% ne_states) |>
  select(-starts_with("densidade_real_"), -starts_with("densidade_sintetica")) |>
  left_join(base_future,      by = "code_amc") |>
  left_join(outcomes_interp,  by = "code_amc")

ctrl_clima <- readRDS("01-dados/processados/controles_clima_amcs_nordeste.rds")
ctrl_rios  <- readRDS("01-dados/processados/controles_rios_amcs_nordeste.rds")
ctrl_solo  <- readRDS("01-dados/processados/controles_solo_amcs_nordeste.rds")

base <- base |>
  left_join(ctrl_clima |> select(code_amc, bio_1, bio_12, bio_15),               by = "code_amc") |>
  left_join(ctrl_rios  |> select(code_amc, dist_rio_km, densidade_hidro_km_km2), by = "code_amc") |>
  left_join(ctrl_solo  |> select(code_amc, pct_solo_latossolos, pct_solo_neossolos), by = "code_amc")

cat(sprintf("   AMCs Nordeste na base: %d\n\n", nrow(base)))

# ------------------------------------------------------------------------------
# 3. ANOS DE TRATAMENTO DISPONÍVEIS
# ------------------------------------------------------------------------------
cat("3. Identificando anos de tratamento disponíveis...\n")

cols <- colnames(base)
future_real_cols <- grep("^densidade_buffer_real_future_[0-9]+$", cols, value = TRUE)
treatment_years  <- sort(as.integer(sub("densidade_buffer_real_future_", "", future_real_cols)))

cat(sprintf("   %d anos disponíveis: %d–%d\n\n",
            length(treatment_years), min(treatment_years), max(treatment_years)))

# ------------------------------------------------------------------------------
# 4. MAPEAMENTO DE OUTCOMES CONTEMPORÂNEOS
# ------------------------------------------------------------------------------
# O outcome é o PIB/população do próprio ano T (contemporâneo a T).
# A pergunta: "lugares que receberão ferrovias no futuro já eram mais ricos em T?"
#
# Mapeamento: para cada ano de tratamento T, qual é o outcome mais próximo
# de T disponível na base?

outcomes_map <- tribble(
  ~prefixo,    ~escopo,          ~needs_log,
  "pib",        "PIB_Total",     TRUE,
  "pibag",      "PIB_Agro",      TRUE,
  "pibi",       "PIB_Industria", TRUE,
  "pibse",      "PIB_Servicos",  TRUE,
  "pop_total",  "Populacao",     TRUE
)

extrair_anos <- function(prefix) {
  pattern <- paste0("^", prefix, "_([0-9]+)$")
  anos <- sub(pattern, "\\1", grep(pattern, cols, value = TRUE))
  if (length(anos) == 0) return(integer(0))
  sort(as.integer(anos))
}

outcomes_map <- outcomes_map |>
  mutate(anos_disponiveis = map(prefixo, extrair_anos))

cat("   Outcomes mapeados:\n")
for (i in seq_len(nrow(outcomes_map))) {
  row  <- outcomes_map[i, ]
  anos <- row$anos_disponiveis[[1]]
  if (length(anos) > 0)
    cat(sprintf("   • %-12s %d anos [%d–%d]\n",
                row$prefixo, length(anos), min(anos), max(anos)))
}
cat("\n")

# ------------------------------------------------------------------------------
# 5. CONTROLES FIXOS E FUNÇÃO 2SLS
# ------------------------------------------------------------------------------

fixed_controls <- paste(
  "bio_1", "bio_12", "bio_15",
  "dist_rio_km", "densidade_hidro_km_km2",
  "pct_solo_latossolos", "pct_solo_neossolos",
  sep = " + "
)

rodar_2sls <- function(df, endo_var, inst_var, outcome_col, needs_log,
                       ano_trat, ano_out, escopo) {

  if (!(outcome_col %in% names(df))) return(NULL)

  vals    <- df[[outcome_col]]
  n_valid <- sum(!is.na(vals) & vals > 0, na.rm = TRUE)
  if (n_valid < 15) return(NULL)

  outcome_expr <- if (needs_log) paste0("log(", outcome_col, ")") else outcome_col

  formula_str <- sprintf(
    "%s ~ %s | state_abbr | %s ~ %s",
    outcome_expr, fixed_controls, endo_var, inst_var
  )

  tryCatch({
    mod  <- feols(as.formula(formula_str), data = df, se = "hetero")
    ct   <- summary(mod)$coeftable
    nome <- paste0("fit_", endo_var)
    if (!(nome %in% rownames(ct))) return(NULL)

    tibble(
      ano_tratamento       = ano_trat,
      ano_outcome          = ano_out,
      escopo               = escopo,
      outcome_coluna       = outcome_col,
      variavel_endogena    = endo_var,
      variavel_instrumento = inst_var,
      coeficiente          = ct[nome, 1],
      erro_padrao          = ct[nome, 2],
      t_estatistica        = ct[nome, 3],
      p_valor              = ct[nome, 4],
      F_stat_1estagio      = tryCatch(fitstat(mod, "ivf")[[1]]$stat, error = \(e) NA_real_),
      R2_2estagio          = tryCatch(summary(mod)$r.squared,          error = \(e) NA_real_),
      n_observacoes        = nrow(df),
      significancia        = case_when(
        ct[nome, 4] < 0.01 ~ "***",
        ct[nome, 4] < 0.05 ~ "**",
        ct[nome, 4] < 0.10 ~ "*",
        TRUE               ~ ""
      )
    )
  }, error = \(e) NULL)
}

# ------------------------------------------------------------------------------
# 6. LOOP PRINCIPAL
# ------------------------------------------------------------------------------
cat("4. Rodando regressões de placebo in-time (future density)...\n\n")

resultados_lista <- list()
contador <- 0

for (ano_trat in treatment_years) {

  endo_var <- paste0("densidade_buffer_real_future_",      ano_trat)
  inst_var <- paste0("densidade_buffer_sintetica_future_", ano_trat)

  if (!all(c(endo_var, inst_var) %in% cols)) next

  # Pula anos onde a variação do instrumento é zero (todos os trilhos já passaram)
  if (sum(base[[inst_var]], na.rm = TRUE) == 0) next

  # Excluir pontas deste ano
  codes_pontas <- painel_pontas |>
    filter(ano_corte == ano_trat) |>
    pull(code_amc) |>
    unique()

  df_work <- base |>
    filter(
      !(code_amc %in% codes_pontas),
      is.finite(.data[[endo_var]]),
      is.finite(.data[[inst_var]]),
      !is.na(state_abbr)
    )

  if (nrow(df_work) < 20) next

  for (i in seq_len(nrow(outcomes_map))) {
    row     <- outcomes_map[i, ]
    prefixo <- row$prefixo
    anos_disp <- row$anos_disponiveis[[1]]

    # Outcome contemporâneo: ano mais próximo de T disponível (<=T)
    anos_validos <- anos_disp[anos_disp <= ano_trat]
    if (length(anos_validos) == 0) next
    ano_out     <- max(anos_validos)
    outcome_col <- paste0(prefixo, "_", ano_out)

    res <- rodar_2sls(
      df          = df_work,
      endo_var    = endo_var,
      inst_var    = inst_var,
      outcome_col = outcome_col,
      needs_log   = row$needs_log,
      ano_trat    = ano_trat,
      ano_out     = ano_out,
      escopo      = row$escopo
    )

    if (!is.null(res)) {
      contador <- contador + 1
      resultados_lista[[contador]] <- res
    }
  }
}

cat(sprintf("   → %d regressões concluídas\n\n", contador))

# ------------------------------------------------------------------------------
# 7. COMPILAR E SALVAR
# ------------------------------------------------------------------------------
cat("5. Compilando e salvando resultados...\n")

if (length(resultados_lista) == 0) {
  stop("Nenhuma regressão bem-sucedida. Verifique se base_buffer_future.R foi rodado.")
}

resultados_df <- bind_rows(resultados_lista) |>
  arrange(escopo, ano_tratamento)

dir.create("03-resultados/csv", showWarnings = FALSE, recursive = TRUE)
write_csv(resultados_df, "03-resultados/csv/resultados_placebo_in_time_future.csv")

# ------------------------------------------------------------------------------
# 8. RESUMO
# ------------------------------------------------------------------------------
cat("========================================================================\n")
cat("RESUMO — PLACEBO IN-TIME (FUTURE DENSITY)\n")
cat("========================================================================\n\n")
cat(sprintf("Total de regressões: %d\n", nrow(resultados_df)))
cat(sprintf("Arquivo: 03-resultados/csv/resultados_placebo_in_time_future.csv\n\n"))

cat("Taxa de significância por escopo (esperado: ~5% se exógeno):\n")
resultados_df |>
  group_by(escopo) |>
  summarise(
    n_total    = n(),
    n_sig_005  = sum(p_valor < 0.05, na.rm = TRUE),
    pct_sig    = round(100 * mean(p_valor < 0.05, na.rm = TRUE), 1),
    F_medio    = round(mean(F_stat_1estagio, na.rm = TRUE), 1),
    coef_medio = round(mean(coeficiente, na.rm = TRUE), 4),
    .groups = "drop"
  ) |>
  print(n = 20)

cat("\nResultados significativos (p < 0.05):\n")
sig <- resultados_df |>
  filter(p_valor < 0.05) |>
  select(escopo, ano_tratamento, ano_outcome, coeficiente, p_valor, F_stat_1estagio)

if (nrow(sig) > 0) {
  print(sig, n = 30)
  cat(sprintf(
    "\n⚠  %d de %d regressões significativas (%.1f%%)\n",
    nrow(sig), nrow(resultados_df),
    100 * nrow(sig) / nrow(resultados_df)
  ))
} else {
  cat("✅ Nenhum resultado significativo — placebo aprovado.\n")
}

cat("\n========================================================================\n")
cat("✅ PROCESSO CONCLUÍDO\n")
cat("========================================================================\n")
