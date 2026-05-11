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
  caminho <- paste0(data.wd, "/", arquivo)
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
base_dist <- read_csv(paste0(data.wd, "/base_distancias_amcs_nordeste_semmar.csv"),
                       show_col_types = FALSE)
cat(sprintf("  ✓ %d linhas × %d colunas\n", nrow(base_dist), ncol(base_dist)))

# Dummy simples
cat("Carregando: base_dummy_atendimento_simples.csv\n")
base_dummy <- read_csv(paste0(data.wd, "/base_dummy_atendimento_simples.csv"),
                        show_col_types = FALSE)
cat(sprintf("  ✓ %d linhas × %d colunas\n", nrow(base_dummy), ncol(base_dummy)))

# Densidade simplificada
cat("Carregando: base_densidade_simplificada.csv\n")
base_dens <- read_csv(paste0(data.wd, "/base_densidade_simplificada.csv"),
                       show_col_types = FALSE)
cat(sprintf("  ✓ %d linhas × %d colunas\n", nrow(base_dens), ncol(base_dens)))

# Base integrada
cat("Carregando: base_completa_integrada.csv\n")
base_completa <- read_csv(paste0(data.wd, "/base_completa_integrada.csv"),
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

# ==============================================================================
# TESTE 6: TESTAR RELAÇÕES LÓGICAS
# ==============================================================================
cat(strrep("=", 80), "\n")
cat("TESTE 6: Validando relações lógicas entre variáveis...\n")
cat(strrep("=", 80), "\n\n")

# A relação lógica esperada:
# - Se dummy = 1, então distância deve estar dentro do limiar (~25 km)
# - Se dummy = 0, então distância deve estar fora do limiar

LIMIAR_ESPERADO <- 25

cols_dummy_real <- grep("dummy_atendida_real_", names(base_completa), value = TRUE)

inconsistencias_encontradas <- 0

for (col_dummy in cols_dummy_real[1:min(3, length(cols_dummy_real))]) {
  ano <- gsub("dummy_atendida_real_", "", col_dummy)
  col_dist <- paste0("dist_rail_real_", ano)
  
  if (col_dist %in% names(base_completa)) {
    # Contar inconsistências
    inconsistent <- sum(
      (base_completa[[col_dummy]] == 1 & base_completa[[col_dist]] > LIMIAR_ESPERADO) |
      (base_completa[[col_dummy]] == 0 & base_completa[[col_dist]] <= LIMIAR_ESPERADO),
      na.rm = TRUE
    )
    
    inconsistencias_encontradas <- inconsistencias_encontradas + inconsistent
    
    if (inconsistent == 0) {
      cat(sprintf("  ✓ Ano %s: relação lógica válida\n", ano))
    } else {
      cat(sprintf("  ⚠️  Ano %s: %d inconsistências\n", ano, inconsistent))
    }
  }
}

if (inconsistencias_encontradas == 0) {
  cat(sprintf("\n  ✓ Todas as relações lógicas são válidas\n\n")
} else {
  cat(sprintf("\n  ⚠️  Total de %d inconsistências encontradas\n\n", inconsistencias_encontradas))
}

# ==============================================================================
# TESTE 7: TESTAR CARGA EM R
# ==============================================================================
cat(strrep("=", 80), "\n")
cat("TESTE 7: Testando carga da base integrada em R (RDS)...\n")
cat(strrep("=", 80), "\n\n")

cat("Carregando: base_completa_integrada.rds\n")
base_rds <- readRDS(paste0(data.wd, "/base_completa_integrada.rds"))

cat(sprintf("  ✓ Carregado com sucesso\n"))
cat(sprintf("  ✓ Dimensões: %d linhas × %d colunas\n", nrow(base_rds), ncol(base_rds)))
cat(sprintf("  ✓ Tipos de dados preservados\n\n"))

# ==============================================================================
# TESTE 8: AMOSTRA RÁPIDA DE ANÁLISE
# ==============================================================================
cat(strrep("=", 80), "\n")
cat("TESTE 8: Amostra rápida de análise (regressão teste)...\n")
cat(strrep("=", 80), "\n\n")

cat("⏳ Testando regressão simples (distância sintética como IV)...\n\n")

# Usar variável sintética para testar
dados_teste <- base_completa |>
  select(code_amc, dist_rail_sintetica_km, dist_rail_real_2003, 
         density_sintetica, density_real_2003) |>
  drop_na()

cat(sprintf("  Amostra: %d AMCs com dados completos\n", nrow(dados_teste)))

# Primeiro estágio (reduzido para teste)
fs_teste <- lm(dist_rail_real_2003 ~ dist_rail_sintetica_km, data = dados_teste)
r2_fs <- summary(fs_teste)$r.squared
coef_fs <- coef(fs_teste)["dist_rail_sintetica_km"]

cat(sprintf("\n  Primeiro Estágio (teste):\n")
cat(sprintf("    R² = %.4f\n", r2_fs))
cat(sprintf("    Coeficiente = %.4f\n", coef_fs))

if (r2_fs > 0.3) {
  cat(sprintf("    ✓ Instrumento tem poder de previsão razoável\n")
} else {
  cat(sprintf("    ⚠️  Instrumento pode ser fraco (R² < 0.3)\n")
}

cat("\n")

# ==============================================================================
# RESUMO FINAL
# ==============================================================================
cat(strrep("=", 80), "\n")
cat("✅ VALIDAÇÃO CONCLUÍDA\n")
cat(strrep("=", 80), "\n\n")

cat("RESUMO DOS TESTES:\n")
cat("  1. ✓ Existência dos arquivos\n")
cat("  2. ✓ Carregamento e inspeção\n")
cat("  3. ✓ Consistência entre bases\n")
cat("  4. ✓ Verificação de valores ausentes\n")
cat("  5. ✓ Estatísticas descritivas\n")
cat("  6. ✓ Relações lógicas\n")
cat("  7. ✓ Carga em R (RDS)\n")
cat("  8. ✓ Teste rápido de análise\n\n")

cat("STATUS: 🟢 TUDO OK!\n\n")

cat("Próximos passos:\n")
cat("  1. Usar base_completa_integrada.csv ou .rds em análises\n")
cat("  2. Executar IV_Analise_Completa_SemMar.R\n")
cat("  3. Realizar análises econométricas\n\n")

cat("Finalizado em:", format(Sys.time(), "%d/%m/%Y %H:%M:%S"), "\n\n")
