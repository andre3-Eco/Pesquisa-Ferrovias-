# ==============================================================================
# Etapa 16 
# CRIAR ROTAS FALSAS ALEATÓRIAS (PLACEBO IN-SPACE RÍGIDO)
# Usa Monte Carlo para encontrar a melhor posição na terra, mas aplica a 
# translação preservando todos os atributos originais (ano_inaug, etc.).
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

# Base bruta (contém as colunas 'ano_inaug' e todas as outras)
sint_orig_bruta <- st_read("05-geometrias/Rotas_LCP_OD_Real.gpkg", quiet = TRUE) %>%
  st_transform(crs_projeto)

# Batedor (Scout): Base unificada apenas para teste de colisão com o oceano
batedor <- st_sf(geometry = st_sfc(st_union(sint_orig_bruta)), crs = crs_projeto)
comprimento_real <- as.numeric(st_length(batedor))
centroide_atual <- st_coordinates(st_centroid(batedor))

# -------------------- 2. ALGORITMO DE BUSCA (MONTE CARLO) --------------------

set.seed(123) 
max_tentativas <- 500
tolerancia_terra <- 0.98 

tentativa <- 1
melhor_pct_terra <- 0

# Variáveis para guardar os parâmetros matemáticos do movimento vencedor
melhor_coord <- NULL
melhor_theta <- NULL

while (tentativa <= max_tentativas) {
  pt_origem <- st_sample(borda_ne, size = 1, type = "random")
  coord_origem <- st_coordinates(pt_origem)
  theta <- runif(1, min = 0, max = 2 * pi)
  
  dx <- coord_origem[1] - centroide_atual[1]
  dy <- coord_origem[2] - centroide_atual[2]
  geom_transladada <- st_geometry(batedor) + c(dx, dy)
  
  matriz_rotacao <- matrix(c(cos(theta), sin(theta), 
                             -sin(theta), cos(theta)), 
                           nrow = 2, ncol = 2)
  geom_rotacionada <- (geom_transladada - coord_origem) * matriz_rotacao + coord_origem
  geom_teste <- st_sfc(geom_rotacionada, crs = crs_projeto)
  
  intersecao_terra <- st_intersection(geom_teste, borda_ne)
  
  if (length(intersecao_terra) > 0) {
    pct_terra <- as.numeric(st_length(intersecao_terra)) / comprimento_real
    
    if (pct_terra > melhor_pct_terra) {
      melhor_pct_terra <- pct_terra
      melhor_coord <- coord_origem
      melhor_theta <- theta
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
  cat(sprintf("   ! Limite atingido. Usando melhor posição encontrada (%.1f%% na terra).\n", 
              melhor_pct_terra * 100))
}

# -------------------- 3. APLICAR TRANSFORMAÇÃO NA BASE BRUTA --------------------

# Recuperar o dx e dy exatos da melhor tentativa
dx_final <- melhor_coord[1] - centroide_atual[1]
dy_final <- melhor_coord[2] - centroide_atual[2]

# Recriar matriz de rotação vencedora
matriz_final <- matrix(c(cos(melhor_theta), sin(melhor_theta), 
                         -sin(melhor_theta), cos(melhor_theta)), 
                       nrow = 2, ncol = 2)

# Extrair todas as geometrias individuais (com seus respectivos anos)
geoms_individuais <- st_geometry(sint_orig_bruta)

# Transladar e rotacionar todas de uma vez (operação vetorial hiper-rápida)
geoms_transladadas <- geoms_individuais + c(dx_final, dy_final)
geoms_finais <- (geoms_transladadas - melhor_coord) * matriz_final + melhor_coord

# Recolocar as geometrias novas na base que tem as colunas originais!
sint_fake <- sint_orig_bruta
st_geometry(sint_fake) <- st_sfc(geoms_finais, crs = crs_projeto)

# -------------------- 4. SALVAR RESULTADO --------------------

arquivo_saida <- "05-geometrias/Rotas_LCP_Fake_Random.gpkg"
st_write(sint_fake, arquivo_saida, delete_layer = TRUE, quiet = TRUE)
