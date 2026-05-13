# ==============================================================================
# GERAÇÃO DE REDE FERROVIÁRIA SINTÉTICA (CONTRAFACTUAL LCP)
# Amostragem Aleatória Inteligente com Janela Móvel
# ==============================================================================

# 1. AMBIENTE E PACOTES
rm(list = ls())
gc()

libraries <- c("tidyverse", "sf", "terra", "leastcostpath")

pacotes_ausentes <- libraries[!(libraries %in% installed.packages()[,"Package"])]
if(length(pacotes_ausentes) > 0) {
  cat("Instalando pacotes ausentes...\n")
  install.packages(pacotes_ausentes, dependencies = TRUE)
}

invisible(lapply(libraries, require, character.only = TRUE))

# PARÂMETROS DA SIMULAÇÃO 
N_ORIGENS <- 10   # Quantidade de pontos de partida
N_DESTINOS <- 10  # Quantidade de destinos POR ponto de partida (Ex: 30x30 = 900 rotas)

output_gpkg <- "Rotas_Aleatorias_LCP_Sinteticas.gpkg"
input_cost_file <- "cost_raster_ferrovias_ne_1880_1920_90m.tif"

# ==============================================================================
# 2. PREPARAÇÃO DO RASTER (TERRA)
# ==============================================================================
cat("A preparar a matriz topográfica base...\n")
cost_raster_terra <- rast(input_cost_file)
if (is.na(crs(cost_raster_terra)) || crs(cost_raster_terra) == "") {
  crs(cost_raster_terra) <- "EPSG:31983"
}
target_crs_raster <- st_crs(cost_raster_terra)

# Agregamos para eficiência térmica (270m)
cost_raster_opt <- terra::aggregate(cost_raster_terra, fact = 3, fun = "mean", na.rm = TRUE)

max_cost_value <- 9999999
cost_raster_opt <- terra::ifel(
  is.na(cost_raster_opt) | is.infinite(cost_raster_opt), 
  max_cost_value, 
  cost_raster_opt
)

condutancia_base <- terra::ifel(cost_raster_opt < max_cost_value, 1 / cost_raster_opt, 0)

# ==============================================================================
# 3. AMOSTRAGEM ESPACIAL INTELIGENTE 
# ==============================================================================
cat("A sortear coordenadas viáveis (evitando mar e serras intransponíveis)...\n")

# Para garantir que temos pontos suficientes pós-filtragem, pedimos 5000 amostras
# O argumento 'cells=TRUE' permite-nos extrair diretamente onde estão
set.seed(42) # Semente fixada para reprodutibilidade científica
amostra_bruta <- spatSample(cost_raster_opt, size = 5000, method = "random", 
                            xy = TRUE, values = TRUE, na.rm = TRUE)

# Filtra: remove oceanos e células acima de 1.8% de inclinação (nosso muro)
# O nome da coluna gerada por values=TRUE normalmente é o nome da camada.
# Usamos a 3ª coluna que contém o valor do pixel.
amostra_viavel <- amostra_bruta[amostra_bruta[, 3] < max_cost_value, ]

if (nrow(amostra_viavel) < (N_ORIGENS + N_DESTINOS)) {
  stop("ERRO CRÍTICO: Não há pontos viáveis suficientes no mapa. Reduza a exigência.")
}

# Converte o pool de coordenadas em objetos espaciais (SF)
pool_sf <- st_as_sf(amostra_viavel, coords = c("x", "y"), crs = target_crs_raster)
pool_sf$id_ponto <- 1:nrow(pool_sf)

# Sorteia as Origens
origens_sf <- pool_sf[sample(1:nrow(pool_sf), N_ORIGENS), ]

# ==============================================================================
# 4. CÁLCULO MASSIVO DE ROTAS LCP (ARQUITETURA DE JANELA MÓVEL)
# ==============================================================================
total_rotas_estimadas <- N_ORIGENS * N_DESTINOS
cat(sprintf("\nIniciando simulação de ~%d rotas...\n", total_rotas_estimadas))
cat("AVISO: Dependendo do processador, isto pode demorar. Pode ir tomar um café.\n\n")

lcp_list <- list()
contador_sucesso <- 0

# LOOP EXTERNO: Origens
for (i in 1:nrow(origens_sf)) {
  pt_start <- origens_sf[i, ]
  
  # Sorteia os destinos para esta origem (garantindo que não sorteia o próprio ponto)
  pool_disponivel <- pool_sf[pool_sf$id_ponto != pt_start$id_ponto, ]
  destinos_sf <- pool_disponivel[sample(1:nrow(pool_disponivel), N_DESTINOS), ]
  
  # LOOP INTERNO: Destinos
  for (j in 1:nrow(destinos_sf)) {
    pt_end <- destinos_sf[j, ]
    
    # Progresso no console
    cat(sprintf("\rProcessando Origem [%d/%d] -> Destino [%d/%d] | Sucessos: %d", 
                i, N_ORIGENS, j, N_DESTINOS, contador_sucesso))
    
    # ---------------------------------------------------------
    # JANELA MÓVEL (BOUNDING BOX) 
    # ---------------------------------------------------------
    pts_union <- st_union(pt_start, pt_end)
    route_envelope <- st_buffer(pts_union, dist = 100000) # Buffer 100km
    
    local_condutancia <- tryCatch({
      terra::crop(condutancia_base, route_envelope)
    }, error = function(e) NULL)
    
    if (is.null(local_condutancia)) next # Falhou no recorte, pula
    
    # ---------------------------------------------------------
    # CRIAÇÃO DO GRAFO E DESENHO DA ROTA
    # ---------------------------------------------------------
    path <- tryCatch({
      local_cs <- leastcostpath::create_cs(local_condutancia, neighbours = 16)
      
      leastcostpath::create_lcp(
        x = local_cs, 
        origin = pt_start, 
        destination = pt_end
      )
    }, error = function(e) NULL) # Se der erro (obstáculo intransponível), retorna NULL
    
    if (!is.null(path)) {
      path <- path %>%
        mutate(
          id_origem = pt_start$id_ponto,
          id_destino = pt_end$id_ponto,
          tipo_rota = "Sintetica_Aleatoria"
        )
      
      # Guarda a rota e atualiza o contador
      contador_sucesso <- contador_sucesso + 1
      lcp_list[[contador_sucesso]] <- path
    }
  }
}

# ==============================================================================
# 5. EXPORTAÇÃO
# ==============================================================================
cat("\n\nEmpacotando resultados...\n")

if (length(lcp_list) == 0) {
  cat("⚠️ NENHUMA ROTA POSSÍVEL FOI GERADA.\n")
} else {
  instrumento_final <- do.call(rbind, lcp_list)
  write_sf(instrumento_final, output_gpkg, delete_layer = TRUE)
  cat(sprintf("🎉 SUCESSO! %d rotas sintéticas salvas em '%s'.\n", 
              nrow(instrumento_final), output_gpkg))
}