library(ggplot2)
library(sf)

# 1. PREPARAÇÃO (Garantindo que todos os objetos estejam no mesmo CRS)
# É crítico que todos compartilhem o mesmo sistema de referência (ex: SIRGAS 2000 / EPSG:4674)
target_crs <- st_crs(amcs_geometria)

ferrovias_reais <- st_read(ferrovias_gpkg, quiet = TRUE) |> st_transform(target_crs)
rotas_lcp       <- st_read(output_gpkg, quiet = TRUE) |> st_transform(target_crs)

# 2. PLOTAGEM DO MAPA
# Usamos a hierarquia visual: AMCs no fundo, Rotas LCP (sintéticas) ao meio, e Reais por cima
mapa_comparativo <- ggplot() +
  # Camada 1: Fundo (Municípios)
  geom_sf(data = amcs_geometria, fill = "gray95", color = "white", linewidth = 0.1) +
  
  # Camada 2: Rotas Sintéticas (LCP) - Linhas pontilhadas e mais finas
  geom_sf(data = rotas_lcp, color = "#e67e22", linewidth = 0.5, linetype = "dashed", alpha = 0.6) +
  
  # Camada 3: Ferrovia Real - Linha sólida, mais grossa e escura
  geom_sf(data = ferrovias_reais, color = "#2c3e50", linewidth = 0.8) +
  
  theme_minimal() +
  labs(
    title = "Comparação: Rede Ferroviária Real vs. Sintética (LCP)",
    subtitle = "Linhas escuras: Realidade | Linhas alaranjadas (tracejadas): LCP",
    caption = "Fonte: Elaboração própria baseada em ferrovias históricas."
  ) +
  theme(panel.grid = element_blank(), axis.text = element_blank())

# 3. EXIBIR E SALVAR
print(mapa_comparativo)
ggsave("03-resultados/mapas/Mapa_Comparativo_Real_Sintetica.png", mapa_comparativo, width = 10, height = 8, dpi = 300)


library(ggplot2)
library(sf)

# 1. Configuração do mapa
mapa_final <- ggplot() +
  # Camada 1: Municípios (Base) - Cor suave e bordas bem finas
  geom_sf(data = amcs_geometria, fill = "#f8f9fa", color = "#e9ecef", linewidth = 0.1) +
  
  # Camada 2: Rotas Sintéticas (LCP) - Destaque com tracejado e transparência
  geom_sf(data = rotas_lcp, aes(color = "Sintética (LCP)"), 
          linewidth = 0.4, linetype = "dashed", alpha = 0.5) +
  
  # Camada 3: Ferrovia Real - Linha sólida, cor forte e sem transparência
  geom_sf(data = ferrovias_reais, aes(color = "Real (Histórica)"), 
          linewidth = 0.8) +
  
  # 2. Definição precisa de cores e rótulos da legenda
  scale_color_manual(
    name = "Tipo de Rede",
    values = c("Sintética (LCP)" = "#e67e22", "Real (Histórica)" = "#2c3e50"),
    guide = guide_legend(override.aes = list(linewidth = 2, linetype = c("dashed", "solid")))
  ) +
  
  # 3. Estilo e Layout Profissional
  theme_void() + # Remove eixos, grid e fundos desnecessários
  labs(
    title = "Comparativo de Malha Ferroviária: Realidade vs. Modelo",
    subtitle = "Sobreposição das ferrovias históricas do NE com o menor custo de construção (LCP)",
    caption = "Fonte: Elaboração própria. Ferrovias Reais (Iphan/DNIT) | Modelo Sintético (LCP)"
  ) +
  theme(
    plot.title = element_text(face = "bold", size = 16, hjust = 0),
    plot.subtitle = element_text(size = 12, color = "gray40", margin = margin(b = 10)),
    legend.position = "bottom", # Legenda na parte inferior fica mais organizada
    legend.title = element_text(face = "bold"),
    plot.margin = margin(10, 10, 10, 10)
  )

# Exibir
print(mapa_final)

# Exportar com alta resolução
ggsave("03-resultados/mapas/Mapa_Comparativo_Final.png", 
       mapa_final, width = 10, height = 8, dpi = 300)




# Se você não tiver o ggspatial, instale: 
install.packages("ggspatial")
library(ggplot2)
library(sf)
library(ggspatial) # Essencial para escala e bússola

mapa_final_contraste <- ggplot() +
  # 1. Fundo do mar/ocean (maior contraste)
  theme(panel.background = element_rect(fill = "#d1e0ea")) + 
  
  # 2. Municípios (AMCs)
  geom_sf(data = amcs_geometria, fill = "white", color = "gray70", linewidth = 0.1) +
  
  # 3. Rotas Sintéticas (LCP)
  geom_sf(data = rotas_lcp, aes(color = "Sintética (LCP)"), 
          linewidth = 0.4, linetype = "dashed", alpha = 0.5) +
  
  # 4. Ferrovia Real
  geom_sf(data = ferrovias_reais, aes(color = "Real (Histórica)"), 
          linewidth = 0.8) +
  
  # 5. Escala e Bússola
  annotation_scale(location = "bl", width_hint = 0.2) + # Escala no canto inferior esquerdo
  annotation_north_arrow(location = "tl", which_north = "true", # Bússola no canto superior esquerdo
                         style = north_arrow_fancy_orienteering) +
  
  # 6. Estética e Cores
  scale_color_manual(
    name = "Tipo de Rede",
    values = c("Sintética (LCP)" = "#FF0000", "Real (Histórica)" = "#2c3e50"),
    guide = guide_legend(override.aes = list(linewidth = 1.5))
  ) +
  theme_void()  +
  theme(plot.title = element_text(face = "bold", size = 16),
        legend.position = "bottom")

# Exibir e salvar
print(mapa_final_contraste)
ggsave("03-resultados/mapas/Mapa_Final_Profissional.png", 
       mapa_final_contraste, width = 10, height = 8, dpi = 300)