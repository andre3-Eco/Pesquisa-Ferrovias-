# Script para extrair bases de tratamento de densidade (real e sintética por ano)
# Projeto: Pesquisa (Ferrovias) - Impacto de Ferrovias no Desenvolvimento Regional (Nordeste)

# Carregar pacotes necessários
library(tidyverse)
library(data.table)

# Definir diretórios
dir_processed <- "01-dados/processados/"
dir_output <- "01-dados/processados/"

# Função para extrair variáveis de densidade real
extrair_densidade_real <- function() {
  cat("Extraindo variáveis de densidade real...\n")
  
  # Carregar base completa integrada
  base_completa <- fread(file.path(dir_processed, "base_completa_integrada.csv"))
  
  # Identificar colunas de densidade real (padrão: densidade_real_YYYY)
  cols_densidade_real <- names(base_completa)[str_detect(names(base_completa), "^densidade_real_\\d{4}$")]
  
  if(length(cols_densidade_real) == 0) {
    # Tentar padrão alternativo
    cols_densidade_real <- names(base_completa)[str_detect(names(base_completa), "densidade_real")]
  }
  
  cat(sprintf("Encontradas %d colunas de densidade real\n", length(cols_densidade_real)))
  
  # Selecionar apenas código AMC, estado e colunas de densidade real
  densidade_real <- base_completa %>%
    select(code_amc, state_abbr, all_of(cols_densidade_real))
  
  # Salvar arquivo
  output_file <- file.path(dir_output, "densidade_real_tratamento.csv")
  fwrite(densidade_real, output_file)
  cat(sprintf("Base de densidade real salva em: %s\n", output_file))
  
  return(densidade_real)
}

# Função para extrair variáveis de densidade sintética por ano
extrair_densidade_sintetica <- function() {
  cat("Extraindo variáveis de densidade sintética por ano...\n")
  
  # Carregar base sintética cronológica
  base_sintetica <- fread(file.path(dir_processed, "base_sintetica_cronologica.csv"))
  
  # Identificar colunas de densidade sintética por ano (padrão: densidade_sintetica_YYYY)
  cols_densidade_sintetica <- names(base_sintetica)[str_detect(names(base_sintetica), "^densidade_sintetica_\\d{4}$")]
  
  if(length(cols_densidade_sintetica) == 0) {
    # Tentar padrão alternativo
    cols_densidade_sintetica <- names(base_sintetica)[str_detect(names(base_sintetica), "densidade_sintetica_\\d{4}")]
  }
  
  cat(sprintf("Encontradas %d colunas de densidade sintética por ano\n", length(cols_densidade_sintetica)))
  
  # Selecionar apenas código AMC e colunas de densidade sintética
  densidade_sintetica <- base_sintetica %>%
    select(code_amc, all_of(cols_densidade_sintetica))
  
  # Salvar arquivo
  output_file <- file.path(dir_output, "densidade_sintetica_tratamento_por_ano.csv")
  fwrite(densidade_sintetica, output_file)
  cat(sprintf("Base de densidade sintética por ano salva em: %s\n", output_file))
  
  return(densidade_sintetica)
}

# Função para criar documento de metadados
criar_metadados <- function(densidade_real, densidade_sintetica) {
  cat("Criando documento de metadados...\n")
  
  # Informações sobre densidade real
  cols_real <- names(densidade_real)[!names(densidade_real) %in% c("code_amc", "state_abbr")]
  anos_real <- str_extract(cols_real, "\\d{4}") %>% sort()
  
  # Informações sobre densidade sintética
  cols_sintetica <- names(densidade_sintetica)[!names(densidade_sintetica) %in% c("code_amc")]
  anos_sintetica <- str_extract(cols_sintetica, "\\d{4}") %>% sort()
  
  # Criar arquivo de metadados
  metadados <- paste0(
    "# Metadados das Bases de Tratamento de Densidade\n\n",
    "## Densidade Real\n",
    "- Arquivo: densidade_real_tratamento.csv\n",
    "- Observações: ", nrow(densidade_real), "\n",
    "- Variáveis: ", length(cols_real), " (densidade_real_YYYY)\n",
    "- Período: ", min(anos_real), " a ", max(anos_real), "\n\n",
    "## Densidade Sintética por Ano\n",
    "- Arquivo: densidade_sintetica_tratamento_por_ano.csv\n",
    "- Observações: ", nrow(densidade_sintetica), "\n",
    "- Variáveis: ", length(cols_sintetica), " (densidade_sintetica_YYYY)\n",
    "- Período: ", min(anos_sintetica), " a ", max(anos_sintetica), "\n\n",
    "## Uso Recomendado\n",
    "Essas bases contêm as variáveis de tratamento de densidade para uso em análises IV/2SLS:\n",
    "- densidade_real_tratamento.csv: Para análise com variável endógena densidade real\n",
    "- densidade_sintetica_tratamento_por_ano.csv: Para análise com instrumento sintético por ano\n"
  )
  
  metadados_file <- file.path(dir_output, "METADADOS_DENSIDADE_TRATAMENTO.md")
  writeLines(metadados, metadados_file)
  cat(sprintf("Metadados salvos em: %s\n", metadados_file))
}

# Executar funções principais
cat("=== EXTRAÇÃO DE BASES DE TRATAMENTO DE DENSIDADE ===\n\n")

# Extrair densidade real
densidade_real <- extrair_densidade_real()
cat("\n")

# Extrair densidade sintética por ano
densidade_sintetica <- extrair_densidade_sintetica()
cat("\n")

# Criar metadados
criar_metadados(densidade_real, densidade_sintetica)

cat("\n=== PROCESSO CONCLUÍDO ===\n")
cat("Bases de tratamento de densidade criadas com sucesso!\n")