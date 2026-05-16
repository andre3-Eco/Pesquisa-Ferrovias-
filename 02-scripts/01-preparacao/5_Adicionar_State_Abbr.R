# ==============================================================================
# ADICIONAR COLUNA state_abbr À BASE INTEGRADA
# ==============================================================================
# Script que adiciona a abreviatura do estado (UF) para cada AMC
# Extrai do código IBGE do município (2 primeiros dígitos)
# ==============================================================================

cat("\n", strrep("=", 80), "\n")
cat("ADICIONANDO COLUNA state_abbr À BASE INTEGRADA\n")
cat("Data:", format(Sys.time(), "%d/%m/%Y %H:%M:%S"), "\n")
cat(strrep("=", 80), "\n\n")

if (!exists("data.wd")) data.wd <- getwd()

library(tidyverse)
library(geobr)

# ==============================================================================
# SEÇÃO 1: CARREGAMENTO DA BASE
# ==============================================================================

cat("ETAPA 1: Carregando base integrada...\n\n")

base_completa <- read_csv(
  paste0(data.wd, "/01-dados/processados/base_completa_integrada.csv"),
  show_col_types = FALSE
)

cat(sprintf("  ✓ Base carregada: %d linhas × %d colunas\n", 
            nrow(base_completa), ncol(base_completa)))

# ==============================================================================
# SEÇÃO 2: CRIAR MAPEAMENTO DE ESTADO
# ==============================================================================

cat("\nETAPA 2: Criando mapeamento de estado...\n\n")

# Mapeamento IBGE: código de estado → UF
estado_map <- data.frame(
  codigo_estado = c(11, 12, 13, 14, 15, 16, 17, 21, 22, 23, 24, 25, 26, 27, 28, 29, 
                    31, 32, 33, 35, 41, 42, 43, 50, 51, 52, 53, 53),
  state_abbr = c("RO", "AC", "AM", "RR", "AP", "PA", "TO", "MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA",
                 "MG", "ES", "RJ", "SP", "PR", "SC", "RS", "MS", "MT", "GO", "DF", "DF"),
  stringsAsFactors = FALSE
)

cat("  Estados IBGE mapeados:\n")
for (i in 1:nrow(estado_map)) {
  cat(sprintf("    %d → %s\n", estado_map$codigo_estado[i], estado_map$state_abbr[i]))
}

# ==============================================================================
# SEÇÃO 3: OBTER MAPEAMENTO code_amc → ESTADO VIA geobr
# ==============================================================================

cat("\nETAPA 3: Obtendo mapeamento de estado para cada AMC...\n\n")

cat("  • Carregando geometria das AMCs do geobr...\n")
amcs_info <- read_comparable_areas(start_year = 1970, end_year = 2010) |>
  st_drop_geometry() |>
  select(code_amc, list_code_muni_2010) |>
  distinct(code_amc, .keep_all = TRUE) |>
  mutate(
    # Extrair código de estado (2 primeiros dígitos do código de município)
    codigo_estado = as.integer(substr(list_code_muni_2010, 1, 2))
  ) |>
  left_join(estado_map, by = "codigo_estado") |>
  select(code_amc, state_abbr)

cat(sprintf("    ✓ %d AMCs mapeados\n", nrow(amcs_info)))

# Verificar se há NA
na_states <- sum(is.na(amcs_info$state_abbr))
if (na_states > 0) {
  cat(sprintf("    ⚠️  Atenção: %d AMCs com estado não identificado\n", na_states))
}

# Contar estados
cat("\n  Estados únicos obtidos:\n")
states_unique <- amcs_info |>
  filter(!is.na(state_abbr)) |>
  distinct(state_abbr) |>
  arrange(state_abbr) |>
  pull(state_abbr)

cat(sprintf("    %s\n", paste(states_unique, collapse = ", ")))

# ==============================================================================
# SEÇÃO 4: ADICIONAR state_abbr À BASE
# ==============================================================================

cat("\nETAPA 4: Adicionando coluna state_abbr à base...\n\n")

# Merge com base_completa
base_completa <- base_completa |>
  left_join(amcs_info, by = "code_amc")

# Verificar se há NA
na_state <- sum(is.na(base_completa$state_abbr))
if (na_state == 0) {
  cat(sprintf("  ✓ Coluna state_abbr adicionada sem valores ausentes\n"))
} else {
  cat(sprintf("  ⚠️  Atenção: %d valores NA em state_abbr\n", na_state))
}

# Contar estados
cat("\n  Distribuição de AMCs por estado:\n")
states_count <- base_completa |>
  count(state_abbr) |>
  arrange(state_abbr)

for (i in 1:nrow(states_count)) {
  cat(sprintf("    %s: %d AMCs\n", states_count$state_abbr[i], states_count$n[i]))
}

# ==============================================================================
# SEÇÃO 5: REORDENAR COLUNAS
# ==============================================================================

cat("\nETAPA 5: Reordenando colunas...\n\n")

# Colocar state_abbr logo após code_amc
colunas_novo_ordem <- c(
  "code_amc",
  "state_abbr",
  "area_km2",
  setdiff(colnames(base_completa), c("code_amc", "state_abbr", "area_km2"))
)

base_completa <- base_completa |>
  select(all_of(colunas_novo_ordem))

cat(sprintf("  ✓ Colunas reordenadas\n"))
cat(sprintf("  ✓ Primeiras 5 colunas: %s\n", 
            paste(colnames(base_completa)[1:5], collapse = ", ")))

# ==============================================================================
# SEÇÃO 6: EXPORTAR BASE ATUALIZADA
# ==============================================================================

cat("\nETAPA 6: Exportando base atualizada...\n\n")

# Salvar em CSV
arquivo_csv <- paste0(data.wd, "/01-dados/processados/base_completa_integrada.csv")
write_csv(base_completa, arquivo_csv)
cat(sprintf("  ✓ CSV atualizado: %s\n", arquivo_csv))

# Salvar em RDS
arquivo_rds <- paste0(data.wd, "/01-dados/processados/base_completa_integrada.rds")
saveRDS(base_completa, arquivo_rds)
cat(sprintf("  ✓ RDS atualizado: %s\n", arquivo_rds))


