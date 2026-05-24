# ==============================================================================
# GERAÇÃO DE MAPAS HISTÓRICOS: REDE REAL VS REDE SINTÉTICA (LCP)
# ==============================================================================

library(sf)
library(dplyr)
library(ggplot2)
# install.packages("ggspatial") # Opcional, para barra de escala e rosa dos ventos

sf_use_s2(FALSE)
if (!exists("data.wd")) data.wd <- getwd()

cat(strrep("=", 80), "\n")
cat("GERANDO SÉRIE HISTÓRICA DE MAPAS (REAL VS SINTÉTICO)\n")
cat(strrep("=", 80), "\n\n")

# ==============================================================================
# 1. CARREGAMENTO E PREPARAÇÃO DOS DADOS
# ==============================================================================
cat("Etapa 1: Carregando e padronizando geometrias...\n")

# Carregar redes (usando os arquivos base originais)
ferrovias_reais <- st_read(paste0(data.wd, "/05-geometrias/ferrovias_cronologicas.gpkg"), quiet = TRUE)
ferrovias_sinteticas <- st_read(paste0(data.wd, "/05-geometrias/Rotas_LCP_OD_Real.gpkg"), quiet = TRUE)

# Projetar tudo para o mesmo CRS (UTM 24S é bom para o Nordeste, ou SIRGAS 2000 geográfico)
crs_mapa <- 4674 # SIRGAS 2000 (Geográfico)
ferro_real_proj <- st_transform(ferrovias_reais, crs_mapa)
ferro_sint_proj <- st_transform(ferrovias_sinteticas, crs_mapa)

# Preparar o mapa de fundo (Background)
# Dissolver as AMCs para criar apenas a "silhueta" do Nordeste e não poluir o mapa
if(exists("amcs_geometria")) {
  fundo_nordeste <- amcs_geometria |> 
    st_transform(crs_mapa) |> 
    st_union() |> 
    st_make_valid()
} else {
  library(geobr)
  fundo_nordeste <- read_region(year = 2010, showProgress = FALSE) |> 
    filter(name_region == "Nordeste") |> 
    st_transform(crs_mapa)
}

# ==============================================================================
# 2. CONFIGURAÇÃO DOS CORTES TEMPORAIS
# ==============================================================================
# Escolha os anos que deseja transformar em mapa (ex: a cada 20 anos)
anos_mapa <- c(1880, 1900, 1920, 1940, 1970, 2000)

cat(sprintf("Etapa 2: Gerando %d mapas históricos...\n\n", length(anos_mapa)))

dir.create(paste0(data.wd, "/03-resultados/mapas"), showWarnings = FALSE, recursive = TRUE)

# ==============================================================================
# 3. LOOP DE RENDERIZAÇÃO DOS MAPAS
# ==============================================================================
for (ano in anos_mapa) {
  
  cat(sprintf("Renderizando mapa do ano %d...\n", ano))
  
  # Filtrar as redes cumulativamente até o ano especificado
  real_ano <- ferro_real_proj |> filter(ano_inaug <= ano)
  sint_ano <- ferro_sint_proj |> filter(ano_inaug <= ano)
  
  # Criar o mapa com ggplot2
  p <- ggplot() +
    # Camada 1: Fundo do Nordeste
    geom_sf(data = fundo_nordeste, fill = "gray95", color = "gray60", size = 0.3) +
    
    # Camada 2: Rede Sintética (LCP) - Linha tracejada vermelha
    geom_sf(data = sint_ano, aes(color = "Sintética (Instrumento)"), 
            linetype = "dashed", linewidth = 0.8, alpha = 0.7) +
    
    # Camada 3: Rede Real - Linha sólida azul (plotada por cima)
    geom_sf(data = real_ano, aes(color = "Real (Tratamento)"), 
            linewidth = 1) +
    
    # Customização de Cores e Legenda
    scale_color_manual(
      name = "Rede Ferroviária",
      values = c("Real (Tratamento)" = "#1f78b4", "Sintética (Instrumento)" = "#e31a1c")
    ) +
    
    # Estética do Título e Fundo
    labs(
      title = sprintf("Expansão Ferroviária no Nordeste até %d", ano),
      subtitle = "Comparação entre o traçado real e a linha de menor custo (LCP)",
      caption = "Elaboração própria."
    ) +
    theme_void() + # Remove eixos com coordenadas lat/lon
    theme(
      plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
      plot.subtitle = element_text(size = 12, hjust = 0.5, color = "gray30"),
      legend.position = "bottom",
      legend.title = element_text(face = "bold"),
      plot.margin = margin(10, 10, 10, 10)
    )
  
  # Adicionar barra de escala e norte (Descomente se tiver instalado o ggspatial)
  # p <- p + 
  #   ggspatial::annotation_scale(location = "bl", width_hint = 0.2) +
  #   ggspatial::annotation_north_arrow(location = "tr", which_north = "true", 
  #                                     style = ggspatial::north_arrow_minimal())
  
  # Salvar em alta resolução (300 DPI) para artigos
  caminho_mapa <- sprintf("%s/03-resultados/mapas/Evolucao_Rede_%d.png", data.wd, ano)
  ggsave(filename = caminho_mapa, plot = p, width = 8, height = 8, dpi = 300, bg = "white")
}

cat("\n✓ Processo concluído! Os mapas foram salvos na pasta '03-resultados/mapas'.\n")