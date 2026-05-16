# ==============================================================================
# SCRIPT DE VALIDAÇÃO: TESTAR AS BASES CRIADAS
# ==============================================================================
# Use este script para verificar se as bases foram criadas corretamente
# e fazer testes rápidos antes de usar em análises principais
# ==============================================================================

cat("\n")
cat(strrep("=", 80), "\n")
cat("VALIDAÇÃO DE BASES CRIADAS\n")
cat("Data:", format(Sys.time(), "%d/%m/%Y %H:%M:%S"), "\n")
cat(strrep("=", 80), "\n\n")

library(tidyverse)

if (!exists("data.wd")) data.wd <- getwd()

# ==============================================================================
# TESTE 1: VERIFICAR EXISTÊNCIA DOS ARQUIVOS
# ==============================================================================
cat("TESTE 1: Verificando existência dos arquivos...\n\n")

arquivos_esperados <- c(
  "base_distancias_amcs_nordeste_semmar.csv",
  "base_dummy_atendimento_ferrovias.csv",
  "base_dummy_atendimento_simples.csv",
  "base_densidade_ferrovias.csv",
  "base_densidade_simplificada.csv",
  "base_completa_integrada.csv",
  "base_completa_integrada.rds",
  "base_completa_data_dictionary.csv"
)

arquivos_encontrados <- 0

for (arquivo in arquivos_esperados) {
  caminho <- paste0(data.wd, "/01-dados/processados/", arquivo)
  if (file.exists(caminho)) {
    tamanho <- file.size(caminho)
    tamanho_mb <- tamanho / (1024^2)
    cat(sprintf("  ✓ %s (%.1f MB)\n", arquivo, tamanho_mb))
    arquivos_encontrados <- arquivos_encontrados + 1
  } else {
    cat(sprintf("  ✗ %s [NÃO ENCONTRADO]\n", arquivo))
  }
}

cat(sprintf("\nResultado: %d/%d arquivos encontrados\n\n", 
            arquivos_encontrados, length(arquivos_esperados)))

if (arquivos_encontrados < length(arquivos_esperados)) {
  cat("⚠️  Nem todos os arquivos foram encontrados!\n")
  cat("Certifique-se de ter executado: source('0_MASTER_Criar_Todas_Bases.R')\n\n")
  stop("Arquivos faltando!")
}

# ==============================================================================
# TESTE 2: CARREGAR E INSPECIONAR BASES
# ==============================================================================
cat(strrep("=", 80), "\n")
cat("TESTE 2: Carregando e inspecionando as bases...\n")
cat(strrep("=", 80), "\n\n")

# Distâncias
cat("Carregando: base_distancias_amcs_nordeste_semmar.csv\n")
base_dist <- read_csv(paste0(data.wd, "/01-dados/processados/base_distancias_amcs_nordeste_semmar.csv"),
                       show_col_types = FALSE)
cat(sprintf("  ✓ %d linhas × %d colunas\n", nrow(base_dist), ncol(base_dist)))

# Dummy simples
cat("Carregando: base_dummy_atendimento_simples.csv\n")
base_dummy <- read_csv(paste0(data.wd, "/01-dados/processados/base_dummy_atendimento_simples.csv"),
                        show_col_types = FALSE)
cat(sprintf("  ✓ %d linhas × %d colunas\n", nrow(base_dummy), ncol(base_dummy)))

# Densidade simplificada
cat("Carregando: base_densidade_simplificada.csv\n")
base_dens <- read_csv(paste0(data.wd, "/01-dados/processados/base_densidade_simplificada.csv"),
                       show_col_types = FALSE)
cat(sprintf("  ✓ %d linhas × %d colunas\n", nrow(base_dens), ncol(base_dens)))

# Base integrada
cat("Carregando: base_completa_integrada.csv\n")
base_completa <- read_csv(paste0(data.wd, "/01-dados/processados/base_completa_integrada.csv"),
                           show_col_types = FALSE)
cat(sprintf("  ✓ %d linhas × %d colunas\n\n", nrow(base_completa), ncol(base_completa)))

# ==============================================================================
# TESTE 3: VALIDAR CONSISTÊNCIA ENTRE BASES
# ==============================================================================
cat(strrep("=", 80), "\n")
cat("TESTE 3: Validando consistência entre bases...\n")
cat(strrep("=", 80), "\n\n")

# Verificar se code_amc é consistente
amc_dist <- sort(unique(base_dist$code_amc))
amc_dummy <- sort(unique(base_dummy$code_amc))
amc_dens <- sort(unique(base_dens$code_amc))
amc_completa <- sort(unique(base_completa$code_amc))

cat("AMCs únicas em cada base:\n")
cat(sprintf("  • Distâncias: %d\n", length(amc_dist)))
cat(sprintf("  • Dummy: %d\n", length(amc_dummy)))
cat(sprintf("  • Densidade: %d\n", length(amc_dens)))
cat(sprintf("  • Completa: %d\n\n", length(amc_completa)))

if (length(amc_completa) == length(amc_dist) &&
    identical(amc_completa, amc_dist)) {
  cat("  ✓ Code_amc consistente entre todas as bases\n\n")
} else {
  cat("  ⚠️  AVISO: code_amc não é consistente!\n\n")
}

# ==============================================================================
# TESTE 4: VERIFICAR VALORES AUSENTES
# ==============================================================================
cat(strrep("=", 80), "\n")
cat("TESTE 4: Verificando valores ausentes (NAs)...\n")
cat(strrep("=", 80), "\n\n")

verificar_nas <- function(df, nome) {
  nas <- colSums(is.na(df))
  nas_nao_zero <- nas[nas > 0]
  
  if (length(nas_nao_zero) == 0) {
    cat(sprintf("  ✓ %s: sem valores ausentes\n", nome))
    return(TRUE)
  } else {
    cat(sprintf("  ⚠️  %s: %d colunas com NAs\n", nome, length(nas_nao_zero)))
    print(nas_nao_zero[1:5])  # Mostrar primeiro 5
    return(FALSE)
  }
}

verificar_nas(base_dist, "Distâncias")
verificar_nas(base_dummy, "Dummy")
verificar_nas(base_dens, "Densidade")
verificar_nas(base_completa, "Completa")

cat("\n")

# ==============================================================================
# TESTE 5: ESTATÍSTICAS DESCRITIVAS
# ==============================================================================
cat(strrep("=", 80), "\n")
cat("TESTE 5: Estatísticas descritivas das variáveis principais...\n")
cat(strrep("=", 80), "\n\n")

# Distâncias
cat("Distâncias (km):\n")
cat(sprintf("  Sintética:\n"))
cat(sprintf("    Média: %.1f | Mediana: %.1f | Min: %.1f | Max: %.1f\n",
            mean(base_dist$dist_rail_sintetica_km, na.rm = TRUE),
            median(base_dist$dist_rail_sintetica_km, na.rm = TRUE),
            min(base_dist$dist_rail_sintetica_km, na.rm = TRUE),
            max(base_dist$dist_rail_sintetica_km, na.rm = TRUE)))

# Pegar última coluna de real (mais recente)
cols_real <- grep("dist_rail_real_", names(base_dist), value = TRUE)
if (length(cols_real) > 0) {
  ultimo_ano <- cols_real[length(cols_real)]
  ano <- gsub("dist_rail_real_", "", ultimo_ano)
  cat(sprintf("  Real %s:\n", ano))
  cat(sprintf("    Média: %.1f | Mediana: %.1f | Min: %.1f | Max: %.1f\n\n",
              mean(base_dist[[ultimo_ano]], na.rm = TRUE),
              median(base_dist[[ultimo_ano]], na.rm = TRUE),
              min(base_dist[[ultimo_ano]], na.rm = TRUE),
              max(base_dist[[ultimo_ano]], na.rm = TRUE)))
}

# Dummy
cat("Atendimento (proporção com dummy = 1):\n")
cat(sprintf("  Sintética: %.1f%%\n",
            100 * mean(base_dummy$dummy_atendida_sintetica, na.rm = TRUE)))

cols_dummy_real <- grep("dummy_atendida_real_", names(base_dummy), value = TRUE)
if (length(cols_dummy_real) > 0) {
  ultimo_dummy <- cols_dummy_real[length(cols_dummy_real)]
  ano <- gsub("dummy_atendida_real_", "", ultimo_dummy)
  cat(sprintf("  Real %s: %.1f%%\n\n",
              ano, 100 * mean(base_dummy[[ultimo_dummy]], na.rm = TRUE)))
}

# Densidade
cat("Densidade (km por 1000 km²):\n")
cat(sprintf("  Sintética:\n"))
cat(sprintf("    Média: %.2f | Mediana: %.2f | Max: %.2f\n",
            mean(base_dens$densidade_sintetica, na.rm = TRUE),
            median(base_dens$densidade_sintetica, na.rm = TRUE),
            max(base_dens$densidade_sintetica, na.rm = TRUE)))

cols_dens_real <- grep("densidade_real_", names(base_dens), value = TRUE)
if (length(cols_dens_real) > 0) {
  ultimo_dens <- cols_dens_real[length(cols_dens_real)]
  ano <- gsub("densidade_real_", "", ultimo_dens)
  cat(sprintf("  Real %s:\n", ano))
  cat(sprintf("    Média: %.2f | Mediana: %.2f | Max: %.2f\n\n",
              mean(base_dens[[ultimo_dens]], na.rm = TRUE),
              median(base_dens[[ultimo_dens]], na.rm = TRUE),
              max(base_dens[[ultimo_dens]], na.rm = TRUE)))
}





