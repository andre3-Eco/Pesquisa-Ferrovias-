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
ferrovias_gpkg  <- paste0(data.wd, "/05-geometrias/ferrovias_cronologicas.gpkg")
amcs_gpkg       <- paste0(data.wd, "/05-geometrias/ferrovias_cronologicas.gpkg")
output_gpkg     <- paste0(data.wd, "/05-geometrias/Rotas_LCP_OD_Real.gpkg")

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

amcs_nordeste <- amcs_geometria
  
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
# Lógica: todas as linhas com mesmo `id` formam uma ferrovia completa.
# `cod_part` marca as partes/entroncamentos — não devem ser usados como pontas.
# Os terminais verdadeiros são os pontos que aparecem como início ou fim de
# exatamente UM segmento (grau 1 na rede), identificados com tolerância de 50 m.
# ==============================================================================
cat("Lendo ferrovias e identificando terminais verdadeiros por ID...\n")
ferrovias_reais <- st_read(ferrovias_gpkg, quiet = TRUE)
crs_ferrovias   <- st_crs(ferrovias_reais)
snap_tol        <- 50  # metros — tolerância para fundir coordenadas de entroncamentos

od_pairs <- ferrovias_reais |>
  arrange(id, cod_part) |>
  group_by(id) |>
  group_map(function(df_id, key) {

    # Extrai primeiro e último vértice de cada segmento (MULTILINESTRING → pontos)
    pts_list <- lapply(seq_len(nrow(df_id)), function(i) {
      coords <- st_coordinates(st_cast(st_geometry(df_id[i, ]), "POINT"))[, 1:2]
      rbind(coords[1, ], coords[nrow(coords), ])
    })
    todos <- as.data.frame(do.call(rbind, pts_list))
    names(todos) <- c("X", "Y")

    # Agrupa pontos próximos numa grade de snap_tol metros
    todos$Xr <- round(todos$X / snap_tol) * snap_tol
    todos$Yr <- round(todos$Y / snap_tol) * snap_tol

    # Terminais = células da grade visitadas exatamente 1 vez (não são entroncamentos)
    terminais <- todos |>
      dplyr::count(Xr, Yr) |>
      dplyr::filter(n == 1) |>
      # Recupera coordenadas originais do primeiro ponto que caiu nessa célula
      dplyr::left_join(
        todos |> dplyr::distinct(Xr, Yr, .keep_all = TRUE) |> dplyr::select(Xr, Yr, X, Y),
        by = c("Xr", "Yr")
      )

    n_term <- nrow(terminais)
    if (n_term < 2) {
      cat(sprintf("  [id=%d %s] Apenas %d terminal — ignorado.\n",
                  key$id[1], df_id$Nome[1], n_term))
      return(NULL)
    }

    # Cria um par O-D para cada combinação de terminais (C(n,2))
    combos <- combn(n_term, 2, simplify = FALSE)
    pares  <- lapply(seq_along(combos), function(k) {
      idx <- combos[[k]]
      data.frame(
        id        = key$id[1],
        Nome      = df_id$Nome[1],
        ano_inaug = min(df_id$ano_inaug, na.rm = TRUE),
        par_idx   = k,
        n_pares   = length(combos),
        X_orig    = terminais$X[idx[1]],
        Y_orig    = terminais$Y[idx[1]],
        X_dest    = terminais$X[idx[2]],
        Y_dest    = terminais$Y[idx[2]],
        stringsAsFactors = FALSE
      )
    })
    do.call(rbind, pares)
  }) |>
  dplyr::bind_rows()

# Filtra pares com distância < 5 km (evita rotas degeneradas)
od_pairs <- od_pairs |>
  dplyr::mutate(
    dist_km = sqrt((X_orig - X_dest)^2 + (Y_orig - Y_dest)^2) / 1000
  ) |>
  dplyr::filter(dist_km >= 5)

cat(sprintf("IDs carregados: %d  |  Pares O-D gerados: %d  |  Válidos (≥5 km): %d\n\n",
            n_distinct(ferrovias_reais$id), nrow(od_pairs) + sum(od_pairs$dist_km < 5),
            nrow(od_pairs)))

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
# Itera sobre od_pairs: cada linha é um par O-D derivado dos terminais reais.
# ==============================================================================
cat(sprintf("Iniciando cálculo de %d rotas LCP...\n\n", nrow(od_pairs)))

lcp_list <- list()

for (i in seq_len(nrow(od_pairs))) {
  par       <- od_pairs[i, ]
  nome_rota <- sprintf("%s [par %d/%d]", par$Nome, par$par_idx, par$n_pares)

  cat(sprintf("Rota [%d/%d] — %s: ", i, nrow(od_pairs), nome_rota))

  # Constrói sf points em UTM (CRS da ferrovia → CRS do raster)
  pt_start_raw <- st_sf(
    id        = par$id,
    Nome      = par$Nome,
    ano_inaug = par$ano_inaug,
    geometry  = st_sfc(st_point(c(par$X_orig, par$Y_orig)), crs = crs_ferrovias)
  ) |> st_transform(target_crs_raster)

  pt_end_raw <- st_sf(
    id        = par$id,
    Nome      = par$Nome,
    ano_inaug = par$ano_inaug,
    geometry  = st_sfc(st_point(c(par$X_dest, par$Y_dest)), crs = crs_ferrovias)
  ) |> st_transform(target_crs_raster)

  # Janela móvel (bounding box dos dois pontos + buffer 130 km)
  pts_union      <- st_union(pt_start_raw, pt_end_raw)
  route_envelope <- st_buffer(pts_union, dist = 130000)

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
        id        = par$id,
        Nome      = par$Nome,
        par_idx   = par$par_idx,
        ano_inaug = par$ano_inaug,
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
