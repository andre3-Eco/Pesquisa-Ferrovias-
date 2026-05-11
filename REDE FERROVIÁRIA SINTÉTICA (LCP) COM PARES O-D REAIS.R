# ==============================================================================
# REDE FERROVIÁRIA SINTÉTICA (LCP) COM PARES O-D REAIS
# Mesma estratégia do LCP04.R, mas usando os pontos de início e fim
# das ferrovias históricas reais como pares Origem-Destino.
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
output_gpkg     <- paste0(data.wd, "/Variavel_Instrumental_LCP_OD_Real.gpkg")

# ==============================================================================
# 2. PREPARAÇÃO DO RASTER DE CUSTO
# ==============================================================================
cat("Lendo raster de custo...\n")
cost_raster_terra <- rast(input_cost_file)

if (is.na(crs(cost_raster_terra)) || crs(cost_raster_terra) == "") {
  crs(cost_raster_terra) <- "EPSG:31983"
}
target_crs_raster <- st_crs(cost_raster_terra)

# Agrega para ~270m para eficiência computacional (igual ao LCP04.R)
cat("Agregando raster para 270m...\n")
cost_raster_opt <- terra::aggregate(cost_raster_terra, fact = 3, fun = "mean", na.rm = TRUE)

# Substitui NA/Inf por muro de barreira
max_cost_value <- 9999999
cost_raster_opt <- terra::ifel(
  is.na(cost_raster_opt) | is.infinite(cost_raster_opt),
  max_cost_value,
  cost_raster_opt
)

# Gera raster de condutância (inverso do custo)
condutancia_base <- terra::ifel(cost_raster_opt < max_cost_value, 1 / cost_raster_opt, 0)

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

# Filtrar pares com distância mínima (> 5 km) para evitar rotas degeneradas
dist_od <- as.numeric(st_distance(origens_pts, destinos_pts, by_element = TRUE)) / 1000

cat(sprintf("Total de ferrovias: %d\n", nrow(origens_pts)))
cat(sprintf("Ferrovias excluídas (O ≈ D, dist < 5 km): %d\n", sum(dist_od < 5)))

ids_validos   <- which(dist_od >= 5)
origens_valid <- origens_pts[ids_validos, ]
destinos_valid <- destinos_pts[ids_validos, ]

cat(sprintf("Pares O-D válidos para LCP: %d\n\n", length(ids_validos)))

# ==============================================================================
# 4. CÁLCULO DAS ROTAS LCP (JANELA MÓVEL — mesma arquitetura do LCP04.R)
# ==============================================================================
cat(sprintf("Iniciando cálculo de %d rotas LCP...\n", nrow(origens_valid)))

lcp_list <- list()

for (i in 1:nrow(origens_valid)) {
  pt_start <- origens_valid[i, ]
  pt_end   <- destinos_valid[i, ]
  
  cat(sprintf("\nRota [%d/%d] — %s: ", i, nrow(origens_valid), pt_start$Nome))
  
  # ----------------------------------------------------------
  # JANELA MÓVEL (BOUNDING BOX + buffer 100km)
  # Permite desvios de serras sem carregar o Nordeste inteiro
  # ----------------------------------------------------------
  pts_union      <- st_union(pt_start, pt_end)
  route_envelope <- st_buffer(pts_union, dist = 100000)
  
  local_condutancia <- tryCatch({
    terra::crop(condutancia_base, route_envelope)
  }, error = function(e) NULL)
  
  if (is.null(local_condutancia)) {
    cat("Falha no recorte do raster. Pulando.\n")
    next
  }
  
  # ----------------------------------------------------------
  # GRAFO E ROTA
  # ----------------------------------------------------------
  path <- tryCatch({
    local_cs <- leastcostpath::create_cs(local_condutancia, neighbours = 16)
    leastcostpath::create_lcp(
      x           = local_cs,
      origin      = pt_start,
      destination = pt_end
    )
  }, error = function(e) {
    cat(sprintf("Erro no LCP: %s ", e$message))
    return(NULL)
  })
  
  if (!is.null(path)) {
    path <- path |>
      mutate(
        id         = pt_start$id,
        Nome       = pt_start$Nome,
        ano_inaug  = pt_start$ano_inaug,
        tipo_rota  = "LCP_OD_Real"
      )
    lcp_list[[length(lcp_list) + 1]] <- path
    cat("✅ Sucesso!")
  }
}

# ==============================================================================
# 5. EXPORTAÇÃO
# ==============================================================================
cat("\n\n")

if (length(lcp_list) == 0) {
  cat("⚠️ NENHUMA ROTA FOI GERADA. Verifique os arquivos de entrada.\n")
} else {
  instrumento_final <- do.call(rbind, lcp_list)
  write_sf(instrumento_final, output_gpkg, delete_layer = TRUE)
  cat(sprintf("🎉 Conclusão! %d rotas LCP salvas em:\n   %s\n",
              nrow(instrumento_final), output_gpkg))
}