# ==============================================================================
#  Etapa 06.2
#  CONTROLES PEDOLÓGICOS POR AMC — Solos do Brasil (IBGE/EMBRAPA)
#  Projeto: Ferrovias Nordeste
#  Saída:   controles_solo_amcs_nordeste.csv / .rds
#  Fonte:   IBGE/EMBRAPA — Pedologia 1:5.000.000 (2020)
# ==============================================================================

# 1. Pacotes -------------------------------------------------------------------
library(sf)
library(tidyverse)
library(geobr)

# 2. Caminhos ------------------------------------------------------------------
DIR_PROJETO  <- "C:/Users/André Elias/Documents/Pesquisa (Ferrovias)"
SOLOS_SHP    <- file.path(
  DIR_PROJETO,
  "02_dados_espaciais/VETORES_AMBIENTAIS/brasil_solos_5m_20201104/brasil_solos_5m_20201104.shp"
)

SAIDA_CSV    <- file.path(DIR_PROJETO, "controles_solo_amcs_nordeste.csv")
SAIDA_RDS    <- file.path(DIR_PROJETO, "controles_solo_amcs_nordeste.rds")

# 3. AMCs do Nordeste (via geobr) ----------------------------------------------

amcs_nordeste <- read_comparable_areas(start_year = 1970, end_year = 2010) |>
  filter(substr(list_code_muni_2010, 1, 1) == "2") |>
  distinct(code_amc, .keep_all = TRUE) |>
  st_make_valid() |>
  st_transform(4326)   # WGS84 — mesmo CRS do shapefile de solos

cat("  AMCs carregadas:", nrow(amcs_nordeste), "\n")

# 4. Shapefile de Solos --------------------------------------------------------


solos <- st_read(SOLOS_SHP, quiet = TRUE) |>
  # Manter apenas colunas necessárias
  select(ordem1, geometry)

cat("  Feições de solo carregadas:", nrow(solos), "\n")
cat("  Ordens de solo únicas:",
    length(unique(solos$ordem1[!is.na(solos$ordem1)])), "\n")

# Verificar e corrigir geometrias inválidas
n_invalidas <- sum(!st_is_valid(solos))
if (n_invalidas > 0) {
  cat("  Corrigindo", n_invalidas, "geometrias inválidas...\n")
  solos <- st_make_valid(solos)
}

# NAs em ordem1 correspondem a áreas de água e dunas
solos <- solos |>
  mutate(ordem1 = if_else(is.na(ordem1), "AGUA_DUNAS", ordem1))

# 5. Interseção Espacial Solos × AMCs ------------------------------------------

# Desligar validação esférica s2 para evitar erros de topologia
sf_use_s2(FALSE)

solos_amcs <- st_intersection(
  solos,
  amcs_nordeste |> select(code_amc)
)

# Calcular área de cada fragmento resultante (km²)
solos_amcs <- solos_amcs |>
  mutate(area_frag_km2 = as.numeric(st_area(geometry)) / 1e6)

sf_use_s2(TRUE)

cat("  Fragmentos resultantes:", nrow(solos_amcs), "\n")
cat("  AMCs cobertas:", n_distinct(solos_amcs$code_amc), "\n")

# 6. Estatísticas por AMC ------------------------------------------------------

solos_tbl <- st_drop_geometry(solos_amcs)

# Área total mapeada por AMC
area_total_amc <- solos_tbl |>
  group_by(code_amc) |>
  summarise(area_mapeada_km2 = sum(area_frag_km2, na.rm = TRUE))

# Percentual de cada ordem de solo por AMC
pct_ordens <- solos_tbl |>
  group_by(code_amc, ordem1) |>
  summarise(area_ordem_km2 = sum(area_frag_km2, na.rm = TRUE), .groups = "drop") |>
  left_join(area_total_amc, by = "code_amc") |>
  mutate(pct = 100 * area_ordem_km2 / area_mapeada_km2) |>
  select(code_amc, ordem1, pct)

# Pivotar para formato largo (uma coluna por ordem de solo)
pct_wide <- pct_ordens |>
  pivot_wider(
    names_from  = ordem1,
    values_from = pct,
    values_fill = 0,
    names_prefix = "pct_solo_"
  ) |>
  rename_with(
    ~ str_to_lower(.) |>
      str_replace_all(" ", "_") |>
      str_replace_all("[^a-z0-9_]", ""),
    starts_with("pct_solo_")
  )

# Classe de solo dominante por AMC (maior percentual de área)
classe_dom <- pct_ordens |>
  group_by(code_amc) |>
  slice_max(pct, n = 1, with_ties = FALSE) |>
  ungroup() |>
  select(code_amc,
         solo_dominante  = ordem1,
         pct_dominante   = pct)

# 7. Consolidar base final ------------------------------------------------------

controles_solo <- pct_wide |>
  left_join(classe_dom,      by = "code_amc") |>
  left_join(area_total_amc,  by = "code_amc") |>
  select(code_amc, solo_dominante, pct_dominante, area_mapeada_km2, everything())

cat("  Dimensão final:", nrow(controles_solo), "AMCs x",
    ncol(controles_solo) - 1, "colunas\n")

# AMCs sem cobertura de solo no shapefile
amcs_sem_solo <- setdiff(amcs_nordeste$code_amc, controles_solo$code_amc)
if (length(amcs_sem_solo) > 0) {
  cat("  ATENÇÃO:", length(amcs_sem_solo),
      "AMCs sem cobertura de solo (provavelmente bordas/ilhas pequenas).\n")
}

# 8. Verificação de NAs --------------------------------------------------------
n_nas <- sum(is.na(controles_solo))
if (n_nas == 0) {
  cat("  Nenhum NA encontrado.\n")
} else {
  cat("  ATENÇÃO:", n_nas, "NAs encontrados.\n")
  controles_solo |>
    summarise(across(everything(), ~sum(is.na(.)))) |>
    pivot_longer(everything(), names_to = "var", values_to = "n_na") |>
    filter(n_na > 0) |>
    print()
}

# 9. Salvar --------------------------------------------------------------------
cat("Salvando arquivos...\n")
write_csv(controles_solo, SAIDA_CSV)
saveRDS(controles_solo,   SAIDA_RDS)
cat("  Salvo em:", SAIDA_CSV, "\n")
cat("  Salvo em:", SAIDA_RDS, "\n")




