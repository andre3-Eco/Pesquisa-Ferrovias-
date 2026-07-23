# =============================================================================
# Etapa 27 - DADOS MAIS RECENTES DE PIB
#
# Extrai e harmoniza o outcome principal para as AMCs:
#   1. PIB Total a preços correntes (2021 e 2023 | SIDRA tabela 5938)
# =============================================================================

library(sidrar)
library(tidyverse)

# ── Diretórios ────────────────────────────────────────────────────────────────
DIR_BRUTOS <- "01-dados/brutos/outcomes_recentes"
DIR_PROC   <- "01-dados/processados/outcomes_recentes"
dir.create(DIR_BRUTOS, showWarnings = FALSE, recursive = TRUE)
dir.create(DIR_PROC,   showWarnings = FALSE, recursive = TRUE)

# =============================================================================
# 0. MAPEAMENTO MUNICÍPIO → AMC
# =============================================================================

amcs_geometria <- readRDS(paste0(data.wd, "/01-dados/processados/amcs_geometria.rds"))

amc_map <- amcs_geometria |>
  mutate(
    list_code_muni_2010 = str_split(list_code_muni_2010, ",\\s*")
  ) |>
  unnest(list_code_muni_2010) |>
  mutate(
    code_muni = as.integer(list_code_muni_2010),
    code_amc  = as.integer(code_amc)
  ) |>
  select(code_muni, code_amc) |>
  filter(!is.na(code_muni))

ne_amcs  <- sort(unique(amc_map$code_amc))
ne_munis <- unique(amc_map$code_muni[amc_map$code_amc %in% ne_amcs])

estados_ne <- c(21, 22, 23, 24, 25, 26, 27, 28, 29)

cat("Municípios NE no mapeamento :", length(ne_munis), "\n")
cat("AMCs NE na base do projeto  :", length(ne_amcs), "\n\n")

# =============================================================================
# ESCOPO 1 – PIB TOTAL (SIDRA - Tabela 5938)
# =============================================================================
cat("Iniciando extração do PIB Total (SIDRA)...\n")

pib_raw_list <- list()

for (uf in estados_ne) {
  cat("  Estado", uf, "... ")
  tryCatch({
    df <- get_sidra(
      x          = 5938,
      variable   = 37,             # Apenas PIB Total
      period     = c("2021", "2023"), 
      geo        = "City",
      geo.filter = list("State" = uf)
    )
    cat("OK (", nrow(df), "obs)\n")
    pib_raw_list[[as.character(uf)]] <- df
  }, error = function(e) {
    cat("ERRO:", conditionMessage(e), "\n")
  })
}

raw_pib_tidy <- bind_rows(pib_raw_list) |>
  transmute(
    code_muni = as.integer(`Município (Código)`),
    ano       = as.integer(`Ano (Código)`),
    serie     = "PIB",
    value     = suppressWarnings(as.numeric(Valor))
  ) |>
  filter(!is.na(value), code_muni %in% ne_munis)

write_csv(raw_pib_tidy, file.path(DIR_BRUTOS, "pib_municipal_ne_21_23.csv"))
cat("Salvo: pib_municipal_ne_21_23.csv\n\n")

# =============================================================================
# HARMONIZAÇÃO PARA AMC E CONSOLIDAÇÃO WIDE
# =============================================================================

harmonizar_soma <- function(df) {
  df |>
    inner_join(amc_map, by = "code_muni") |>
    filter(code_amc %in% ne_amcs) |>
    group_by(serie, code_amc, ano) |> 
    summarise(
      value   = sum(value, na.rm = TRUE), 
      .groups = "drop"
    ) |>
    rename(ano_ref = ano)
}

pib_amc <- harmonizar_soma(raw_pib_tidy)

para_wide_recente <- function(df) {
  df |>
    mutate(col_name = paste0(tolower(serie), "_", ano_ref)) |>
    select(code_amc, col_name, value) |>
    pivot_wider(names_from = col_name, values_from = value, values_fn = mean)
}

pib_wide <- para_wide_recente(pib_amc)

base_outcomes_recente <- tibble(code_amc = ne_amcs) |>
  left_join(pib_wide, by = "code_amc")

cat("Base final consolidada: ", nrow(base_outcomes_recente), " AMCs × ", ncol(base_outcomes_recente), " colunas\n", sep = "")

write_csv(base_outcomes_recente, file.path(DIR_PROC, "outcomes_pib_amc_recente.csv"))
saveRDS(base_outcomes_recente,   file.path(DIR_PROC, "outcomes_pib_amc_recente.rds"))

# =============================================================================
# MERGE: Integrar PIB Recente (2021/2023) à Base Principal
# =============================================================================

library(tidyverse)


caminho_base_principal <- "C:/Users/André Elias/Documents/Pesquisa (Ferrovias)/01-dados/processados/base_completa_integrada_buffer.csv"
caminho_pib_recente    <- "01-dados/processados/outcomes_recentes/outcomes_pib_amc_recente.csv"


base_principal <- read_csv(caminho_base_principal, show_col_types = FALSE)


base_pib_recente <- read_csv(caminho_pib_recente, show_col_types = FALSE)

base_final <- base_principal |>
  left_join(base_pib_recente, by = "code_amc")

caminho_salvamento <- str_replace(caminho_base_principal, "\\.csv$", "_com_pib_recente.csv")

write_csv(base_final, caminho_salvamento)

