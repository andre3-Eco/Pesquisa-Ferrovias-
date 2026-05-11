# ==============================================================================
# INTEGRAR AS TRÊS BASES DE DADOS EM UMA ÚNICA BASE ANALÍTICA
# ==============================================================================
# Este script integra:
#   1. base_distancias_amcs_nordeste_semmar.csv
#   2. base_dummy_atendimento_ferrovias.csv
#   3. base_densidade_ferrovias.csv
# ==============================================================================

# 1. PACOTES E CONFIGURAÇÕES ---------------------------------------------------
library(tidyverse)

cat("========================================================================\n")
cat("INTEGRANDO TRÊS BASES DE ANÁLISE\n")
cat("========================================================================\n\n")

if (!exists("data.wd")) data.wd <- getwd()

# 2. CARREGAMENTO DAS TRÊS BASES -----------------------------------------------
cat("Etapa 1: Carregando as três bases de dados...\n\n")

## 2a. Base de distâncias
cat("  → Carregando base de distâncias...\n")
base_distancias <- read_csv(
  paste0(data.wd, "/base_distancias_amcs_nordeste_semmar.csv"),
  show_col_types = FALSE
)

cat(sprintf("    ✓ %d linhas, %d colunas\n\n", nrow(base_distancias), ncol(base_distancias)))

## 2b. Base de dummy
cat("  → Carregando base de dummy de atendimento...\n")
base_dummy <- read_csv(
  paste0(data.wd, "/base_dummy_atendimento_simples.csv"),
  show_col_types = FALSE
)

cat(sprintf("    ✓ %d linhas, %d colunas\n\n", nrow(base_dummy), ncol(base_dummy)))

## 2c. Base de densidade simplificada
cat("  → Carregando base de densidade...\n")
base_densidade <- read_csv(
  paste0(data.wd, "/base_densidade_simplificada.csv"),
  show_col_types = FALSE
)

cat(sprintf("    ✓ %d linhas, %d colunas\n\n", nrow(base_densidade), ncol(base_densidade)))

# 3. INTEGRAÇÃO DAS BASES ------------------------------------------------------
cat("Etapa 2: Integrando bases por code_amc...\n\n")

# Verificar se todas as bases têm as mesmas AMCs
n_amcs_dist <- nrow(base_distancias)
n_amcs_dummy <- nrow(base_dummy)
n_amcs_dens <- nrow(base_densidade)

cat(sprintf("  • Base distâncias: %d AMCs\n", n_amcs_dist))
cat(sprintf("  • Base dummy: %d AMCs\n", n_amcs_dummy))
cat(sprintf("  • Base densidade: %d AMCs\n", n_amcs_dens))

if (!(n_amcs_dist == n_amcs_dummy && n_amcs_dummy == n_amcs_dens)) {
  cat("\n  ⚠ Aviso: As bases têm número diferente de AMCs!\n")
  cat("           Será feito um inner_join (apenas AMCs em comum)\n\n")
}

# Fazer o merge (inner join para garantir consistência)
base_integrada <- base_distancias |>
  inner_join(base_dummy, by = "code_amc") |>
  inner_join(base_densidade, by = "code_amc")

cat(sprintf("  ✓ Base integrada: %d AMCs, %d colunas\n\n", nrow(base_integrada), ncol(base_integrada)))

# 4. VERIFICAÇÃO DE DUPLICATAS E MISSINGS ------------------------------------
cat("Etapa 3: Verificando integridade dos dados...\n\n")

# Verificar duplicatas
duplicatas <- base_integrada |>
  group_by(code_amc) |>
  filter(n() > 1) |>
  ungroup()

if (nrow(duplicatas) == 0) {
  cat("  ✓ Nenhuma duplicata de code_amc\n\n")
} else {
  cat(sprintf("  ⚠ %d registros duplicados detectados!\n\n", nrow(duplicatas)))
}

# Verificar missings
missing_summary <- base_integrada |>
  summarise(across(everything(), ~sum(is.na(.)))) |>
  pivot_longer(everything()) |>
  filter(value > 0) |>
  arrange(desc(value))

if (nrow(missing_summary) == 0) {
  cat("  ✓ Sem valores ausentes na base integrada\n\n")
} else {
  cat("  ⚠ Valores ausentes detectados:\n")
  print(missing_summary)
  cat("\n")
}

# 5. REORGANIZAÇÃO E RENOMEAÇÃO DE COLUNAS ------------------------------------
cat("Etapa 4: Reorganizando colunas para melhor legibilidade...\n\n")

# Obter lista de anos únicos (a partir dos nomes das colunas)
anos_dist <- grep("dist_rail_real_", names(base_integrada), value = TRUE) |>
  str_extract("[0-9]+$") |>
  as.numeric() |>
  sort()

cat(sprintf("  • Anos de ferrovia real: %d períodos (%d a %d)\n\n",
            length(anos_dist), min(anos_dist), max(anos_dist)))

# Reorganizar: code_amc + síntética + variáveis reais (ordenadas por ano)
cols_sintet <- c("code_amc", "area_km2", 
                 "dist_rail_sintetica_km", 
                 "dummy_atendida_sintetica",
                 "densidade_sintetica")

cols_dist_real <- grep("^dist_rail_real_", names(base_integrada), value = TRUE) |> sort()
cols_dummy_real <- grep("^dummy_atendida_real_", names(base_integrada), value = TRUE) |> sort()
cols_dens_real <- grep("^densidade_real_", names(base_integrada), value = TRUE) |> sort()

base_integrada <- base_integrada |>
  select(
    all_of(cols_sintet),
    all_of(cols_dist_real),
    all_of(cols_dummy_real),
    all_of(cols_dens_real)
  )

cat(sprintf("  ✓ Colunas reorganizadas em ordem lógica\n\n"))

# 6. VALIDAÇÃO DE RELAÇÕES LÓGICAS ENTRE VARIÁVEIS ---------------------------
cat("Etapa 5: Validando relações lógicas entre variáveis...\n\n")

# Verificar: dummy deve ser 1 quando distância está dentro do limiar
# (Note: limiar usado em dummy_atendimento foi de 25 km por padrão)
LIMIAR_PADRAO <- 25

inconsistencias <- 0
for (ano in anos_dist) {
  col_dist <- paste0("dist_rail_real_", ano)
  col_dummy <- paste0("dummy_atendida_real_", ano)
  
  if (col_dist %in% names(base_integrada) && col_dummy %in% names(base_integrada)) {
    # Verificar se dummy é consistente com distância (limiar de 25 km)
    inconsistent_rows <- base_integrada |>
      filter(
        (!!rlang::sym(col_dummy) == 1 & !!rlang::sym(col_dist) > LIMIAR_PADRAO) |
        (!!rlang::sym(col_dummy) == 0 & !!rlang::sym(col_dist) <= LIMIAR_PADRAO)
      ) |>
      nrow()
    
    inconsistencias <- inconsistencias + inconsistent_rows
  }
}

if (inconsistencias == 0) {
  cat(sprintf("  ✓ Relações lógicas validadas (limiar: %.0f km)\n\n", LIMIAR_PADRAO))
} else {
  cat(sprintf("  ⚠ %d registros com relações lógicas inconsistentes\n\n", inconsistencias))
}

# 7. ESTATÍSTICAS DESCRITIVAS GERAIS ------------------------------------------
cat("Etapa 6: Gerando estatísticas descritivas...\n\n")

cat("DIMENSÕES DA BASE INTEGRADA:\n")
cat(sprintf("  • Linhas: %d AMCs\n", nrow(base_integrada)))
cat(sprintf("  • Colunas: %d\n", ncol(base_integrada)))
cat(sprintf("  • Períodos: %d (de %d a %d)\n\n", 
            length(anos_dist), min(anos_dist), max(anos_dist)))

cat("COMPOSIÇÃO DE VARIÁVEIS:\n")
cat(sprintf("  • Identificador: 1 (code_amc)\n"))
cat(sprintf("  • Controles: 2 (area_km2, e coluna code_amc)\n"))
cat(sprintf("  • Sintética: 3 (distância, dummy, densidade)\n"))
cat(sprintf("  • Reais cronológicas: %d (3 tipos × %d períodos)\n\n", 
            3 * length(anos_dist), length(anos_dist)))

# Estatísticas das variáveis chave
cat("ESTATÍSTICAS CHAVE:\n\n")

cat("Distâncias (km):\n")
cat(sprintf("  Sintética - Média: %.1f | Med: %.1f | Max: %.1f\n",
            mean(base_integrada$dist_rail_sintetica_km, na.rm = TRUE),
            median(base_integrada$dist_rail_sintetica_km, na.rm = TRUE),
            max(base_integrada$dist_rail_sintetica_km, na.rm = TRUE)))

col_dist_2003 <- "dist_rail_real_2003"
if (col_dist_2003 %in% names(base_integrada)) {
  cat(sprintf("  Real 2003  - Média: %.1f | Med: %.1f | Max: %.1f\n\n",
              mean(base_integrada[[col_dist_2003]], na.rm = TRUE),
              median(base_integrada[[col_dist_2003]], na.rm = TRUE),
              max(base_integrada[[col_dist_2003]], na.rm = TRUE)))
}

cat("Densidades (km/1000 km²):\n")
cat(sprintf("  Sintética - Média: %.2f | Med: %.2f | Max: %.2f\n",
            mean(base_integrada$densidade_sintetica, na.rm = TRUE),
            median(base_integrada$densidade_sintetica, na.rm = TRUE),
            max(base_integrada$densidade_sintetica, na.rm = TRUE)))

col_dens_2003 <- "densidade_real_2003"
if (col_dens_2003 %in% names(base_integrada)) {
  cat(sprintf("  Real 2003  - Média: %.2f | Med: %.2f | Max: %.2f\n\n",
              mean(base_integrada[[col_dens_2003]], na.rm = TRUE),
              median(base_integrada[[col_dens_2003]], na.rm = TRUE),
              max(base_integrada[[col_dens_2003]], na.rm = TRUE)))
}

cat("Atendimento (proporção com dummy = 1):\n")
cat(sprintf("  Sintética - %.1f%% das AMCs atendidas\n",
            100 * mean(base_integrada$dummy_atendida_sintetica, na.rm = TRUE)))

col_dummy_2003 <- "dummy_atendida_real_2003"
if (col_dummy_2003 %in% names(base_integrada)) {
  cat(sprintf("  Real 2003  - %.1f%% das AMCs atendidas\n\n",
              100 * mean(base_integrada[[col_dummy_2003]], na.rm = TRUE)))
}

# 8. EXPORTAÇÃO ---------------------------------------------------------------
cat("Etapa 7: Exportando base integrada...\n\n")

output_integrated <- paste0(data.wd, "/base_completa_integrada.csv")
write_csv(base_integrada, output_integrated)
cat(sprintf("  ✓ Base completa: %s\n", basename(output_integrated)))

# Exportar também em formato RDS para preservar tipos
output_rds <- paste0(data.wd, "/base_completa_integrada.rds")
saveRDS(base_integrada, output_rds)
cat(sprintf("  ✓ Base em formato R: %s\n\n", basename(output_rds)))

# 9. CRIAR DOCUMENTO DE REFERÊNCIA --------------------------------------------
cat("Etapa 8: Criando documento de referência (data dictionary)...\n\n")

# Criar data dictionary
data_dict <- tibble(
  Nome_Coluna = names(base_integrada),
  Tipo = sapply(base_integrada, class),
  Nao_Nulos = colSums(!is.na(base_integrada)),
  Media_ou_Valores = sapply(base_integrada, function(x) {
    if (is.numeric(x)) sprintf("%.2f", mean(x, na.rm = TRUE))
    else paste(n_distinct(x), "valores únicos")
  })
)

output_dict <- paste0(data.wd, "/base_completa_data_dictionary.csv")
write_csv(data_dict, output_dict)
cat(sprintf("  ✓ Dicionário de dados: %s\n\n", basename(output_dict)))

# 10. SUMÁRIO FINAL -----------------------------------------------------------
cat("========================================================================\n")
cat("✅ BASES INTEGRADAS COM SUCESSO!\n")
cat("========================================================================\n\n")

cat("SAÍDAS CRIADAS:\n")
cat(sprintf("  1. base_completa_integrada.csv\n"))
cat(sprintf("     └─ Base integrada (CSV)\n\n"))
cat(sprintf("  2. base_completa_integrada.rds\n"))
cat(sprintf("     └─ Base integrada (R object, tipos preservados)\n\n"))
cat(sprintf("  3. base_completa_data_dictionary.csv\n"))
cat(sprintf("     └─ Dicionário de variáveis\n\n"))

cat("ESTRUTURA DA BASE:\n")
cat(sprintf("  • %d AMCs × %d variáveis\n", nrow(base_integrada), ncol(base_integrada)))
cat(sprintf("  • Variáveis sintéticas: 3\n"))
cat(sprintf("  • Períodos reais: %d\n", length(anos_dist)))
cat(sprintf("  • Variáveis por período: 3 (distância, dummy, densidade)\n\n")

cat("COMO USAR:\n")
cat("  # Carregar a base em R:\n")
cat("  base <- read_csv('base_completa_integrada.csv')\n")
cat("  # ou\n")
cat("  base <- readRDS('base_completa_integrada.rds')\n\n")

cat("PRÓXIMAS ANÁLISES:\n")
cat("  1. Análise descritiva por período\n")
cat("  2. Análise causal usando IV (distância sintética como instrumento)\n")
cat("  3. Análise de densidade com controles geográficos\n")
cat("  4. Event study explorand impacto de inaugurações\n\n")
