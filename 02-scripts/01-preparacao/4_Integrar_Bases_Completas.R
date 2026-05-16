# ==============================================================================
# INTEGRAÇÃO DE BASES COMPLETAS
# ==============================================================================
# Script que combina as três bases (distância, dummy, densidade) em uma
# única base analítica pronta para uso em análises IV
# ==============================================================================

cat("\n", strrep("=", 80), "\n")
cat("INTEGRAÇÃO DE BASES COMPLETAS\n")
cat("Data:", format(Sys.time(), "%d/%m/%Y %H:%M:%S"), "\n")
cat(strrep("=", 80), "\n\n")

# Definir diretório de trabalho se não estiver definido
if (!exists("data.wd")) data.wd <- getwd()

library(tidyverse)

# ==============================================================================
# SEÇÃO 1: CARREGAMENTO DAS TRÊS BASES
# ==============================================================================

cat("ETAPA 1: Carregando as três bases componentes...\n\n")

# Base de distâncias
cat("  • Carregando base de distâncias...")
base_distancias <- read_csv(
  paste0(data.wd, "/01-dados/processados/base_distancias_amcs_nordeste_semmar.csv"),
  show_col_types = FALSE
)
cat(sprintf(" OK (%d linhas, %d colunas)\n", nrow(base_distancias), ncol(base_distancias)))

# Base de dummy
cat("  • Carregando base de dummy...")
base_dummy <- read_csv(
  paste0(data.wd, "/01-dados/processados/base_dummy_atendimento_ferrovias.csv"),
  show_col_types = FALSE
)
cat(sprintf(" OK (%d linhas, %d colunas)\n", nrow(base_dummy), ncol(base_dummy)))

# Base de densidade
cat("  • Carregando base de densidade...")
base_densidade <- read_csv(
  paste0(data.wd, "/01-dados/processados/base_densidade_ferrovias.csv"),
  show_col_types = FALSE
)
cat(sprintf(" OK (%d linhas, %d colunas)\n", nrow(base_densidade), ncol(base_densidade)))

cat("\n")

# ==============================================================================
# SEÇÃO 2: VALIDAÇÕES BÁSICAS
# ==============================================================================

cat("ETAPA 2: Realizando validações...\n\n")

# Verificar se todas têm o mesmo número de linhas
n_dist <- nrow(base_distancias)
n_dummy <- nrow(base_dummy)
n_dens <- nrow(base_densidade)

if (n_dist == n_dummy & n_dummy == n_dens) {
  cat(sprintf("  ✓ Todas as bases têm %d linhas\n", n_dist))
} else {
  stop(sprintf("❌ Erro: Bases têm números diferentes de linhas!\n  Distância: %d, Dummy: %d, Densidade: %d",
               n_dist, n_dummy, n_dens))
}

# Verificar se code_amc está igual em todas
if (all(base_distancias$code_amc == base_dummy$code_amc) &
    all(base_dummy$code_amc == base_densidade$code_amc)) {
  cat("  ✓ code_amc alinhado entre as três bases\n")
} else {
  stop("❌ Erro: code_amc não está alinhado entre as bases!")
}

# Verificar se há valores ausentes
na_dist <- sum(is.na(base_distancias))
na_dummy <- sum(is.na(base_dummy))
na_dens <- sum(is.na(base_densidade))

if (na_dist == 0 & na_dummy == 0 & na_dens == 0) {
  cat("  ✓ Nenhum valor ausente (NA) nas três bases\n")
} else {
  cat(sprintf("  ⚠️  Atenção: %d NA em distância, %d em dummy, %d em densidade\n",
              na_dist, na_dummy, na_dens))
}

cat("\n")

# ==============================================================================
# SEÇÃO 3: INTEGRAÇÃO (MERGE)
# ==============================================================================

cat("ETAPA 3: Integrando as bases...\n\n")

# Merge: distância + dummy
cat("  • Merge de distância com dummy...")
base_temp <- base_distancias |>
  left_join(base_dummy, by = "code_amc")
cat(sprintf(" OK\n"))

# Merge: resultado + densidade
cat("  • Merge com densidade...")
base_completa_integrada <- base_temp |>
  left_join(base_densidade, by = "code_amc")
cat(sprintf(" OK\n"))

cat(sprintf("\n  Base final: %d linhas × %d colunas\n\n", 
            nrow(base_completa_integrada), ncol(base_completa_integrada)))

# ==============================================================================
# SEÇÃO 4: LIMPEZA E REORDENAÇÃO DE COLUNAS
# ==============================================================================

cat("ETAPA 4: Limpeza e reordenação de colunas...\n\n")

# Remover duplicatas de colunas (se houver)
colunas_duplicadas <- colnames(base_completa_integrada)[duplicated(colnames(base_completa_integrada))]
if (length(colunas_duplicadas) > 0) {
  cat(sprintf("  ⚠️  Removendo %d colunas duplicadas\n", length(colunas_duplicadas)))
  base_completa_integrada <- base_completa_integrada[, !duplicated(colnames(base_completa_integrada))]
}

# Reordenar colunas: primeiro code_amc e área, depois em grupos temáticos
ordem_preferida <- c(
  "code_amc",
  "area_km2",
  # Sintéticas
  grep("^dist_rail_sintetica|^dummy_atendida_sintetica|^cobertura|^comprimento_sintetico|^densidade_sintetica",
       colnames(base_completa_integrada), value = TRUE),
  # Reais (cronológicas)
  grep("^dist_rail_real|^dummy_atendida_real|^comprimento_real|^densidade_real",
       colnames(base_completa_integrada), value = TRUE)
)

# Certificar que todas as colunas estão na ordem preferida
colunas_extras <- setdiff(colnames(base_completa_integrada), ordem_preferida)
ordem_final <- c(ordem_preferida[ordem_preferida %in% colnames(base_completa_integrada)], 
                 colunas_extras)

base_completa_integrada <- base_completa_integrada |>
  select(all_of(ordem_final))

cat(sprintf("  ✓ Colunas reordenadas: %d total\n", ncol(base_completa_integrada)))

cat("\n")

# ==============================================================================
# SEÇÃO 5: VALIDAÇÕES FINAIS
# ==============================================================================

cat("ETAPA 5: Realizando validações finais...\n\n")

# Verificar se há NA na base final
na_final <- sum(is.na(base_completa_integrada))
if (na_final == 0) {
  cat("  ✓ Base final sem valores ausentes (NA)\n")
} else {
  cat(sprintf("  ⚠️  Atenção: %d valores NA na base final\n", na_final))
}

# Verificar estatísticas básicas
cat("\n  ESTATÍSTICAS BÁSICAS:\n\n")

# Distância sintética
dist_sint <- base_completa_integrada$dist_rail_sintetica_km
cat(sprintf("  Distância Sintética (km):\n"))
cat(sprintf("    Media: %.2f, Mediana: %.2f, Min: %.2f, Max: %.2f\n",
            mean(dist_sint, na.rm = TRUE),
            median(dist_sint, na.rm = TRUE),
            min(dist_sint, na.rm = TRUE),
            max(dist_sint, na.rm = TRUE)))

# Distância real 2003
dist_real_2003 <- base_completa_integrada$dist_rail_real_2003
cat(sprintf("  Distância Real 2003 (km):\n"))
cat(sprintf("    Media: %.2f, Mediana: %.2f, Min: %.2f, Max: %.2f\n",
            mean(dist_real_2003, na.rm = TRUE),
            median(dist_real_2003, na.rm = TRUE),
            min(dist_real_2003, na.rm = TRUE),
            max(dist_real_2003, na.rm = TRUE)))

# Dummy sintética
dummy_sint <- base_completa_integrada$dummy_atendida_sintetica
pct_atend_sint <- sum(dummy_sint == 1) / length(dummy_sint) * 100
cat(sprintf("  Dummy Sintética:\n"))
cat(sprintf("    Atendidas: %.1f%% (%d de %d)\n",
            pct_atend_sint, sum(dummy_sint == 1), length(dummy_sint)))

# Dummy real 2003
dummy_real_2003 <- base_completa_integrada$dummy_atendida_real_2003
pct_atend_real <- sum(dummy_real_2003 == 1) / length(dummy_real_2003) * 100
cat(sprintf("  Dummy Real 2003:\n"))
cat(sprintf("    Atendidas: %.1f%% (%d de %d)\n",
            pct_atend_real, sum(dummy_real_2003 == 1), length(dummy_real_2003)))

# Densidade sintética
dens_sint <- base_completa_integrada$densidade_sintetica
cat(sprintf("  Densidade Sintética (km/1000km²):\n"))
cat(sprintf("    Media: %.2f, Mediana: %.2f, Min: %.2f, Max: %.2f\n",
            mean(dens_sint, na.rm = TRUE),
            median(dens_sint, na.rm = TRUE),
            min(dens_sint, na.rm = TRUE),
            max(dens_sint, na.rm = TRUE)))

# Densidade real 2003
dens_real_2003 <- base_completa_integrada$densidade_real_2003
cat(sprintf("  Densidade Real 2003 (km/1000km²):\n"))
cat(sprintf("    Media: %.2f, Mediana: %.2f, Min: %.2f, Max: %.2f\n",
            mean(dens_real_2003, na.rm = TRUE),
            median(dens_real_2003, na.rm = TRUE),
            min(dens_real_2003, na.rm = TRUE),
            max(dens_real_2003, na.rm = TRUE)))

cat("\n")

# ==============================================================================
# SEÇÃO 6: EXPORTAÇÃO
# ==============================================================================

cat("ETAPA 6: Exportando base integrada...\n\n")

# Salvar em CSV
arquivo_csv <- paste0(data.wd, "/01-dados/processados/base_completa_integrada.csv")
write_csv(base_completa_integrada, arquivo_csv)
cat(sprintf("  ✓ CSV salvo: %s\n", arquivo_csv))

# Salvar em RDS (mais eficiente para R)
arquivo_rds <- paste0(data.wd, "/01-dados/processados/base_completa_integrada.rds")
saveRDS(base_completa_integrada, arquivo_rds)
cat(sprintf("  ✓ RDS salvo: %s\n", arquivo_rds))


