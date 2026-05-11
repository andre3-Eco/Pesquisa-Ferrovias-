# ==============================================================================
# REDE FERROVIÁRIA SINTÉTICA (LCP) COM PARES O-D REAIS — SEM CRUZAR O MAR
# Usa os pontos de início e fim das ferrovias históricas reais como pares O-D.
# Máscara de terra aplicada ao raster de condutância para evitar rotas pelo mar.
# ==============================================================================

# 1. AMBIENTE E PACOTES --------------------------------------------------------
rm(list = setdiff(ls(), "data.wd"))
gc()

libraries <- c("tidyverse", "sf", "terra", "leastcostpath")
pacotes_ausentes <- libraries[!(libraries %in% installed.packages()[,"Package"])]
if (length(pacotes_ausentes) > 0) {
  cat("Instalando pacotes ausentes:", paste(pacotes_ausentes, collapse = ", "), "\n")
  install.packages(pacotes_ausentes, dependencies = TRUE)
}
invisible(lapply(libraries, require, character.only = TRUE))

if (!exists("data.wd")) data.wd <- getwd()

# Caminhos
input_cost_file <- paste0(data.wd, "/cost_raster_ferrovias_ne_1880_1920_90m.tif")
ferrovias_gpkg  <- paste0(data.wd, "/Dados pesquisa (Ferrovias)/ferrovias_cronologicas.gpkg")
amcs_gpkg       <- paste0(data.wd, "/Dados pesquisa (Ferrovias)/ferrovias_cronologicas.gpkg")
output_gpkg     <- paste0(data.wd, "/Dados pesquisa (Ferrovias)/Rotas_LCP_OD_Real_SemMar.gpkg")

# ==============================================================================
# 2. PREPARAÇÃO DO RASTER DE CUSTO COM MÁSCARA DE TERRA
# ==============================================================================
cat("Lendo raster de custo...\n")
cost_raster_terra <- rast(input_cost_file)

if (is.na(crs(cost_raster_terra)) || crs(cost_raster_terra) == "") {
  crs(cost_raster_terra) <- "EPSG:31983"
}
target_crs_raster <- st_crs(cost_raster_terra)

# Agrega para ~270m (eficiência computacional)
cat("Agregando raster para 270m...\n")
cost_raster_opt <- terra::aggregate(cost_raster_terra, fact = 3, fun = "mean", na.rm = TRUE)

max_cost_value <- 9999999
cost_raster_opt <- terra::ifel(
  is.na(cost_raster_opt) | is.infinite(cost_raster_opt),
  max_cost_value,
  cost_raster_opt
)

# Raster de condutância base (inverso do custo)
condutancia_base <- terra::ifel(cost_raster_opt < max_cost_value, 1 / cost_raster_opt, 0)

# --------------------------------------------------------------------------
# MÁSCARA DE TERRA: zera condutância no oceano usando os polígonos das AMCs
# --------------------------------------------------------------------------
cat("Aplicando máscara de terra (oceano intransitável)...\n")
library(geobr)
amcs_nordeste <- read_comparable_areas(start_year = 1970, end_year = 2010) |>
  filter(substr(list_code_muni_2010, 1, 1) == "2")

land_poly <- st_union(amcs_nordeste) |>
  st_transform(target_crs_raster)

land_vect <- terra::vect(land_poly)

condutancia_mascarada <- terra::mask(
  condutancia_base,
  land_vect,
  inverse     = FALSE,
  updatevalue = 0
)

# ==============================================================================
# 3. EXTRAÇÃO DOS PARES O-D DAS FERROVIAS REAIS
# ==============================================================================
cat("Extraindo pontos de início e fim das ferrovias reais...\n")
ferrovias_reais <- st_read(ferrovias_gpkg, quiet = TRUE)

# ORIGENS: primeiro ponto do primeiro segmento (cod_part mínimo) de cada ferrovia
origens_reais <- ferrovias_reais |>
  group_by(id) |>
  filter(cod_part == min(cod_part)) |>
  ungroup()

origens_pts <- suppressWarnings(st_cast(origens_reais, "POINT")) |>
  group_by(id) |>
  slice(1) |>
  ungroup() |>
  st_transform(target_crs_raster)

# DESTINOS: último ponto do último segmento (cod_part máximo) de cada ferrovia
destinos_reais <- ferrovias_reais |>
  group_by(id) |>
  filter(cod_part == max(cod_part)) |>
  ungroup()

destinos_pts <- suppressWarnings(st_cast(destinos_reais, "POINT")) |>
  group_by(id) |>
  slice(n()) |>
  ungroup() |>
  st_transform(target_crs_raster)

# Filtrar pares com distância mínima de 5 km (evita rotas degeneradas)
dist_od <- as.numeric(st_distance(origens_pts, destinos_pts, by_element = TRUE)) / 1000

cat(sprintf("Total de ferrovias: %d\n", nrow(origens_pts)))
cat(sprintf("Excluídas (O ≈ D, dist < 5 km): %d\n", sum(dist_od < 5)))

ids_validos    <- which(dist_od >= 5)
origens_valid  <- origens_pts[ids_validos, ]
destinos_valid <- destinos_pts[ids_validos, ]

cat(sprintf("Pares O-D válidos: %d\n\n", length(ids_validos)))

# ==============================================================================
# 4. FUNÇÃO DE SNAPPING: move pontos para a célula de terra mais próxima
# ==============================================================================
# Necessário porque origens/destinos costeiros podem cair em células com
# condutância = 0 (oceano), impedindo a criação do grafo pelo leastcostpath.
# O snap é feito DENTRO do raster local (já cropado) para garantir consistência.

snap_to_local_land <- function(pt, local_raster) {
  val <- tryCatch(terra::extract(local_raster, terra::vect(pt))[[2]], error = function(e) NA)
  if (!is.na(val) && val > 0) return(pt)  # já está em terra

  land_pts <- terra::as.points(terra::ifel(local_raster > 0, local_raster, NA))
  if (length(land_pts) == 0) return(NULL)

  dists   <- terra::distance(terra::vect(pt), land_pts)
  nearest <- st_as_sf(land_pts[which.min(dists)])
  st_geometry(pt) <- st_geometry(st_transform(nearest, st_crs(pt)))
  return(pt)
}

# ==============================================================================
# 5. CÁLCULO DAS ROTAS LCP (JANELA MÓVEL + MÁSCARA DE TERRA)
# ==============================================================================
cat(sprintf("Iniciando cálculo de %d rotas LCP...\n\n", nrow(origens_valid)))

lcp_list <- list()

for (i in seq_len(nrow(origens_valid))) {
  pt_start_raw <- origens_valid[i, ]
  pt_end_raw   <- destinos_valid[i, ]
  nome_rota    <- pt_start_raw$Nome

  cat(sprintf("Rota [%d/%d] — %s: ", i, nrow(origens_valid), nome_rota))

  # Janela móvel (bounding box + buffer 1.2° ≈ 130 km)
  # terra::extend(..., 5) adiciona 5 células de margem para evitar pontos na borda
  pts_union      <- st_union(pt_start_raw, pt_end_raw)
  route_envelope <- st_buffer(pts_union, dist = 1.2)

  local_cond <- tryCatch({
    cropped <- terra::crop(condutancia_mascarada, terra::vect(route_envelope))
    terra::extend(cropped, 5)
  }, error = function(e) NULL)

  if (is.null(local_cond)) { cat("Falha no recorte.\n"); next }

  # Snap dos pontos para terra no raster local
  pt_start <- snap_to_local_land(pt_start_raw, local_cond)
  pt_end   <- snap_to_local_land(pt_end_raw,   local_cond)

  if (is.null(pt_start) || is.null(pt_end)) { cat("Snap falhou.\n"); next }

  # Criar grafo e calcular rota
  path <- tryCatch({
    local_cs <- leastcostpath::create_cs(local_cond, neighbours = 16)
    leastcostpath::create_lcp(x = local_cs, origin = pt_start, destination = pt_end)
  }, error = function(e) {
    cat(sprintf("Erro: %s ", e$message)); NULL
  })

  if (!is.null(path)) {
    path <- path |>
      mutate(
        id        = pt_start_raw$id,
        Nome      = nome_rota,
        ano_inaug = pt_start_raw$ano_inaug,
        tipo_rota = "LCP_OD_SemMar"
      )
    lcp_list[[length(lcp_list) + 1]] <- path
    cat("✅\n")
  } else {
    cat("❌\n")
  }
}

# ==============================================================================
# 6. EXPORTAÇÃO
# ==============================================================================
cat("\n")

if (length(lcp_list) == 0) {
  cat("⚠️ NENHUMA ROTA FOI GERADA. Verifique os arquivos de entrada.\n")
} else {
  instrumento_final <- do.call(rbind, lcp_list)
  write_sf(instrumento_final, output_gpkg, delete_layer = TRUE)
  cat(sprintf("🎉 Conclusão! %d rotas salvas em:\n   %s\n",
              nrow(instrumento_final), output_gpkg))
}
