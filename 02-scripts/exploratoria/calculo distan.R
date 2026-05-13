# ==============================================================================
#Cálculo de Distância das AMCs (Nordeste) para Ferrovias Reais e Sintéticas
# ==============================================================================

# 1. Instalação e carregamento dos pacotes necessários -----------------------
# install.packages(c("sf", "tidyverse", "geobr", "units"))

library(sf)
library(tidyverse)
library(geobr)
library(ggplot2)

# 2. Extração das AMCs (1970-2010) e Filtro para o Nordeste ------------------
cat("Baixando Áreas Mínimas Comparáveis (1970-2010) do IPEA...\n")
amcs_70_10 <- read_comparable_areas(start_year = 1970, end_year = 2010)

cat("Filtrando AMCs para a região Nordeste...\n")

amcs_nordeste <- amcs_70_10 %>% 
  filter(substr(list_code_muni_2010, 1, 1) == "2")

# 3. Importação dos dados das Ferrovias --------------------------------------
cat("Carregando as malhas ferroviárias reais e sintéticas...\n")

caminho_real      <- "Dados pesquisa (Ferrovias)/ferrovias_cronologicas.gpkg"
caminho_sintetica <- "Dados pesquisa (Ferrovias)/Rotas_Aleatorias_LCP_Sinteticas.gpkg"

ferrovias_reais      <- st_read(caminho_real, quiet = TRUE)
ferrovias_sinteticas <- st_read(caminho_sintetica, quiet = TRUE)

# 4. Padronização da Projeção Espacial (UTM 24S - EPSG 31984) ----------------
cat("Projetando bases para SIRGAS 2000 / UTM zone 24S...\n")
crs_projeto <- 31984

amcs_ne_utm      <- st_transform(amcs_nordeste, crs = crs_projeto)
ferro_reais_utm  <- st_transform(ferrovias_reais, crs = crs_projeto)
ferro_sintet_utm <- st_transform(ferrovias_sinteticas, crs = crs_projeto)

# 5. Geração de Centróides das AMCs ------------------------------------------
cat("Gerando centróides das AMCs...\n")
amc_pontos <- st_centroid(amcs_ne_utm)

# 6. Cálculo da Distância para a Rede Sintética (Variável Instrumental) ------

cat("Calculando distância estática para a rede sintética (Instrumento)...\n")
malha_sintet_unida <- st_union(ferro_sintet_utm)

distancias_sintet <- st_distance(amc_pontos, malha_sintet_unida)
# Converte a matriz de distância (metros) para vetor numérico em km
amc_pontos$dist_rail_sintetica_km <- as.numeric(distancias_sintet) / 1000

# 7. Cálculo da Distância Evolutiva para a Rede Real (Painel) ----------------
cat("Calculando distâncias cronológicas para a rede real...\n")
# Identifica os anos únicos de inauguração, ignorando possíveis NAs
anos_disponiveis <- sort(unique(na.omit(ferro_reais_utm$ano_inaug)))

for(ano in anos_disponiveis) {
  # Filtra a malha existente ATÉ aquele ano específico
  ferrovia_sub <- ferro_reais_utm %>% filter(ano_inaug <= ano)
  
  # Nomeia a coluna de forma sistemática
  col_name <- paste0("dist_rail_real_", ano)
  
  # O uso do st_union aqui unifica a geometria do ano, acelerando a busca do vizinho mais próximo
  distancias_ano <- st_distance(amc_pontos, st_union(ferrovia_sub))
  
  # Salva em km
  amc_pontos[[col_name]] <- as.numeric(distancias_ano) / 1000
  
  message(paste("Distâncias calculadas para a malha até o ano:", ano))
}

# 8. Geração de Mapa de Validação (Opcional) ---------------------------------
cat("Gerando mapa de validação visual...\n")
mapa_validacao <- ggplot() +
  geom_sf(data = amcs_ne_utm, fill = "gray95", color = "gray80", linewidth = 0.1) +
  geom_sf(data = ferro_reais_utm, color = "#2b6cb0", linewidth = 0.6, alpha = 0.8) +
  geom_sf(data = ferro_sintet_utm, color = "#e53e3e", linewidth = 0.6, linetype = "dashed") +
  labs(title = "Infraestrutura Ferroviária Histórica vs Sintética (AMCs Nordeste)",
       subtitle = "Azul: Real | Vermelho Tracejado: Sintética (LCP)",
       caption = "Fonte: Elaboração própria com dados do IPEA (geobr)") +
  theme_minimal()

print(mapa_validacao)

# 9. Exportação da Base de Dados Final ---------------------------------------
cat("Exportando base de dados...\n")
base_final <- amc_pontos %>% st_drop_geometry()
write_csv(base_final, "base_distancias_amcs_nordeste_1970.csv")

cat("Sucesso! O arquivo 'base_distancias_amcs_nordeste_1970.csv' foi gerado.\n")