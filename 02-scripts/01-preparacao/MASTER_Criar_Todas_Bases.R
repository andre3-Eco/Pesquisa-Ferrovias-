# ==============================================================================
# SCRIPT MASTER: CRIAR TODAS AS BASES ANALÍTICAS
# ==============================================================================
# Este script orquestra a criação sequencial de todas as bases de dados:
#   1. Base de Distâncias
#   2. Base de Dummy de Atendimento
#   3. Base de Densidade de Ferrovias
#   4. Base Integrada Completa
# ==============================================================================
#   3. Base de Densidade de Ferrovias
#   4. Base Integrada Comple
# ==============================================================================

cat("\n\n")
cat(strrep("=", 80), "\n")
cat("CRIAÇÃO COMPLETA DE BASES ANALÍTICAS - SCRIPT MASTER\n")
cat("Data:", format(Sys.time(), "%d/%m/%Y %H:%M:%S"), "\n")
cat(strrep("=", 80), "\n\n")

# Configurar variáveis globais
if (!exists("data.wd")) data.wd <- getwd()

cat(sprintf("Diretório de trabalho: %s\n\n", data.wd))

# ==============================================================================
# ETAPA 1: BASE DE DISTÂNCIAS
# ==============================================================================
cat(strrep("-", 80), "\n")
cat("ETAPA 1/4: CRIANDO BASE DE DISTÂNCIAS\n")
cat(strrep("-", 80), "\n\n")

tempo_inicio_1 <- Sys.time()

tryCatch({
  source(paste0(data.wd, "/02-scripts/01-preparacao/1_Criar_Base_Distancias.R"), echo = FALSE)
  
  tempo_fim_1 <- Sys.time()
  tempo_1 <- difftime(tempo_fim_1, tempo_inicio_1, units = "secs")
  
  cat(sprintf("\n✅ ETAPA 1 CONCLUÍDA EM %.1f segundos\n\n", tempo_1))
  
}, error = function(e) {
  cat(sprintf("\n❌ ERRO NA ETAPA 1:\n%s\n\n", e$message))
  stop("Parado na etapa 1")
})

# ==============================================================================
# ETAPA 2: BASE DE DUMMY
# ==============================================================================
cat(strrep("-", 80), "\n")
cat("ETAPA 2/4: CRIANDO BASE DE DUMMY DE ATENDIMENTO\n")
cat(strrep("-", 80), "\n\n")

tempo_inicio_2 <- Sys.time()

tryCatch({
  source(paste0(data.wd, "/02-scripts/01-preparacao/2_Criar_Base_Dummy_Atendimento.R"), echo = FALSE)
  
  tempo_fim_2 <- Sys.time()
  tempo_2 <- difftime(tempo_fim_2, tempo_inicio_2, units = "secs")
  
  cat(sprintf("\n✅ ETAPA 2 CONCLUÍDA EM %.1f segundos\n\n", tempo_2))
  
}, error = function(e) {
  cat(sprintf("\n❌ ERRO NA ETAPA 2:\n%s\n\n", e$message))
  stop("Parado na etapa 2")
})

# ==============================================================================
# ETAPA 3: BASE DE DENSIDADE
# ==============================================================================
cat(strrep("-", 80), "\n")
cat("ETAPA 3/4: CRIANDO BASE DE DENSIDADE DE FERROVIAS\n")
cat(strrep("-", 80), "\n\n")

tempo_inicio_3 <- Sys.time()

tryCatch({
  source(paste0(data.wd, "/02-scripts/01-preparacao/3_Criar_Base_Densidade_Ferrovias.R"), echo = FALSE)
  
  tempo_fim_3 <- Sys.time()
  tempo_3 <- difftime(tempo_fim_3, tempo_inicio_3, units = "secs")
  
  cat(sprintf("\n✅ ETAPA 3 CONCLUÍDA EM %.1f segundos\n\n", tempo_3))
  
}, error = function(e) {
  cat(sprintf("\n❌ ERRO NA ETAPA 3:\n%s\n\n", e$message))
  stop("Parado na etapa 3")
})

# ==============================================================================
# ETAPA 4: INTEGRAÇÃO
# ==============================================================================
cat(strrep("-", 80), "\n")
cat("ETAPA 4/4: INTEGRANDO TODAS AS BASES\n")
cat(strrep("-", 80), "\n\n")

tempo_inicio_4 <- Sys.time()

tryCatch({
  source(paste0(data.wd, "/02-scripts/01-preparacao/4_Integrar_Bases_Completas.R"), echo = FALSE)
  
  tempo_fim_4 <- Sys.time()
  tempo_4 <- difftime(tempo_fim_4, tempo_inicio_4, units = "secs")
  
  cat(sprintf("\n✅ ETAPA 4 CONCLUÍDA EM %.1f segundos\n\n", tempo_4))
  
}, error = function(e) {
  cat(sprintf("\n❌ ERRO NA ETAPA 4:\n%s\n\n", e$message))
  stop("Parado na etapa 4")
})


