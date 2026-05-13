# ==============================================================================
# CÁLCULO DA VARIÁVEL INSTRUMENTAL (LCP) 
# Uso do pacote 'leastcostpath' com Janela Móvel 
# ==============================================================================

# 1. AMBIENTE E PACOTES
rm(list = setdiff(ls(), "data.wd"))
gc()

libraries <- c("tidyverse", "sf", "terra", "leastcostpath")

# Rotina crítica: Verifica e instala pacotes ausentes automaticamente
pacotes_ausentes <- libraries[!(libraries %in% installed.packages()[,"Package"])]
if(length(pacotes_ausentes) > 0) {
  cat("Instalando pacotes ausentes:", paste(pacotes_ausentes, collapse = ", "), "\n")
  install.packages(pacotes_ausentes, dependencies = TRUE)
}

invisible(lapply(libraries, require, character.only = TRUE))

if (!exists("data.wd")) data.wd <- getwd()
input_cost_file <- paste0(data.wd, "/cost_raster_ferrovias_ne_1880_1920_90m.tif")
points_file <- paste0(data.wd, "/hubs_lcp_nordeste.csv")
output_gpkg <- paste0(data.wd, "/Variavel_Instrumental_LCP_Ferroviario.gpkg")

# ==============================================================================
# 2. PREPARAÇÃO DO RASTER (TERRA)
# ==============================================================================
cat("Lendo raster nativamente...\n")
cost_raster_terra <- rast(input_cost_file)

if (is.na(crs(cost_raster_terra)) || crs(cost_raster_terra) == "") {
  crs(cost_raster_terra) <- "EPSG:31983"
}

target_crs_raster <- st_crs(cost_raster_terra)



cat("Ajustando resolução para eficiência térmica (Fator 3 = ~270m)...\n")
cost_raster_opt <- terra::aggregate(cost_raster_terra, fact = 3, fun = "mean", na.rm = TRUE)

cat("Aplicando muro de barreira matemática...\n")
max_cost_value <- 9999999
cost_raster_opt <- terra::ifel(
  is.na(cost_raster_opt) | is.infinite(cost_raster_opt), 
  max_cost_value, 
  cost_raster_opt
)

# ==============================================================================
# 3. RASTER DE CONDUTÂNCIA (BASE PARA O GRAFO)
# ==============================================================================
cat("Gerando Raster de Condutância base...\n")
condutancia_base <- terra::ifel(cost_raster_opt > 0, 1 / cost_raster_opt, 0)

# ==============================================================================
# 4. TRATAMENTO DOS PONTOS
# ==============================================================================
cat("Processando hubs ferroviários...\n")
points_df <- read_csv(points_file, show_col_types = FALSE) %>% 
  filter(!is.na(lon_destino) & !is.na(lat_destino))

# Lógica condicional de CRS
points_df <- points_df %>%
  mutate(
    epsg_origem = case_when(
      abs(lon_origem) > 180 & lon_origem > 600000 & abbrev_state %in% c("RN", "CE", "PB", "PI") ~ 31984,
      abs(lon_origem) > 180 ~ 31983,
      TRUE ~ 4326
    )
  )

create_sf_mixed_crs <- function(df, lon_col, lat_col, epsg_col) {
  df_split <- split(df, df[[epsg_col]])
  sf_list <- lapply(names(df_split), function(epsg) {
    st_as_sf(df_split[[epsg]], coords = c(lon_col, lat_col), crs = as.numeric(epsg)) %>%
      st_transform(target_crs_raster)
  })
  do.call(rbind, sf_list) %>% arrange(id) 
}

pts_origem_sf <- create_sf_mixed_crs(points_df, "lon_origem", "lat_origem", "epsg_origem")
pts_destino_sf <- st_as_sf(points_df, coords = c("lon_destino", "lat_destino"), crs = 4326) %>%
  st_transform(target_crs_raster)

# ==============================================================================
# 5. CÁLCULO DAS ROTAS LCP (ARQUITETURA DE JANELA MÓVEL)
# ==============================================================================
cat(sprintf("Iniciando algoritmo LCP para %d rotas (Grafo Dinâmico Seguro)...\n", nrow(points_df)))

lcp_list <- list()

for (i in 1:nrow(points_df)) {
  pt_start <- pts_origem_sf[i, ]
  pt_end <- pts_destino_sf[i, ]
  
  cat(sprintf("\nRota [%d/%d]: ", i, nrow(points_df)))
  
  # ---------------------------------------------------------
  # CORREDOR DE RECORTE (BOUNDING BOX)
  # ---------------------------------------------------------
  # Cria um polígono juntando origem e destino e adiciona um buffer de 100km.
  # Isso permite que a rota desvie de serras, mas impede o R de tentar 
  # memorizar o Nordeste inteiro atoa.
  pts_union <- st_union(pt_start, pt_end)
  route_envelope <- st_buffer(pts_union, dist = 100000) # 100.000 metros
  
  # Recorta o raster APENAS para esse envelope
  local_condutancia <- tryCatch({
    terra::crop(condutancia_base, route_envelope)
  }, error = function(e) NULL)
  
  if (is.null(local_condutancia)) {
    cat("Falha no recorte do raster (Pontos fora do mapa?). Pulando.\n")
    next
  }
  
  # ---------------------------------------------------------
  # CRIAÇÃO DO GRAFO E ROTA 
  # ---------------------------------------------------------
  path <- tryCatch({
    # Agora a função roda super leve, apenas para o corredor recortado
    local_cs <- leastcostpath::create_cs(local_condutancia, neighbours = 16)
    
    leastcostpath::create_lcp(
      x = local_cs, 
      origin = pt_start, 
      destination = pt_end
    )
  }, error = function(e) {
    cat(sprintf("Erro no LCP: %s ", e$message))
    return(NULL)
  })
  
  if (!is.null(path)) {
    path <- path %>%
      mutate(
        id = pts_origem_sf$id[i],
        nome_ferrovia = pts_origem_sf$Nome[i],
        ano_inaug = pts_origem_sf$ano_inaug[i],
        estado = pts_origem_sf$abbrev_state[i]
      )
    lcp_list[[i]] <- path
    cat("✅ Sucesso!")
  }
}

# ==============================================================================
# 6. EXPORTAÇÃO
# ==============================================================================
if (length(lcp_list) == 0) {
  cat("\n⚠️ NENHUMA ROTA FOI GERADA. Verifique os dados espaciais.\n")
} else {
  instrumento_final <- do.call(rbind, lcp_list)
  write_sf(instrumento_final, output_gpkg, delete_layer = TRUE)
  cat(sprintf("\n🎉 Conclusão! %d rotas salvas em %s.\n", nrow(instrumento_final), output_gpkg))
}




