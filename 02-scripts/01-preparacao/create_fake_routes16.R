# ==============================================================================
# Etapa 16 
# CRIAR ROTAS FALSAS ALEATÓRIAS (PLACEBO IN-SPACE RÍGIDO)
# Usa Monte Carlo para encontrar a melhor posição na terra[cite: 1].
# Aplica apenas translação (deslocamento lateral) preservando a geometria, 
# atributos (ano_inaug) e garantindo uma distância mínima para evitar spillovers[cite: 1].
# ==============================================================================

library(sf)
library(dplyr)
library(purrr)

if (!exists("data.wd")) {
  data.wd <- normalizePath(file.path(getwd(), "..", ".."))
}
setwd(data.wd)

sf_use_s2(FALSE)

# -------------------- 1. CARREGAR DADOS --------------------
crs_projeto <- 31984

amcs_ne <- readRDS("01-dados/processados/amcs_geometria.rds") %>% 
  st_transform(crs_projeto)
borda_ne <- st_union(amcs_ne)

# Base bruta (contém as colunas 'ano_inaug' e todas as outras)[cite: 1]
sint_orig_bruta <- st_read("05-geometrias/Rotas_LCP_OD_Real.gpkg", quiet = TRUE) %>%
  st_transform(crs_projeto)

# Batedor (Scout): Base unificada apenas para teste de colisão com o oceano[cite: 1]
batedor <- st_sf(geometry = st_sfc(st_union(sint_orig_bruta)), crs = crs_projeto)
comprimento_real <- as.numeric(st_length(batedor))

# -------------------- 2. ALGORITMO DE BUSCA (MONTE CARLO) --------------------

set.seed(123) 
max_tentativas <- 500
tolerancia_terra <- 0.98 

# Parâmetros de deslocamento (em metros, assumindo CRS 31984 que é SIRGAS 2000 / UTM)
distancia_minima <- 50000  # Pelo menos 50 km de distância da original
distancia_maxima <- 250000 # No máximo 250 km de distância

tentativa <- 1
melhor_pct_terra <- 0

# Variáveis para guardar o dx e dy vencedores
melhor_dx <- NULL
melhor_dy <- NULL

while (tentativa <= max_tentativas) {
  # Sorteia uma distância e um ângulo de direção para o "pulo"
  dist_pulo <- runif(1, min = distancia_minima, max = distancia_maxima)
  angulo_pulo <- runif(1, min = 0, max = 2 * pi)
  
  # Calcula o vetor de translação pura (dx, dy)
  dx <- dist_pulo * cos(angulo_pulo)
  dy <- dist_pulo * sin(angulo_pulo)
  
  # Aplica o deslocamento rígido no batedor
  geom_transladada <- st_geometry(batedor) + c(dx, dy)
  geom_teste <- st_sfc(geom_transladada, crs = crs_projeto)
  
  # Testa colisão com a terra[cite: 1]
  intersecao_terra <- st_intersection(geom_teste, borda_ne)
  
  if (length(intersecao_terra) > 0) {
    pct_terra <- as.numeric(st_length(intersecao_terra)) / comprimento_real
    
    if (pct_terra > melhor_pct_terra) {
      melhor_pct_terra <- pct_terra
      melhor_dx <- dx
      melhor_dy <- dy
    }
    
    if (pct_terra >= tolerancia_terra) {
      cat(sprintf("   ✓ Posição encontrada! (%.1f%% na terra na tentativa %d)\n", 
                  pct_terra * 100, tentativa))
      break
    }
  }
  tentativa <- tentativa + 1
}

if (tentativa > max_tentativas) {
  cat(sprintf("   ! Limite atingido. Usando melhor posição encontrada (%.1f%% na terra)[cite: 1].\n", 
              melhor_pct_terra * 100))
}

# -------------------- 3. APLICAR TRANSFORMAÇÃO NA BASE BRUTA --------------------

# Extrair todas as geometrias individuais (com seus respectivos anos)[cite: 1]
geoms_individuais <- st_geometry(sint_orig_bruta)

# Transladar todas de uma vez (apenas vetor direcional, sem rotação)
geoms_finais <- geoms_individuais + c(melhor_dx, melhor_dy)

# Recolocar as geometrias novas na base que tem as colunas originais![cite: 1]
sint_fake <- sint_orig_bruta
st_geometry(sint_fake) <- st_sfc(geoms_finais, crs = crs_projeto)

# -------------------- 4. SALVAR RESULTADO --------------------

arquivo_saida <- "05-geometrias/Rotas_LCP_Fake_Random.gpkg"
st_write(sint_fake, arquivo_saida, delete_layer = TRUE, quiet = TRUE)