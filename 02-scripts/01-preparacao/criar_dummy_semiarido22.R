# =============================================================================
# Etapa 22
# Objetivo: Criar dummy 'semiarido' na base_completa_integrada_buffer.csv
#           indicando se o AMC pertence ao semiárido brasileiro.
#
# Lógica:
#   1. Carrega lista de municípios do semiárido (CD_MUN)
#   2. Carrega geometria dos AMCs (list_code_muni_2010)
#   3. Para cada AMC, verifica se algum de seus municípios está na lista
#   4. Atribui dummy = 1 se sim, 0 caso contrário
#   5. Merge na base principal e salva
# =============================================================================

library(readxl)
library(dplyr)

# ---- Caminhos ----
p_semiarido  <- "C:/Users/André Elias/Documents/Pesquisa (Ferrovias)/01-dados/brutos/lista_municipios_Semiarido_2022.xlsx"
p_amcs       <- "C:/Users/André Elias/Documents/Pesquisa (Ferrovias)/amcs_geometria.rds"
p_base       <- "C:/Users/André Elias/Documents/Pesquisa (Ferrovias)/01-dados/processados/base_completa_integrada_buffer.csv"
p_saida      <- "C:/Users/André Elias/Documents/Pesquisa (Ferrovias)/01-dados/processados/base_completa_integrada_buffer.csv"

# ---- 1. Carregar lista de municípios do semiárido ----

df_semi <- read_excel(p_semiarido)
cat("  Municípios no semiárido:", nrow(df_semi), "\n")

# Garantir que CD_MUN é character para comparação
codigos_semiarido <- as.character(df_semi$CD_MUN)
cat("  Exemplo de códigos:", paste(head(codigos_semiarido, 5), collapse = ", "), "\n")

# ---- 2. Carregar geometria dos AMCs ----

library(sf)
amcs <- readRDS(p_amcs)
cat("  AMCs carregados:", nrow(amcs), "\n")

# Extrair só as colunas necessárias (sem geometria)
amcs_df <- amcs %>%
  st_drop_geometry() %>%
  select(code_amc, list_code_muni_2010)

# ---- 3. Determinar quais AMCs pertencem ao semiárido ----


# Para cada AMC, split dos códigos de município e verifica interseção
amcs_semiarido <- amcs_df %>%
  rowwise() %>%
  mutate(
    # Split da string de códigos por vírgula
    muni_codes = list(trimws(strsplit(list_code_muni_2010, ",")[[1]])),
    # Verifica se algum código está na lista do semiárido
    semiarido = as.integer(any(muni_codes %in% codigos_semiarido))
  ) %>%
  ungroup() %>%
  select(code_amc, semiarido)

# Resumo
n_semi <- sum(amcs_semiarido$semiarido)
cat("  AMCs no semiárido:", n_semi, "de", nrow(amcs_semiarido),
    sprintf("(%.1f%%)", 100 * n_semi / nrow(amcs_semiarido)), "\n")

# Verificar uns exemplos

print(head(amcs_semiarido, 10))

# ---- 4. Merge na base principal ----

base <- read.csv(p_base, stringsAsFactors = FALSE)
cat("  Linhas:", nrow(base), "| Colunas:", ncol(base), "\n")

# Verificar se code_amc existe
if (!"code_amc" %in% names(base)) {
  stop("Coluna 'code_amc' não encontrada na base principal!")
}

# Merge (left_join para preservar todas as linhas)
base <- base %>%
  left_join(amcs_semiarido, by = "code_amc")

# AMCs sem match (NA) viram 0 (não estão no shapefile = não classificados)
base$semiarido[is.na(base$semiarido.x)] <- 0


cat("  Após merge: semiarido = 1:", sum(base$semiarido == 1),
    "| semiarido = 0:", sum(base$semiarido == 0), "\n")

# ---- 5. Salvar ----

write.csv(base, p_saida, row.names = FALSE)
cat("  Arquivo salvo:", p_saida, "\n")

# ---- Validação rápida ----

cat("Linhas na base:", nrow(base), "\n")
cat("Colunas na base:", ncol(base), "\n")
cat("Tabela semiarido:\n")
print(table(base$semiarido, dnn = "semiarido"))
cat("\nAlguns AMCs do semiárido com seus estados:\n")
base %>%
  filter(semiarido == 1) %>%
  select(code_amc, state_abbr, semiarido) %>%
  head(10) %>%
  print()

