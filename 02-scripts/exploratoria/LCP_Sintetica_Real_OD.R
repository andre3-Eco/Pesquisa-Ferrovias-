# ==============================================================================
# REDE FERROVIÁRIA SINTÉTICA (LCP) COM PARES O-D REAIS (LÓGICA RAIZ-PONTA)
# CORREÇÃO DA SEÇÃO 5: Tratamento de NAs, Snapping Otimizado e Diagnóstico
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

input_cost_file <- paste0(data.wd, "/cost_raster_ferrovias_ne_1880_1920_90m.tif")
ferrovias_gpkg  <- paste0(data.wd, "/05-geometrias/ferrovias_cronologicas.gpkg")
output_gpkg     <- paste0(data.wd, "/05-geometrias/Rotas_LCP_OD_Real.gpkg")

# ==============================================================================
# 2. PREPARAÇÃO DO RASTER DE CUSTO COM MÁSCARA DE TERRA
# ==============================================================================
cat("Lendo raster de custo...\n")
cost_raster_terra <- rast(input_cost_file)

if (is.na(crs(cost_raster_terra)) || crs(cost_raster_terra) == "") {
  crs(cost_raster_terra) <- "EPSG:4674" # Assume SIRGAS 2000 se não houver metadado
}
target_crs_raster <- st_crs(cost_raster_terra)

cat("Agregando raster para 270m...\n")
cost_raster_opt <- terra::aggregate(cost_raster_terra, fact = 3, fun = "mean", na.rm = TRUE)

max_cost_value <- 9999999
cost_raster_opt <- terra::ifel(
  is.na(cost_raster_opt) | is.infinite(cost_raster_opt),
  max_cost_value,
  cost_raster_opt
)

condutancia_base <- terra::ifel(cost_raster_opt < max_cost_value, 1 / cost_raster_opt, 0)

cat("Gerando polígono continental com Recuo Costeiro...\n")
library(geobr)

if(exists("amcs_geometria")) {
  amcs_nordeste <- amcs_geometria 
} else {
  amcs_nordeste <- read_comparable_areas(start_year = 1970, end_year = 2010) |>
    filter(substr(list_code_muni_2010, 1, 1) == "2")
}

# 1. Funde os municípios e previne erros topológicos
land_poly <- st_union(amcs_nordeste) |> 
  st_transform(target_crs_raster) |>
  st_make_valid() 

# 2. O RIGOR: Buffer Negativo corrigido (Graus vs Metros)
if (st_is_longlat(target_crs_raster)) {
  # Se for Lat/Lon: 1 grau de latitude equivale a ~111.320 metros
  recuo_dist <- -2500 / 111320 
  cat(sprintf("CRS geográfico detetado. Aplicando recuo de %.4f graus (~2.5 km)...\n", abs(recuo_dist)))
} else {
  # Se for UTM projetado:
  recuo_dist <- -2500
  cat("CRS métrico detetado. Aplicando recuo de 2500 metros...\n")
}

land_poly_rigoroso <- st_buffer(land_poly, dist = recuo_dist)
land_vect <- terra::vect(land_poly_rigoroso)

cat("Aplicando máscara definitiva na condutância...\n")
condutancia_mascarada <- terra::mask(
  condutancia_base, land_vect, inverse = FALSE
)

# ==============================================================================
# 3. EXTRAÇÃO DOS PARES O-D (LÓGICA RAIZ PARA AS PONTAS)
# ==============================================================================
cat("Lendo ferrovias e extraindo Origem Histórica e Destinos por ramal...\n")
ferrovias_reais <- st_read(ferrovias_gpkg, quiet = TRUE)
crs_ferrovias   <- st_crs(ferrovias_reais)
snap_tol        <- 50 

od_pairs <- ferrovias_reais |>
  arrange(id, cod_part) |>
  group_by(id, Nome) |>
  group_modify(~ {
    df_id <- .x
    
    pts_list <- lapply(seq_len(nrow(df_id)), function(i) {
      coords <- st_coordinates(st_geometry(df_id[i, ]))
      p1 <- coords[1, 1:2]              
      p2 <- coords[nrow(coords), 1:2]   
      
      data.frame(
        cod_part  = df_id$cod_part[i],
        ano_inaug = df_id$ano_inaug[i],
        is_start  = c(TRUE, FALSE), 
        X = c(p1[1], p2[1]),
        Y = c(p1[2], p2[2])
      )
    })
    todos_pts <- bind_rows(pts_list)
    
    todos_pts <- todos_pts |>
      mutate(Xr = round(X / snap_tol) * snap_tol, Yr = round(Y / snap_tol) * snap_tol)
    
    terminais <- todos_pts |>
      group_by(Xr, Yr) |>
      filter(n() == 1) |>
      ungroup()
    
    if (nrow(terminais) < 2) return(data.frame())
    
    ano_raiz <- min(terminais$ano_inaug, na.rm = TRUE)
    candidatos_origem <- terminais |> filter(ano_inaug == ano_raiz)
    origem <- candidatos_origem |> arrange(desc(is_start)) |> slice(1)
    destinos <- terminais |> filter(!(Xr == origem$Xr & Yr == origem$Yr))
    
    if (nrow(destinos) == 0) return(data.frame())
    
    pares <- destinos |>
      mutate(
        X_orig = origem$X, Y_orig = origem$Y, ano_orig = origem$ano_inaug,
        X_dest = X, Y_dest = Y, ano_dest = ano_inaug,
        par_idx = row_number(), n_pares = n()
      ) |>
      select(cod_part_dest = cod_part, ano_orig, ano_dest, par_idx, n_pares, 
             X_orig, Y_orig, X_dest, Y_dest)
    
    return(pares)
  }) |> ungroup()

od_pairs <- od_pairs |>
  mutate(dist_km = sqrt((X_orig - X_dest)^2 + (Y_orig - Y_dest)^2) / 1000) |>
  filter(dist_km >= 5)

cat(sprintf("\nIDs válidos: %d  |  Rotas Raiz-Ponta geradas: %d\n\n",
            n_distinct(od_pairs$id), nrow(od_pairs)))

# ==============================================================================
# 4. FUNÇÃO DE SNAPPING OTIMIZADA PARA NAs
# ==============================================================================
snap_to_local_land <- function(pt, local_raster) {
  val <- tryCatch(terra::extract(local_raster, terra::vect(pt))[[2]], error = function(e) NA)
  if (!is.na(val) && val > 0) return(pt)
  
  # CORREÇÃO: Pega apenas os pixels válidos (terra firme) com na.rm = TRUE
  land_pts <- terra::as.points(local_raster, na.rm = TRUE)
  if (length(land_pts) == 0) return(NULL)
  
  dists   <- terra::distance(terra::vect(pt), land_pts)
  nearest <- st_as_sf(land_pts[which.min(dists)])
  st_geometry(pt) <- st_geometry(st_transform(nearest, st_crs(pt)))
  return(pt)
}

# ==============================================================================
# 5. CÁLCULO DAS ROTAS LCP (COM DIAGNÓSTICO DE ERRO)
# ==============================================================================
cat(sprintf("Iniciando cálculo de %d rotas LCP...\n\n", nrow(od_pairs)))
lcp_list <- list()

for (i in seq_len(nrow(od_pairs))) {
  par       <- od_pairs[i, ]
  nome_rota <- sprintf("%s [Ramal %d/%d - %d]", par$Nome, par$par_idx, par$n_pares, par$ano_dest)
  
  cat(sprintf("Rota [%d/%d] — %s: ", i, nrow(od_pairs), nome_rota))
  
  pt_start_raw <- st_sf(
    id = par$id, Nome = par$Nome, cod_part = par$cod_part_dest, 
    ano_dest = par$ano_dest, geometry = st_sfc(st_point(c(par$X_orig, par$Y_orig)), crs = crs_ferrovias)
  ) |> st_transform(target_crs_raster)
  
  pt_end_raw <- st_sf(
    id = par$id, Nome = par$Nome, cod_part = par$cod_part_dest, 
    ano_dest = par$ano_dest, geometry = st_sfc(st_point(c(par$X_dest, par$Y_dest)), crs = crs_ferrovias)
  ) |> st_transform(target_crs_raster)
  
  pts_union      <- st_union(pt_start_raw, pt_end_raw)
  route_envelope <- st_buffer(pts_union, dist = 130000)
  
  local_cond <- tryCatch({
    cropped <- terra::crop(condutancia_mascarada, terra::vect(route_envelope))
    terra::extend(cropped, 5) # Estende a borda com NA
  }, error = function(e) NULL)
  
  if (is.null(local_cond)) { cat("Falha no recorte da janela local.\n"); next }
  
  pt_start <- snap_to_local_land(pt_start_raw, local_cond)
  pt_end   <- snap_to_local_land(pt_end_raw,   local_cond)
  
  if (is.null(pt_start) || is.null(pt_end)) { cat("Falha no Snapping para terra firme.\n"); next }
  
  # LIMPEZA DOS ATRIBUTOS: Extrair apenas a geometria para não bugar o leastcostpath
  p_origem_limpo  <- pt_start |> select(geometry)
  p_destino_limpo <- pt_end   |> select(geometry)
  
  path <- tryCatch({
    local_cs <- leastcostpath::create_cs(local_cond, neighbours = 16)
    leastcostpath::create_lcp(x = local_cs, origin = p_origem_limpo, destination = p_destino_limpo)
  }, error = function(e) {
    # SE FALHAR AGORA, ELE GRITA O ERRO!
    cat(sprintf("\n    [ERRO INTERNO LCP]: %s", e$message))
    return(NULL)
  })
  
  if (!is.null(path)) {
    path <- path |>
      mutate(
        id        = par$id,
        Nome      = par$Nome,
        cod_part  = par$cod_part_dest,
        ano_inaug = par$ano_dest, 
        tipo_rota = "LCP_OD_Raiz_Ponta"
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
  cat("⚠️ NENHUMA ROTA FOI GERADA. O algoritmo LCP não encontrou caminhos válidos.\n")
} else {
  instrumento_final <- do.call(rbind, lcp_list)
  write_sf(instrumento_final, output_gpkg, delete_layer = TRUE)
  cat(sprintf("🎉 Conclusão! %d rotas salvas em:\n   %s\n",
              nrow(instrumento_final), output_gpkg))
}