# Instalar os pacotes necessários caso não os tenha:
# install.packages(c("geobr", "dplyr", "stringi", "sf", "readxl", "readr", "tidyr"))

library(geobr)
library(dplyr)
library(stringi)
library(sf)
library(readxl)
library(readr)
library(tidyr)

cat("1. Baixando a malha municipal de 1920...\n")
muni_1920 <- read_municipality(year = 1920, showProgress = FALSE)

cat("2. Padronizando a base do IBGE...\n")
muni_1920_clean <- muni_1920 %>%
  st_drop_geometry() %>% # Trabalhar apenas com os dados tabulares
  mutate(
    nome_padronizado = stri_trans_general(name_muni, "Latin-ASCII"),
    nome_padronizado = tolower(nome_padronizado),
    nome_padronizado = trimws(nome_padronizado),
    chave_join = paste0(nome_padronizado, "_", abbrev_state)
  )

cat("3. Lendo os dados do Excel...\n")
caminho_excel <- "../01-dados/Dados1920.xlsx"
dados_instrucao <- read_excel(caminho_excel, sheet = "instrução")
dados_maquinas <- read_excel(caminho_excel, sheet = "Maquinas")

cat("4. Padronizando a base do Excel...\n")
dados_instrucao_clean <- dados_instrucao %>%
  mutate(
    nome_padronizado = stri_trans_general(municipio, "Latin-ASCII"),
    nome_padronizado = gsub("[[:punct:]]", "", nome_padronizado), # Remove pontuações
    nome_padronizado = tolower(nome_padronizado),
    nome_padronizado = trimws(nome_padronizado),
    chave_join = paste0(nome_padronizado, "_", estado)
  )

cat("5. Realizando o cruzamento exato...\n")
dados_unidos_exato <- dados_instrucao_clean %>%
  left_join(
    muni_1920_clean %>% select(code_muni, name_muni, chave_join), 
    by = "chave_join"
  )

com_match <- dados_unidos_exato %>% filter(!is.na(code_muni))
sem_match <- dados_unidos_exato %>% filter(is.na(code_muni)) %>% select(-code_muni, -name_muni)

cat("6. Realizando o cruzamento aproximado (Fuzzy Match)...\n")
if(nrow(sem_match) > 0) {
  sem_match$code_muni <- NA_integer_
  sem_match$name_muni <- NA_character_
  
  for (i in 1:nrow(sem_match)) {
    estado_atual <- sem_match$estado[i]
    nome_busca <- sem_match$nome_padronizado[i]
    
    opcoes_ibge <- muni_1920_clean %>% filter(abbrev_state == estado_atual)
    
    if (nrow(opcoes_ibge) > 0) {
      distancias <- adist(nome_busca, opcoes_ibge$nome_padronizado)[1, ]
      idx_min <- which.min(distancias)
      min_dist <- distancias[idx_min]
      
      # Aceitamos até 5 alterações (letras diferentes, sobrando ou faltando)
      if (min_dist <= 5) {
        sem_match$code_muni[i] <- opcoes_ibge$code_muni[idx_min]
        sem_match$name_muni[i] <- opcoes_ibge$name_muni[idx_min]
      }
    }
  }
}

fuzzy_sucesso <- sem_match %>% filter(!is.na(code_muni))
fuzzy_falha <- sem_match %>% filter(is.na(code_muni))

# Une resultados exatos com os que deram certo no fuzzy
dados_base_final <- bind_rows(com_match, fuzzy_sucesso)

cat("7. Juntando com a planilha de Maquinário...\n")
dados_finais <- dados_base_final %>%
  # Mantemos apenas as colunas que importam do arquivo de instrução
  select(code_muni, municipio, estado, `sabem(7a14)`, `nsabem(7a14)`, `sabem(15a)`, `nsabem(15a)`, chave_join) %>%
  # Junta com os dados de máquinas pelos nomes exatos do Excel
  left_join(dados_maquinas, by = c("municipio", "estado"))

cat("8. Tratando NAs nas colunas de maquinário...\n")
# Substitui os NAs que surgiram nas colunas de máquinas por zero
dados_finais <- dados_finais %>%
  mutate(
    numeroestabelecimento = replace_na(numeroestabelecimento, 0),
    commaquinas = suppressWarnings(as.numeric(commaquinas)), # Força para número caso tenha texto
    commaquinas = replace_na(commaquinas, 0),
    cominstruagra = replace_na(cominstruagra, 0)
  )

cat("9. Salvando o arquivo CSV final na pasta 01-dados...\n")
write_csv(dados_finais, "../01-dados/dados_1920_final_completo.csv")

cat("\n=== RESUMO ===\n")
cat("Total de municípios processados:", nrow(dados_instrucao), "\n")
cat("Total cruzados com sucesso (Exato + Fuzzy):", nrow(dados_finais), "\n")
cat("Total que não pôde ser cruzado:", nrow(fuzzy_falha), "\n")
if(nrow(fuzzy_falha) > 0) {
  cat("\nNão cruzados:\n")
  print(fuzzy_falha %>% select(municipio, estado))
}
cat("\nProcesso concluído com sucesso. Arquivo 'dados_1920_final_completo.csv' gerado.\n")
