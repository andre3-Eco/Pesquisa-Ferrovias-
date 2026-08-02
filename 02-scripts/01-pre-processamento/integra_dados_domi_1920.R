library(tidyverse)
library(readxl)
library(stringi)

if (!exists("data.wd")) {
  data.wd <- "C:/Users/André Elias/Documents/Pesquisa (Ferrovias)"
}
setwd(data.wd)

cat("1. Lendo arquivo CSV atual completo de 1920...\n")
base_csv <- read_csv("01-dados/dados_1920_final_completo.csv", show_col_types = FALSE)

cat("2. Lendo aba 'domi' do Excel...\n")
domi <- read_excel("01-dados/Dados1920.xlsx", sheet = "domi")

# Criar a chave de join para o domi
domi <- domi |>
  mutate(
    municipio_clean = tolower(stri_trans_general(municipio, "Latin-ASCII")),
    municipio_clean = str_replace_all(municipio_clean, "[^a-z ]", ""),
    municipio_clean = str_trim(str_squish(municipio_clean)),
    chave_join = paste0(municipio_clean, "_", estado)
  )

# Verificar duplicações
if(any(duplicated(domi$chave_join))) {
  cat("⚠ Aviso: Há municípios duplicados na aba 'domi'. Agregando...\n")
  domi <- domi |>
    group_by(chave_join) |>
    summarise(
      fabeofi = sum(fabeofi, na.rm = TRUE),
      casaneg = sum(casaneg, na.rm = TRUE),
      popu = sum(popu, na.rm = TRUE)
    )
} else {
  domi <- domi |> select(chave_join, fabeofi, casaneg, popu)
}

# A base csv já tem chave_join.
cat("3. Juntando as bases...\n")
base_final <- base_csv |>
  # Remover colunas se já existirem (para caso o script rode duas vezes)
  select(-any_of(c("fabeofi", "casaneg", "popu"))) |>
  left_join(domi, by = "chave_join")

cat(sprintf("Base resultante: %d linhas e %d colunas.\n", nrow(base_final), ncol(base_final)))
cat(sprintf("Valores não cruzados (NAs em popu): %d\n", sum(is.na(base_final$popu))))

cat("4. Salvando base unificada...\n")
write_csv(base_final, "01-dados/dados_1920_final_completo.csv")
cat("Concluído!\n")
