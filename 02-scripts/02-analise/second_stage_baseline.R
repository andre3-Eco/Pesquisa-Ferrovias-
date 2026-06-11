# ==============================================================================
# SECOND-STAGE IV (2SLS): DENSIDADE BUFFER SINTÉTICA → REAL — SEM PONTAS
# Instrumento: densidade_buffer_sintetica_YYYY → densidade_buffer_real_YYYY
# Outcomes: PIB e população (persistência + contemporâneos)
# Baseline: Sem Spatial Lag
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
cat("SECOND-STAGE IV: DENSIDADE BUFFER — SEM PONTAS (SEM SPATIAL LAG)\n")
cat("========================================================================\n\n")

# ------------------------------------------------------------------------------
# 1. CARREGAR BASES TABULARES
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
# 2. CARREGAR PAINEL DE PONTAS
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
# 4. CARREGAR OUTCOMES INTERPOLADOS
# ------------------------------------------------------------------------------
cat("4. Carregando outcomes interpolados...\n")

outcomes_interp <- readRDS(
  "01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.rds"
)

outcomes_selecionados <- outcomes_interp |>
  select(
    code_amc,
    # PIB histórico
    pib_1920, pib_1939, pib_1949, pib_1959,
    pib_1970, pib_1975, pib_1980, pib_1985,
    pib_1996, pib_1999, pib_2000, pib_2003, pib_2010,
    # População total
    pop_total_1940, pop_total_1950, pop_total_1960,
    pop_total_1970, pop_total_1980, pop_total_1991,
    pop_total_1996, pop_total_2000, pop_total_2010
  )

base <- base |>
  left_join(outcomes_selecionados, by = "code_amc")

cat(sprintf("   Outcomes adicionados. Base final: %d AMCs × %d colunas\n\n",
            nrow(base), ncol(base)))

# ------------------------------------------------------------------------------
# 5. IDENTIFICAR ANOS DISPONÍVEIS DO TRATAMENTO
# ------------------------------------------------------------------------------
cat("5. Identificando anos disponíveis do tratamento...\n")

cols <- colnames(base)
dens_real_cols <- grep("^densidade_buffer_real_[0-9]+$", cols, value = TRUE)
years <- sort(as.integer(sub("densidade_buffer_real_", "", dens_real_cols)))

cat(sprintf("   %d anos disponíveis: %d–%d\n\n", length(years), min(years), max(years)))

# ------------------------------------------------------------------------------
# 6. DEFINIR OUTCOMES E CONTROLES
# ------------------------------------------------------------------------------

fixed_controls <- paste(
  "bio_1", "bio_12", "bio_15",
  "dist_rio_km", "densidade_hidro_km_km2",
  "pct_solo_latossolos", "pct_solo_neossolos",
  sep = " + "
)

# Outcomes de persistência
outcomes_persistencia <- c(
  "log(pib_2010)",
  "log(pib_2003)",
  "log(pop_total_2010)",
  "log(pop_total_2000)"
)

# Outcomes contemporâneos
contemporaneo_map <- tribble(
  ~ano_min, ~ano_max, ~outcome_pib,         ~outcome_pop,
  1858,     1929,     "log(pib_1920)",       "log(pop_total_1940)",
  1930,     1938,     "log(pib_1939)",       "log(pop_total_1940)",
  1939,     1948,     "log(pib_1939)",       "log(pop_total_1940)",
  1949,     1958,     "log(pib_1949)",       "log(pop_total_1950)",
  1959,     1969,     "log(pib_1959)",       "log(pop_total_1960)",
  1970,     1974,     "log(pib_1970)",       "log(pop_total_1970)",
  1975,     1979,     "log(pib_1975)",       "log(pop_total_1970)",
  1980,     1984,     "log(pib_1980)",       "log(pop_total_1980)",
  1985,     1995,     "log(pib_1985)",       "log(pop_total_1991)",
  1996,     1998,     "log(pib_1996)",       "log(pop_total_1996)",
  1999,     1999,     "log(pib_1999)",       "log(pop_total_2000)",
  2000,     2002,     "log(pib_2000)",       "log(pop_total_2000)",
  2003,     2003,     "log(pib_2003)",       "log(pop_total_2000)"
)

get_contemporaneo <- function(ano) {
  row <- contemporaneo_map |> filter(ano >= ano_min, ano <= ano_max)
  if (nrow(row) == 0) return(NULL)
  list(pib = row$outcome_pib[1], pop = row$outcome_pop[1])
}

# ------------------------------------------------------------------------------
# 7. FUNÇÃO AUXILIAR: RODAR 2SLS (CORRIGIDA PARA fixest)
# ------------------------------------------------------------------------------

rodar_2sls <- function(df, endo_var, inst_var, outcome_var, ano, tipo_outcome) {
  
  outcome_col <- gsub("log\\(|\\)", "", outcome_var)
  if (!(outcome_col %in% names(df))) return(NULL)
  
  vals <- df[[outcome_col]]
  if (sum(!is.na(vals) & vals > 0, na.rm = TRUE) < 10) return(NULL)
  
  form_str <- sprintf(
    "%s ~ %s | state_abbr | %s ~ %s",
    outcome_var, fixed_controls, endo_var, inst_var
  )
  
  tryCatch({
    mod <- feols(as.formula(form_str), data = df, se = "hetero")
    
    ct <- summary(mod)$coeftable
    
    # AQUI ESTÁ A CORREÇÃO: O fixest adiciona "fit_" ao nome da variável endógena.
    nome_endo_fixest <- paste0("fit_", endo_var)
    
    if (!(nome_endo_fixest %in% rownames(ct))) return(NULL)
    
    coef_val <- ct[nome_endo_fixest, 1]   # Estimate
    se_val   <- ct[nome_endo_fixest, 2]   # Std. Error
    t_val    <- ct[nome_endo_fixest, 3]   # t value
    p_val    <- ct[nome_endo_fixest, 4]   # Pr(>|t|)
    
    f_stat <- tryCatch({
      fitstat(mod, "ivf")[[1]]$stat
    }, error = function(e) NA_real_)
    
    tibble(
      ano                  = ano,
      tipo_outcome         = tipo_outcome,
      outcome_var          = outcome_var,
      variavel_endogena    = endo_var,
      variavel_instrumento = inst_var,
      coeficiente          = coef_val,
      erro_padrao          = se_val,
      t_estatistica        = t_val,
      p_valor              = p_val,
      F_stat_1estagio      = f_stat,
      n_observacoes        = nrow(df)
    )
  }, error = function(e) {
    cat(sprintf("  ⚠ Erro [ano=%d, outcome=%s]: %s\n", ano, outcome_var, e$message))
    NULL
  })
}

# ------------------------------------------------------------------------------
# 8. LOOP PRINCIPAL: SEGUNDO ESTÁGIO POR ANO
# ------------------------------------------------------------------------------
cat("6. Rodando regressões de segundo estágio (2SLS)...\n\n")

resultados <- list()
contador   <- 0

for (ano in years) {
  
  endo_var <- paste0("densidade_buffer_real_",      ano)
  inst_var <- paste0("densidade_buffer_sintetica_", ano)
  
  if (!all(c(endo_var, inst_var) %in% cols)) next
  if (sum(base[[inst_var]], na.rm = TRUE) == 0) next
  
  # Excluir pontas deste ano
  codes_pontas_ano <- pontas_por_ano |>
    filter(ano_corte == ano) |>
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
  
  # ── 8A. PERSISTÊNCIA: outcomes fixos × tratamento de cada ano ───────────────
  for (oc_var in outcomes_persistencia) {
    res <- rodar_2sls(df, endo_var, inst_var, oc_var, ano, "persistencia")
    if (!is.null(res)) {
      contador <- contador + 1
      resultados[[paste0("p_", ano, "_", oc_var)]] <- res
    }
  }
  
  # ── 8B. CONTEMPORÂNEO: outcome do mesmo período ───────────────────────────
  ct <- get_contemporaneo(ano)
  if (!is.null(ct)) {
    for (oc_var in unique(c(ct$pib, ct$pop))) {
      res <- rodar_2sls(df, endo_var, inst_var, oc_var, ano, "contemporaneo")
      if (!is.null(res)) {
        contador <- contador + 1
        resultados[[paste0("c_", ano, "_", oc_var)]] <- res
      }
    }
  }
  
  if (which(years == ano) %% 15 == 0) {
    cat(sprintf("  → Ano %d (%d/%d) | n=%d | regressões acumuladas: %d\n",
                ano, which(years == ano), length(years), nrow(df), contador))
  }
}

# ------------------------------------------------------------------------------
# 9. COMPILAR E SALVAR
# ------------------------------------------------------------------------------
cat("\n7. Compilando resultados...\n")

if (length(resultados) == 0) stop("Nenhuma regressão bem-sucedida.")

resultados_df <- bind_rows(resultados)

# Adicionar indicativo de estrelas de significância
resultados_df <- resultados_df |>
  mutate(
    significancia = case_when(
      p_valor < 0.01 ~ "***",
      p_valor < 0.05 ~ "**",
      p_valor < 0.10 ~ "*",
      TRUE           ~ ""
    ),
    coeficiente_sig = sprintf("%+.4f%s", coeficiente, significancia)
  )

output_file <- "03-resultados/csv/second_stage_buffer_density_sem_pontas_baseline.csv"
write_csv(resultados_df, output_file)

cat("========================================================================\n")
cat("   RESUMO DA EXECUÇÃO\n")
cat("========================================================================\n")
cat(sprintf("Total de regressões rodadas e salvas: %d\n", nrow(resultados_df)))
cat(sprintf("Arquivo gerado em: %s\n", output_file))
cat("\n✅ PROCESSO CONCLUÍDO COM SUCESSO!\n")