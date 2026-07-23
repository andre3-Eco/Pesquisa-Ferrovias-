# ==============================================================================
#  Etapa 06.1
#  CONTROLES CLIMÁTICOS POR AMC — WorldClim (10 minutos)
#  Projeto: Ferrovias Nordeste
#  Saída:   controles_clima_amcs_nordeste.csv / .rds
#  Fonte:   WorldClim v1 — https://www.worldclim.org/
# ==============================================================================

# 1. Pacotes -------------------------------------------------------------------
library(sf)
library(terra)
library(tidyverse)
library(geobr)

# 2. Caminhos ------------------------------------------------------------------
DIR_PROJETO  <- "C:/Users/André Elias/Documents/Pesquisa (Ferrovias)"
DIR_CLIMA    <- file.path(DIR_PROJETO, "02_dados_espaciais/raster_clima")
DIR_BIO      <- file.path(DIR_CLIMA, "bio_10m_esri/bio")
DIR_PREC     <- file.path(DIR_CLIMA, "prec_10m_esri/prec")
DIR_TMEAN    <- file.path(DIR_CLIMA, "tmean_10m_esri/tmean")

SAIDA_CSV    <- file.path(DIR_PROJETO, "controles_clima_amcs_nordeste.csv")
SAIDA_RDS    <- file.path(DIR_PROJETO, "controles_clima_amcs_nordeste.rds")

# 3. AMCs do Nordeste ----------------------------------------------

amcs_nordeste <- read_comparable_areas(start_year = 1970, end_year = 2010) |>
  filter(substr(list_code_muni_2010, 1, 1) == "2") |>
  distinct(code_amc, .keep_all = TRUE) |>
  st_make_valid() |>
  st_transform(4326)   # WGS84 — mesmo CRS dos rasters WorldClim

cat("  AMCs carregadas:", nrow(amcs_nordeste), "\n")

# 4. Variáveis Bioclimáticas (BIO1 a BIO19) ------------------------------------

# Carregando rasters bioclimáticos
bio_paths <- file.path(DIR_BIO, paste0("bio_", 1:19))
bio_stack <- rast(bio_paths)
names(bio_stack) <- paste0("bio_", 1:19)

# Extraindo médias por AMC 
bio_extract <- terra::extract(
  bio_stack,
  vect(amcs_nordeste),
  fun   = mean,
  na.rm = TRUE
)

# WorldClim armazena temperatura em °C × 10 → dividir por 10
# BIO1–BIO11 = variáveis de temperatura; BIO12–BIO19 = precipitação (mm)
bio_extract <- bio_extract |>
  mutate(across(paste0("bio_", 1:11), ~ . / 10))

bio_extract$code_amc <- amcs_nordeste$code_amc
bio_extract <- select(bio_extract, -ID)

cat("  BIO extraídas:", ncol(bio_extract) - 1, "variáveis\n")

# 5. Precipitação Mensal (prec_1 a prec_12) ------------------------------------
prec_paths <- file.path(DIR_PREC, paste0("prec_", 1:12))
prec_stack <- rast(prec_paths)
names(prec_stack) <- paste0("prec_", 1:12)

prec_extract <- terra::extract(
  prec_stack,
  vect(amcs_nordeste),
  fun   = mean,
  na.rm = TRUE
)

prec_extract$code_amc <- amcs_nordeste$code_amc
prec_extract <- select(prec_extract, -ID)

cat("  Precipitação mensal extraída:", ncol(prec_extract) - 1, "variáveis\n")

# 6. Temperatura Média Mensal (tmean_1 a tmean_12) -----------------------------
tmean_paths <- file.path(DIR_TMEAN, paste0("tmean_", 1:12))
tmean_stack <- rast(tmean_paths)
names(tmean_stack) <- paste0("tmean_", 1:12)

tmean_extract <- terra::extract(
  tmean_stack,
  vect(amcs_nordeste),
  fun   = mean,
  na.rm = TRUE
)

# WorldClim temperatura × 10 → dividir por 10
tmean_extract <- tmean_extract |>
  mutate(across(starts_with("tmean_"), ~ . / 10))

tmean_extract$code_amc <- amcs_nordeste$code_amc
tmean_extract <- select(tmean_extract, -ID)

cat("  Temperatura mensal extraída:", ncol(tmean_extract) - 1, "variáveis\n")

# 7. Consolidar base final ------------------------------------------------------
controles_clima <- bio_extract |>
  left_join(prec_extract,  by = "code_amc") |>
  left_join(tmean_extract, by = "code_amc") |>
  select(code_amc, everything())

cat("  Dimensão final:", nrow(controles_clima), "AMCs x",
    ncol(controles_clima) - 1, "variáveis climáticas\n")

# 8. Verificação de NAs --------------------------------------------------------
n_nas <- sum(is.na(controles_clima))
if (n_nas == 0) {
  cat("  Nenhum NA encontrado — extração completa.\n")
} else {
  cat("  ATENÇÃO:", n_nas, "NAs encontrados.\n")
  controles_clima |>
    summarise(across(everything(), ~sum(is.na(.)))) |>
    pivot_longer(everything(), names_to = "var", values_to = "n_na") |>
    filter(n_na > 0) |>
    print()
}

# 9. Salvar --------------------------------------------------------------------
write_csv(controles_clima, SAIDA_CSV)
saveRDS(controles_clima,   SAIDA_RDS)
cat("  Salvo em:", SAIDA_CSV, "\n")
cat("  Salvo em:", SAIDA_RDS, "\n")
