# ==============================================================================
# VISUALIZAÇÃO DO PLACEBO IN-SPACE (REDE RÍGIDA COM RESTRIÇÃO CONTINENTAL)
# Plota as rotas reais versus as rotas falsas otimizadas na terra
# ==============================================================================

library(sf)
library(ggplot2)
library(dplyr)

if (!exists("data.wd")) {
  data.wd <- normalizePath(file.path(getwd(), "..", ".."))
}
setwd(data.wd)

# -------------------- 1. CARREGAR DADOS --------------------
crs_projeto <- 31984

# Carrega a malha de municípios para o fundo do mapa
amcs_ne <- readRDS("01-dados/processados/amcs_geometria.rds") %>% 
  st_transform(crs_projeto)

# Cria um contorno externo (fronteira) do Nordeste para limpar a visualização
fronteira_ne <- st_union(amcs_ne)

# Carrega a Rede Real Original
ferrovias_reais <- st_read("05-geometrias/ferrovias_cronologicas.gpkg", quiet = TRUE) %>% 
  st_transform(crs_projeto)

# Carrega a Rede Falsificada (Placebo unificado e otimizado na terra)
ferrovias_fake <- st_read("05-geometrias/Rotas_LCP_Fake_Random.gpkg", quiet = TRUE) %>% 
  st_transform(crs_projeto)

# -------------------- 2. CONSTRUIR O MAPA --------------------

mapa_placebo <- ggplot() +
  # Camada 1: Fundo dos municípios (cinza muito claro)
  geom_sf(data = amcs_ne, fill = "#fcfcfc", color = "#eaeaea", linewidth = 0.1) +
  
  # Camada 2: Fronteira do Nordeste
  geom_sf(data = fronteira_ne, fill = NA, color = "black", linewidth = 0.5) +
  
  # Camada 3: Rotas Falsas (Placebo Continental) - Vermelho
  geom_sf(data = ferrovias_fake, aes(color = "Placebo (Terra)"), linewidth = 0.8, alpha = 0.8) +
  
  # Camada 4: Rotas Reais - Azul escuro
  geom_sf(data = ferrovias_reais, aes(color = "Real"), linewidth = 0.8) +
  
  # Estilização
  scale_color_manual(
    name = "Traçado Ferroviário:",
    values = c("Real" = "#08519c", "Placebo (Terra)" = "#cb181d")
  ) +
  
  # Tema
  theme_minimal() +
  labs(
    title = "Validação Espacial: Ferrovias Reais vs. Placebo Continental",
    subtitle = "Bloco rígido transladado com otimização (Monte Carlo) para evitar o oceano",
    x = "Longitude",
    y = "Latitude"
  ) +
  theme(
    legend.position = "bottom",
    legend.title = element_text(face = "bold"),
    legend.text = element_text(size = 10),
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(color = "grey40", size = 11),
    panel.grid.major = element_line(color = "gray90", linetype = "dashed"),
    panel.background = element_rect(fill = "#e0f3f8", color = NA) # Azul sutil para o mar
  )

# -------------------- 3. EXIBIR E EXPORTAR --------------------

print(mapa_placebo)

# Criação de diretório e salvamento
dir_graficos <- "03-resultados/graficos"
if (!dir.exists(dir_graficos)) dir.create(dir_graficos, recursive = TRUE)

arquivo_mapa <- paste0(dir_graficos, "/mapa_placebo_in_space_continental.png")
ggsave(arquivo_mapa, plot = mapa_placebo, width = 10, height = 10, dpi = 300, bg = "white")

cat(sprintf("✅ Mapa de validação gerado e salvo em:\n%s\n", arquivo_mapa))