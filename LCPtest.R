# ==============================================================================
# CÁLCULO DA VARIÁVEL INSTRUMENTAL (LCP) - ALTA PERFORMANCE
# ==============================================================================

# 1. AMBIENTE E PACOTES
rm(list = setdiff(ls(), "data.wd"))
gc()

libraries <- c("tidyverse", "sf", "terra", "gdistance")
invisible(lapply(libraries, require, character.only = TRUE))

if (!exists("data.wd")) data.wd <- getwd()
input_cost_file <- paste0(data.wd, "/cost_raster_ferrovias_ne_1880_1920_90m.tif")
points_file <- paste0(data.wd, "/hubs_lcp_nordeste.csv")
output_gpkg <- paste0(data.wd, "/Variavel_Instrumental_LCP_Ferroviario.gpkg")

# ==============================================================================
# 2. RASTER: OTIMIZAÇÃO NO MOTOR C++ (TERRA)
# ==============================================================================
cat("Lendo e otimizando o raster de custo no motor nativo...\n")
cost_raster_terra <- rast(input_cost_file)

# Garantia de CRS base
if (is.na(crs(cost_raster_terra)) || crs(cost_raster_terra) == "") {
  crs(cost_raster_terra) <- "EPSG:31983"
}

# Agregação de resolução (fator 3: 90m -> 270m) para caber na RAM
cost_raster_terra_opt <- terra::aggregate(cost_raster_terra, fact = 5, fun = "mean", na.rm = TRUE)

# Substituição VETORIZADA de barreiras (Inf/NA) ANTES de virar 'raster' legado
max_cost_value <- 1000000 
cost_raster_terra_opt <- terra::ifel(
  is.na(cost_raster_terra_opt) | is.infinite(cost_raster_terra_opt), 
  max_cost_value, 
  cost_raster_terra_opt
)

target_crs_raster <- st_crs(cost_raster_terra_opt)

# ==============================================================================
# 3. O HACK DA MATRIZ ESPARSA (GDISTANCE) - REDUÇÃO BRUTAL DE TEMPO
# ==============================================================================
cat("Convertendo para gdistance e calculando Matriz de Transição...\n")
cost_raster_gdist <- raster::raster(cost_raster_terra_opt)

# HACK DE PERFORMANCE CRÍTICA:
# Em vez de passar 'function(x) 1/mean(x)' (o que derruba o R para um cálculo iterativo lento),
# passamos 'mean' (que aciona o motor C++ interno) para criar a matriz de CUSTO.
cat("Criando matriz de base...\n")
transition_matrix <- gdistance::transition(
  cost_raster_gdist, 
  transitionFunction = mean, # Muito mais rápido do que função customizada
  directions = 16, 
  symm = TRUE
)

# Em seguida, invertemos diretamente os valores numéricos internos da Matriz Esparsa (Condutância)
# Custo vira Condutância (1/Custo) instantaneamente na memória RAM.
cat("Invertendo matriz esparsa (Custo -> Condutância)...\n")
transition_matrix@transitionMatrix@x <- 1 / transition_matrix@transitionMatrix@x

cat("Aplicando correção geográfica...\n")
transition_matrix <- gdistance::geoCorrection(transition_matrix, type = "c")


# ==============================================================================
# 4. VETORIZAÇÃO DOS PONTOS (FIM DO FOR LOOP ESPACIAL)
# ==============================================================================
cat("Processando tabela de hubs em lote (Vetorização)...\n")
points_df <- read_csv(points_file, show_col_types = FALSE) %>% 
  filter(!is.na(lon_destino) & !is.na(lat_destino))

# Lógica condicional de CRS processada na tabela inteira de uma vez
points_df <- points_df %>%
  mutate(
    # Se X for um número muito alto, está em metros (UTM). Avalia a Zona.
    # Caso contrário, assume que está em graus decimais (WGS84).
    epsg_origem = case_when(
      abs(lon_origem) > 180 & lon_origem > 600000 & abbrev_state %in% c("RN", "CE", "PB", "PI") ~ 31984,
      abs(lon_origem) > 180 ~ 31983,
      TRUE ~ 4326
    )
  )

# Função para criar pontos sf vetorizados lidando com CRS mistos
create_sf_mixed_crs <- function(df, lon_col, lat_col, epsg_col) {
  # Agrupa por CRS para transformar em lote em vez de ponto a ponto
  df_split <- split(df, df[[epsg_col]])
  
  sf_list <- lapply(names(df_split), function(epsg) {
    chunk <- df_split[[epsg]]
    st_as_sf(chunk, coords = c(lon_col, lat_col), crs = as.numeric(epsg)) %>%
      st_transform(target_crs_raster)
  })
  
  do.call(rbind, sf_list) %>% arrange(id) # Reordena para manter a sequência original
}

# Cria os sf de origem e destino todos de uma vez
cat("Reprojetando coordenadas de origem...\n")
pts_origem_sf <- create_sf_mixed_crs(points_df, "lon_origem", "lat_origem", "epsg_origem")

cat("Reprojetando coordenadas de destino...\n")
# Destino assumido sempre WGS84 conforme seu código original
pts_destino_sf <- st_as_sf(points_df, coords = c("lon_destino", "lat_destino"), crs = 4326) %>%
  st_transform(target_crs_raster)

# Extrair coordenadas brutas (Matriz bidimensional)
coords_origem <- st_coordinates(pts_origem_sf)
coords_destino <- st_coordinates(pts_destino_sf)

# ==============================================================================
# 5. SNAP TO LAND OTIMIZADO
# ==============================================================================
cat("Realizando Snap to Land vetorial...\n")
# Extrai os valores do raster para todos os pontos de uma vez
orig_vals <- terra::extract(cost_raster_terra_opt, coords_origem)[, 2]
dest_vals <- terra::extract(cost_raster_terra_opt, coords_destino)[, 2]

# Apenas os pontos que caíram em 'NA' precisarão do processo pesado de buffer
snap_to_land_optimized <- function(coords_matrix, invalid_idx, rst_terra) {
  for (i in invalid_idx) {
    pt_sf <- st_sfc(st_point(coords_matrix[i, ]), crs = target_crs_raster)
    buffer <- st_buffer(pt_sf, dist = 5000) 
    local_raster <- terra::crop(rst_terra, buffer, mask = FALSE)
    valid_cells <- terra::crds(local_raster, na.rm = TRUE)
    
    if (nrow(valid_cells) > 0) {
      dists <- sqrt((valid_cells[, 1] - coords_matrix[i, 1])^2 + (valid_cells[, 2] - coords_matrix[i, 2])^2)
      coords_matrix[i, ] <- valid_cells[which.min(dists), ]
    }
  }
  return(coords_matrix)
}

coords_origem <- snap_to_land_optimized(coords_origem, which(is.na(orig_vals)), cost_raster_terra_opt)
coords_destino <- snap_to_land_optimized(coords_destino, which(is.na(dest_vals)), cost_raster_terra_opt)

# ==============================================================================
# 6. CALCULO DE ROTAS (LCP)
# ==============================================================================
lcp_list <- list()
n_routes <- nrow(points_df)
cat(sprintf("Iniciando algoritmo de caminho para %d rotas...\n", n_routes))

# O loop agora faz apenas matemática de rede, sem lidar com geometria ou projeção
for (i in 1:n_routes) {
  start_xy <- coords_origem[i, ]
  end_xy <- coords_destino[i, ]
  
  if (any(is.na(start_xy)) || any(is.na(end_xy))) next
  
  path <- tryCatch({
    gdistance::shortestPath(transition_matrix, start_xy, end_xy, output = "SpatialLines")
  }, error = function(e) NULL)
  
  if (!is.null(path) && length(path) > 0) {
    path_sf <- st_as_sf(path) %>%
      mutate(
        id = pts_origem_sf$id[i],
        nome_ferrovia = pts_origem_sf$Nome[i],
        ano_inaug = pts_origem_sf$ano_inaug[i],
        estado = pts_origem_sf$abbrev_state[i]
      )
    lcp_list[[i]] <- path_sf
  }
}

# ==============================================================================
# 7. EXPORTAÇÃO
# ==============================================================================
if (length(lcp_list) == 0) {
  cat("\n⚠️ NENHUMA ROTA FOI GERADA.\n")
} else {
  instrumento_final <- do.call(rbind, lcp_list)
  st_crs(instrumento_final) <- target_crs_raster
  
  write_sf(instrumento_final, output_gpkg, delete_layer = TRUE)
  cat(sprintf("\n🎉 Conclusão! %d rotas salvas com sucesso em %s.\n", length(lcp_list), output_gpkg))
}