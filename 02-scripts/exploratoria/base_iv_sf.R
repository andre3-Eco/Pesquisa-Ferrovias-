# ==============================================================================
# SCRIPT PARA CRIAR A BASE DE DADOS (dados) 
# Para o script IV_Analise_Completa_SemMar.R
# ==============================================================================
# Este script constrói a base analítica completa necessária para as análises IV.
# Após executar este script, a base estará pronta em `dados` (ou `base_iv_sf`).
# ==============================================================================

# 1. PACOTES -------------------------------------------------------------------
library(sf)
library(dplyr)
library(tidyverse)
library(geobr)
library(spdep)

if (!exists("data.wd")) data.wd <- getwd()

sf_use_s2(FALSE)

# 2. PRÉ-REQUISITO: DADOS DE POPULAÇÃO ----------------------------------------
# O script IV_Analise_Completa_SemMar.R requer o objeto `população`
# Este deve ser carregado ANTES de executar este script.
# Se você não tiver, descomente a seção abaixo para criar um exemplo:

# if (!exists("população")) {
#   cat("Aviso: Carregando dados de população (ajuste conforme necessário)...\n")
#   # Você pode:
#   # 1. Carregar de um CSV:
#   # população <- read_csv("caminho/para/população.csv")
#   #
#   # 2. Usar dados do IBGE (geobr + API externa)
#   # 3. Importar de outra fonte
#   #
#   # Para agora, criamos um placeholder:
#   stop("Favor carregar o objeto 'população' antes de executar este script.")
# }

# 3. CARREGAMENTO DOS DADOS GEOESPACIAIS E DISTÂNCIAS -------------------------
cat("========================================================================\n")
cat("CARREGANDO DADOS GEOESPACIAIS E DE DISTÂNCIAS\n")
cat("========================================================================\n\n")

## 3a. Base de distâncias (rede sintética sem mar + redes reais cronológicas)
cat("Lendo base de distâncias...\n")
base_distancias <- read_csv(
  paste0(data.wd, "/base_distancias_amcs_nordeste_semmar.csv"),
  show_col_types = FALSE
)

cat(sprintf("  ✓ Base de distâncias carregada: %d linhas\n\n", nrow(base_distancias)))

## 3b. Ferrovias reais (para extrair pontas)
cat("Lendo ferrovias reais...\n")
ferrovias_reais <- st_read(
  paste0(data.wd, "/Dados pesquisa (Ferrovias)/ferrovias_cronologicas.gpkg"),
  quiet = TRUE
)

cat(sprintf("  ✓ Ferrovias reais carregadas: %d linhas\n\n", nrow(ferrovias_reais)))

## 3c. Geometria das AMCs do Nordeste (via geobr)
cat("Baixando geometria das AMCs do Nordeste (1970-2010)...\n")
amcs_geometria <- read_comparable_areas(start_year = 1970, end_year = 2010) |>
  filter(substr(list_code_muni_2010, 1, 1) == "2") |>
  distinct(code_amc, .keep_all = TRUE) |>
  st_make_valid() |>
  st_transform(31984)

cat(sprintf("  ✓ Geometria das AMCs carregada: %d polígonos\n\n", nrow(amcs_geometria)))

# 4. AGREGAÇÃO DE POPULAÇÃO ---------------------------------------------------
cat("========================================================================\n")
cat("AGREGANDO POPULAÇÃO MUNICIPAL PARA NÍVEL AMC\n")
cat("========================================================================\n\n")

## 4a. Dicionário AMC (municípios → AMCs)
amc_lookup <- read_comparable_areas(start_year = 1970, end_year = 2010) |>
  st_drop_geometry() |>
  select(code_muni = list_code_muni_2010, code_amc) |>
  mutate(code_muni = as.character(code_muni))

cat(sprintf("  ✓ Dicionário AMC criado: %d municípios mapeados\n", nrow(amc_lookup)))

## 4b. Limpeza e agregação de população
pop_clean <- população |>
  rename(code_muni = `Cód.`) |>
  mutate(code_muni = as.character(code_muni))

pop_amc <- pop_clean |>
  inner_join(amc_lookup, by = "code_muni") |>
  group_by(code_amc) |>
  summarise(across(starts_with("20"), sum, na.rm = TRUE)) |>
  ungroup()

cat(sprintf("  ✓ População agregada para %d AMCs\n\n", nrow(pop_amc)))

# 5. IDENTIFICAÇÃO DAS AMCs NAS PONTAS DAS FERROVIAS --------------------------
cat("========================================================================\n")
cat("IDENTIFICANDO AMCs NAS EXTREMIDADES (PONTAS) DAS FERROVIAS\n")
cat("========================================================================\n\n")

## 5a. Pontos de INÍCIO: primeiro ponto do primeiro segmento de cada ferrovia
origens_pts <- ferrovias_reais |>
  group_by(id) |>
  filter(cod_part == min(cod_part)) |>
  ungroup() |>
  suppressWarnings(st_cast("POINT")) |>
  group_by(id) |>
  slice(1) |>
  ungroup() |>
  st_transform(31984)

cat(sprintf("  ✓ %d pontos de origem identificados\n", nrow(origens_pts)))

## 5b. Pontos de FIM: último ponto do último segmento de cada ferrovia
destinos_pts <- ferrovias_reais |>
  group_by(id) |>
  filter(cod_part == max(cod_part)) |>
  ungroup() |>
  suppressWarnings(st_cast("POINT")) |>
  group_by(id) |>
  slice(n()) |>
  ungroup() |>
  st_transform(31984)

cat(sprintf("  ✓ %d pontos de destino identificados\n", nrow(destinos_pts)))

## 5c. Identificar AMCs que contêm pelo menos uma extremidade
extremidades <- bind_rows(
  origens_pts  |> select(id, Nome) |> mutate(tipo = "origem"),
  destinos_pts |> select(id, Nome) |> mutate(tipo = "destino")
)

codes_pontas <- st_join(
  amcs_geometria |> select(code_amc),
  extremidades,
  join = st_contains
) |>
  st_drop_geometry() |>
  filter(!is.na(id)) |>
  distinct(code_amc) |>
  pull(code_amc)

cat(sprintf("  ✓ %d AMCs nas extremidades das ferrovias\n\n", length(codes_pontas)))

# 6. CONSTRUÇÃO DA BASE ANALÍTICA COMPLETA ------------------------------------
cat("========================================================================\n")
cat("CONSTRUINDO BASE ANALÍTICA COMPLETA\n")
cat("========================================================================\n\n")

# Base principal: geometria AMCs + população + distâncias
dados <- amcs_geometria |>
  inner_join(pop_amc,       by = "code_amc") |>
  inner_join(base_distancias |> select(-starts_with("list")), by = "code_amc")

cat(sprintf("  ✓ Base completa: %d AMCs\n", nrow(dados)))
cat(sprintf("  ✓ Colunas disponíveis: %d\n", ncol(dados)))
cat(sprintf("  ✓ CRS: %s\n\n", st_crs(dados)$input))

# Versões especializadas da base (já criadas aqui para referência)
cat("Criando subamostras especializadas...\n\n")

# Submostra 1: Restrita a ≤ 200 km das ferrovias reais
dados_200km <- dados |>
  filter(dist_rail_real_2003 <= 200)

cat(sprintf("  ✓ Submostra (≤ 200 km):                  %d AMCs\n", nrow(dados_200km)))

# Submostra 2: ≤ 200 km E sem AMCs nas pontas
dados_sem_pontas <- dados_200km |>
  filter(!code_amc %in% codes_pontas)

cat(sprintf("  ✓ Submostra (≤ 200 km, sem pontas):     %d AMCs\n", nrow(dados_sem_pontas)))
cat(sprintf("  ✓ AMCs excluídas (pontas no raio 200km): %d\n\n", nrow(dados_200km) - nrow(dados_sem_pontas)))

# 7. VERIFICAÇÃO FINAL --------------------------------------------------------
cat("========================================================================\n")
cat("VERIFICAÇÃO FINAL\n")
cat("========================================================================\n\n")

cat("Resumo das variáveis principais na base `dados`:\n")
cat(sprintf("  • code_amc:           Código da AMC\n"))
cat(sprintf("  • code_muni:          Códigos dos municípios (lista)\n"))
cat(sprintf("  • name_amc:           Nome da AMC\n"))
cat(sprintf("  • Colunas de pop:     2000, 2003, ..., 2010 (população por ano)\n"))
cat(sprintf("  • dist_rail_real_XXXX: Distância até ferrovia real (metros)\n"))
cat(sprintf("  • dist_rail_sintetica: Distância até rede sintética LCP\n"))
cat(sprintf("  • geometry:           Geometria SF (multipolígonos)\n\n"))

# Verificar ausências de dados
cat("Verificando completude de dados (valores ausentes):\n")
missing_summary <- dados |>
  st_drop_geometry() |>
  summarise(across(everything(), ~sum(is.na(.)))) |>
  select(where(~. > 0))

if (ncol(missing_summary) == 0) {
  cat("  ✓ Nenhuma coluna com valores ausentes!\n\n")
} else {
  print(missing_summary)
  cat("\n")
}

cat("========================================================================\n")
cat("✅ BASE DE DADOS CRIADA COM SUCESSO!\n")
cat("========================================================================\n\n")

cat("Agora você pode usar:\n")
cat("  • `dados`:               Base completa (todas as AMCs)\n")
cat("  • `dados_200km`:         Restrita a ≤ 200 km das ferrovias reais\n")
cat("  • `dados_sem_pontas`:    ≤ 200 km e sem AMCs nas pontas\n\n")

cat("Para executar as análises IV, use:\n")
cat("  source('IV_Analise_Completa_SemMar.R')\n\n")