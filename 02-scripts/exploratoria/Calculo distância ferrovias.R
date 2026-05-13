install.packages('sf')
install.packages('tidyverse')
install.packages("geobr")

library(sf)
library(tidyverse)
library(geobr)
library(ggplot2)
library(dplyr)
library(stringr)

"C:/Users/André Elias/Downloads/ferrovias_cronologicas.gpkg"
# Baixar as Áreas Mínimas Comparáveis para o período 1970-2010
amcs_00_10 <- read_comparable_areas(start_year = 1900, end_year = 2010)

# Filtrar Nordeste 
amcs_nordeste <- amcs_00_10[substr(amcs_00_10$list_code_muni_2010, 1, 1) == "2", ]

# 1. Carregar os dados 
ferrovias <- st_read("C:/Users/André Elias/Downloads/ferrovias_cronologicas.gpkg")

# 2. Padronizar Projeção (UTM 24S - EPSG 31984)
crs_projeto <- 31984
ferrovias_utm <- st_transform(ferrovias, crs = crs_projeto)
amcs_ne_utm <- st_transform(amcs_nordeste, crs = crs_projeto)

# Criar o Mapa com ggplot2
# O segredo é usar várias camadas geom_sf()
mapa_validacao <- ggplot() +
  # Camada 1: Polígonos das AMCs (Fundo)
  geom_sf(data = amcs_ne_utm, 
          fill = "gray95", 
          color = "gray80", 
          size = 0.1) +
  # Camada 2: Linhas das Ferrovias (Destaque)
  geom_sf(data = ferrovias_utm, 
          color = "#2b6cb0", # Azul escuro acadêmico
          size = 0.6,
          alpha = 0.8) +
  # Configurações Estéticas
  labs(title = "Infraestrutura Ferroviária Histórica e AMCs (1900-2010)",
       subtitle = "Região Nordeste - Projeção SIRGAS 2000 / UTM zone 24S",
       caption = "Fonte: Elaboração própria com dados do IPEA (geobr) e digitalização histórica.") +
  theme_minimal() +
  theme(panel.grid = element_line(color = "gray90", linetype = "dashed"),
        plot.title = element_text(face = "bold", size = 14),
        axis.text = element_text(size = 8))

# Exibir o Mapa
print(mapa_validacao)

# Gerar Centróides 
amc_pontos <- st_centroid(amcs_ne_utm)

# 3. Identificar todos os anos únicos de inauguração 
anos_disponiveis <- sort(unique(ferrovias_utm$ano_inaug))

# 4. Loop para Cálculo de Distâncias por Ano
for(ano in anos_disponiveis) {
  # Filtrar a malha existente ATÉ aquele ano específico
  ferrovia_sub <- ferrovias_utm %>% filter(ano_inaug <= ano)
  
  # Nomear a coluna com o ano correspondente
  col_name <- paste0("dist_rail_", ano)
  
  # Calcular a distância mínima (em quilômetros)
  # st_distance gera a matriz, apply seleciona a menor distância para cada AMC
  distancias <- st_distance(amc_pontos, ferrovia_sub)
  amc_pontos[[col_name]] <- as.numeric(apply(distancias, 1, min)) / 1000
  
  message(paste("Processado: Ano", ano))
}

# 5. Exportação da Base de Dados de Painel
base_final_anual <- amc_pontos %>% st_drop_geometry()
write_csv(base_final_anual, "base_distancias_historicas_anual.csv")
