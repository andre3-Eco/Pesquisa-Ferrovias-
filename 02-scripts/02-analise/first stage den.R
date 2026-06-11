# ==============================================================================
# FIRST-STAGE: DENSIDADE BUFFER SINTÉTICA vs REAL — SEM PONTAS (POR ANO)
# Baseline OLS (Sem Spatial Lag)
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
cat("FIRST-STAGE: DENSIDADE BUFFER DINÂMICA — SEM PONTAS (SEM SPATIAL LAG)\n")
cat("========================================================================\n\n")

# ------------------------------------------------------------------------------
# 1. CARREGAMENTO DAS BASES TABULARES
# ------------------------------------------------------------------------------
cat("1. Carregando bases de dados...\n")

base_main <- read_csv(
  "01-dados/processados/base_completa_integrada.csv",
  show_col_types = FALSE
)
base_densidade <- read_csv(
  "01-dados/processados/base_densidade_buffer_unificada.csv",
  show_col_types = FALSE
)

ne_states <- c("MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA")

base <- base_main |>
  filter(state_abbr %in% ne_states) |>
  select(-starts_with("densidade_real_"), -starts_with("densidade_sintetica")) |>
  left_join(base_densidade, by = "code_amc")

cat(sprintf("   AMCs Nordeste na base: %d\n", nrow(base)))

# ------------------------------------------------------------------------------
# 2. CARREGAR PAINEL DE PONTAS (EXCLUSÃO TEMPORAL)
# ------------------------------------------------------------------------------
cat("2. Carregando painel de pontas ferroviárias...\n")

painel_pontas <- read_csv(
  "01-dados/processados/painel_amcs_pontas_ano_a_ano.csv",
  show_col_types = FALSE
)

pontas_por_ano <- painel_pontas |>
  select(code_amc, ano_corte) |>
  distinct()

# ------------------------------------------------------------------------------
# 3. CONTROLES AMBIENTAIS E GEOGRÁFICOS
# ------------------------------------------------------------------------------
cat("3. Carregando controles ambientais...\n")

ctrl_clima <- readRDS("01-dados/processados/controles_clima_amcs_nordeste.rds")
ctrl_rios  <- readRDS("01-dados/processados/controles_rios_amcs_nordeste.rds")
ctrl_solo  <- readRDS("01-dados/processados/controles_solo_amcs_nordeste.rds")

base <- base |>
  left_join(ctrl_clima |> select(code_amc, bio_1, bio_12, bio_15),             by = "code_amc") |>
  left_join(ctrl_rios  |> select(code_amc, dist_rio_km, densidade_hidro_km_km2), by = "code_amc") |>
  left_join(ctrl_solo  |> select(code_amc, pct_solo_latossolos, pct_solo_neossolos), by = "code_amc")

cat("   Controles adicionados.\n\n")

# ------------------------------------------------------------------------------
# 4. IDENTIFICAR ANOS DISPONÍVEIS
# ------------------------------------------------------------------------------
cat("4. Identificando anos disponíveis...\n")

cols <- colnames(base)
dens_real_cols <- grep("^densidade_buffer_real_[0-9]+$", cols, value = TRUE)
years <- sort(as.integer(sub("densidade_buffer_real_", "", dens_real_cols)))

cat(sprintf("   %d anos disponíveis: %d–%d\n\n", length(years), min(years), max(years)))

# ------------------------------------------------------------------------------
# 5. LOOP PRINCIPAL: PRIMEIRO ESTÁGIO POR ANO
# ------------------------------------------------------------------------------
cat("5. Rodando regressões de primeiro estágio (sem lag espacial)...\n\n")

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
  
  # Pontas deste ano específico
  codes_pontas_ano <- pontas_por_ano |>
    filter(ano_corte == ano) |>
    pull(code_amc) |>
    unique()
  
  # Montar dados da regressão
  df <- base |>
    select(
      code_amc, state_abbr,
      all_of(endo_var),
      all_of(inst_var),
      bio_1, bio_12, bio_15,
      dist_rio_km, densidade_hidro_km_km2,
      pct_solo_latossolos, pct_solo_neossolos
    ) |>
    # Excluir AMCs que eram pontas NESTE ano
    filter(!(code_amc %in% codes_pontas_ano)) |>
    filter(
      is.finite(.data[[endo_var]]),
      is.finite(.data[[inst_var]]),
      !is.na(state_abbr)
    )
  
  if (nrow(df) < 10) next
  
  n_excluidas <- sum(base$code_amc %in% codes_pontas_ano)
  
  # Formula simplificada: endo ~ inst + controles | state_abbr
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
# 6. COMPILAR E SALVAR
# ------------------------------------------------------------------------------
cat("\n6. Compilando resultados...\n")

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

output_file <- "03-resultados/csv/first_stage_buffer_density_sem_pontas_baseline.csv"
write_csv(resultados_df, output_file)
cat(sprintf("   ✓ Resultados salvos em: %s\n\n", output_file))

# ------------------------------------------------------------------------------
# 7. RESUMO DIAGNÓSTICO
# ------------------------------------------------------------------------------
cat("========================================================================\n")
cat("   RESUMO: FORÇA DO INSTRUMENTO (BASELINE SEM LAG ESPACIAL)\n")
cat("========================================================================\n")
cat(sprintf("Total de regressões: %d\n", nrow(resultados_df)))

n_forte <- sum(resultados_df$instrumento_forte)
cat(sprintf("Instrumento forte (F ≥ 10): %d/%d anos (%.0f%%)\n",
            n_forte, nrow(resultados_df), 100 * n_forte / nrow(resultados_df)))

cat("\nDistribuição do F-statistic:\n")
print(summary(resultados_df$F_estatistica))
cat("\n✅ PROCESSO CONCLUÍDO.\n")