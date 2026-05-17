# ==============================================================================
#  CONTROLES HIDROGRÁFICOS POR AMC — Rede de Rios ANA (BHO)
#  Projeto: Ferrovias Nordeste
#  Saída:   controles_rios_amcs_nordeste.csv / .rds
#  Fonte:   ANA — Base Hidrográfica Ottocodificada (GEOFT_BHO_REF_RIO)
# ==============================================================================

# 1. Pacotes -------------------------------------------------------------------
library(sf)
library(tidyverse)
library(geobr)

# 2. Caminhos ------------------------------------------------------------------
DIR_PROJETO  <- "C:/Users/André Elias/Documents/Pesquisa (Ferrovias)"
RIOS_SHP     <- file.path(
  DIR_PROJETO,
  "02_dados_espaciais/VETORES_AMBIENTAIS/GEOFT_BHO_REF_RIO/GEOFT_BHO_REF_RIO.shp"
)

SAIDA_CSV    <- file.path(DIR_PROJETO, "controles_rios_amcs_nordeste.csv")
SAIDA_RDS    <- file.path(DIR_PROJETO, "controles_rios_amcs_nordeste.rds")

# CRS de trabalho: UTM Zona 24S (SIRGAS 2000) — distâncias em metros
CRS_UTM <- 31984

# 3. AMCs do Nordeste (via geobr) ----------------------------------------------
cat("Carregando AMCs do Nordeste...\n")

amcs_nordeste <- read_comparable_areas(start_year = 1970, end_year = 2010) |>
  filter(substr(list_code_muni_2010, 1, 1) == "2") |>
  distinct(code_amc, .keep_all = TRUE) |>
  st_make_valid() |>
  st_transform(CRS_UTM)

cat("  AMCs carregadas:", nrow(amcs_nordeste), "\n")

# 4. Rede Hidrográfica ANA (BHO) -----------------------------------------------
cat("Carregando rede hidrográfica (ANA)...\n")

rios_raw <- st_read(RIOS_SHP, quiet = TRUE)

cat("  Feições de rio carregadas:", nrow(rios_raw), "\n")
cat("  CRS original:", st_crs(rios_raw)$input, "\n")

# 5. Derivar Hierarquia Hidrográfica pelo Código Otto (CORIO) ------------------
#
#  O código Otto (CORIO) é hierárquico: menos dígitos = bacia/rio maior.
#  Formato: "8641516_0" → nº de dígitos antes do "_" indica o nível.
#  Classificação adotada:
#    ≤ 7 dígitos : rio principal (grandes bacias)
#    8–9 dígitos : rio médio (sub-bacias)
#    ≥ 10 dígitos: tributário (microbacias)
#
rios <- rios_raw |>
  mutate(
    otto_digits = nchar(gsub("_.*", "", CORIO)),
    nivel_rio   = case_when(
      otto_digits <= 7  ~ "principal",
      otto_digits <= 9  ~ "medio",
      TRUE              ~ "tributario"
    )
  )

cat("  Distribuição por nível:\n")
print(count(st_drop_geometry(rios), nivel_rio))

# 6. Reprojetar e Recortar para o Nordeste ------------------------------------
cat("Reprojetando e recortando para o bbox do Nordeste...\n")

bbox_ne <- st_bbox(amcs_nordeste)

rios_utm <- rios |>
  st_transform(CRS_UTM) |>
  st_crop(bbox_ne)

cat("  Feições após recorte:", nrow(rios_utm), "\n")

# 7. Distância do Centroide de Cada AMC ao Rio Mais Próximo -------------------
cat("Calculando distâncias ao rio mais próximo...\n")
cat("  (Pode levar alguns minutos)\n")

centroides <- st_centroid(amcs_nordeste)

# Distância a qualquer rio
dist_qualquer <- st_distance(centroides, rios_utm)
dist_rio_m    <- apply(dist_qualquer, 1, min)

# Distância apenas a rios principais
rios_principais <- filter(rios_utm, nivel_rio == "principal")
dist_principal  <- st_distance(centroides, rios_principais)
dist_principal_m <- apply(dist_principal, 1, min)

dist_df <- tibble(
  code_amc              = amcs_nordeste$code_amc,
  dist_rio_km           = dist_rio_m / 1000,
  dist_rio_principal_km = dist_principal_m / 1000
)

cat("  Distâncias calculadas.\n")

# 8. Interseção Rios × AMCs (comprimentos e contagens) ------------------------
cat("Executando interseção rios × AMCs...\n")

sf_use_s2(FALSE)

rios_in_amcs <- st_intersection(
  rios_utm |> select(NORIOCOMP, nivel_rio, otto_digits),
  amcs_nordeste |> select(code_amc)
) |>
  mutate(comp_segmento_km = as.numeric(st_length(geometry)) / 1000)

sf_use_s2(TRUE)

cat("  Segmentos resultantes:", nrow(rios_in_amcs), "\n")

# 9. Estatísticas por AMC ------------------------------------------------------
cat("Calculando estatísticas hidrográficas por AMC...\n")

area_amc_km2 <- tibble(
  code_amc     = amcs_nordeste$code_amc,
  area_amc_km2 = as.numeric(st_area(amcs_nordeste)) / 1e6
)

stats_rios <- st_drop_geometry(rios_in_amcs) |>
  group_by(code_amc) |>
  summarise(
    # Comprimentos totais
    comp_total_rios_km      = sum(comp_segmento_km, na.rm = TRUE),
    comp_rios_principais_km = sum(comp_segmento_km[nivel_rio == "principal"], na.rm = TRUE),
    comp_maior_rio_km       = max(comp_segmento_km, na.rm = TRUE),
    # Contagens
    n_segmentos_rios        = n(),
    n_rios_distintos        = n_distinct(NORIOCOMP[!is.na(NORIOCOMP)]),
    # Código Otto mínimo = rio mais importante presente na AMC
    otto_min                = min(otto_digits, na.rm = TRUE),
    .groups = "drop"
  ) |>
  # Tratar Inf gerado quando otto_digits é NA para todos os rios da AMC
  mutate(otto_min = if_else(is.infinite(otto_min), NA_real_, as.numeric(otto_min)))

# Juntar área e calcular densidade hidrográfica
stats_rios <- stats_rios |>
  left_join(area_amc_km2, by = "code_amc") |>
  mutate(densidade_hidro_km_km2 = comp_total_rios_km / area_amc_km2) |>
  select(-area_amc_km2)

# 10. Consolidar base final ----------------------------------------------------
cat("Consolidando base...\n")

controles_rios <- area_amc_km2 |>
  left_join(dist_df,    by = "code_amc") |>
  left_join(stats_rios, by = "code_amc") |>
  # AMCs sem rios internos → comprimentos e contagens = 0
  mutate(
    comp_total_rios_km      = replace_na(comp_total_rios_km, 0),
    comp_rios_principais_km = replace_na(comp_rios_principais_km, 0),
    comp_maior_rio_km       = replace_na(comp_maior_rio_km, 0),
    n_segmentos_rios        = replace_na(n_segmentos_rios, 0L),
    n_rios_distintos        = replace_na(n_rios_distintos, 0L),
    densidade_hidro_km_km2  = replace_na(densidade_hidro_km_km2, 0),
    # % do comprimento total que é de rios principais
    pct_comp_principal      = if_else(
      comp_total_rios_km > 0,
      100 * comp_rios_principais_km / comp_total_rios_km,
      0
    )
  ) |>
  select(
    code_amc,
    area_amc_km2,
    dist_rio_km,
    dist_rio_principal_km,
    comp_total_rios_km,
    comp_rios_principais_km,
    pct_comp_principal,
    comp_maior_rio_km,
    densidade_hidro_km_km2,
    n_rios_distintos,
    n_segmentos_rios,
    otto_min
  )

cat("  Dimensão final:", nrow(controles_rios), "AMCs x",
    ncol(controles_rios) - 1, "variáveis\n")

# 11. Verificação de NAs -------------------------------------------------------
na_check <- controles_rios |>
  summarise(across(everything(), ~sum(is.na(.)))) |>
  pivot_longer(everything(), names_to = "var", values_to = "n_na") |>
  filter(n_na > 0)

if (nrow(na_check) == 0) {
  cat("  Nenhum NA crítico encontrado.\n")
} else {
  cat("  Variáveis com NA:\n")
  print(na_check)
  cat("  Nota: NAs em otto_min indicam AMCs cujos rios não têm código Otto.\n")
}

# 12. Salvar -------------------------------------------------------------------
cat("Salvando arquivos...\n")
write_csv(controles_rios, SAIDA_CSV)
saveRDS(controles_rios,   SAIDA_RDS)
cat("  Salvo em:", SAIDA_CSV, "\n")
cat("  Salvo em:", SAIDA_RDS, "\n")

# 13. Dicionário das variáveis -------------------------------------------------
cat("\n=== DICIONÁRIO DE VARIÁVEIS ===\n")
cat("area_amc_km2          : Área total da AMC (km²)\n")
cat("dist_rio_km           : Distância do centroide ao rio mais próximo (km)\n")
cat("dist_rio_principal_km : Distância do centroide ao rio principal mais próximo (km)\n")
cat("comp_total_rios_km    : Comprimento total de rios dentro da AMC (km)\n")
cat("comp_rios_principais_km: Comprimento de rios principais dentro da AMC (km)\n")
cat("pct_comp_principal    : % do comprimento total que é de rios principais\n")
cat("comp_maior_rio_km     : Comprimento do maior segmento de rio na AMC (km)\n")
cat("densidade_hidro_km_km2: Densidade hidrográfica (km de rio / km² de área)\n")
cat("n_rios_distintos      : Nº de rios com nome diferente na AMC\n")
cat("n_segmentos_rios      : Nº total de segmentos hidrográficos na AMC\n")
cat("otto_min              : Menor código Otto da AMC (menor = rio mais importante)\n")
cat("\nNota: A hierarquia Otto classifica rios em:\n")
cat("  principal  (≤ 7 dígitos): grandes rios/bacias\n")
cat("  medio      (8–9 dígitos): rios de porte médio\n")
cat("  tributario (≥ 10 dígitos): pequenos cursos\n")
cat("\nNota para regressão: dist_rio_km e densidade_hidro_km_km2 são os controles\n")
cat("mais diretos para capturar transporte hidroviário alternativo às ferrovias.\n")
