# ==============================================================================
# Etapa 02
# MODELAGEM DE CUSTO FERROVIÁRIO - SÉCULO XIX (BITOLA MÉTRICA)
# Abordagem: Física de Tração e Fricção Exponencial (OTIMIZADO)
# ==============================================================================

# CLEAN ENVIRONMENT
rm(list=ls()) # Limpa todo o ambiente para evitar gargalos de memória
gc()          # Força a coleta de lixo da memória RAM

# LOAD PACKAGES
if (!require("terra")) install.packages("terra")
library(terra)

# ==============================================================================
# 1. OTIMIZAÇÃO DE MEMÓRIA E DIRETÓRIOS
# ==============================================================================
# Definir diretórios (Ajuste os caminhos conforme sua máquina)
input_dem <- "alt_nordeste_completo_COP30_30m.tif"
output_cost <- "cost_raster_ferrovias_ne_1880_1920_90m.tif"

# Cria pasta temporária para cálculos intermediários geridos pelo próprio 'terra'
dir.create("tmp_rasters", showWarnings = FALSE)
terraOptions(tempdir = "tmp_rasters", memfrac = 0.8)

# ==============================================================================
# 2. CARREGAMENTO E SIMULAÇÃO DE TERRAPLENAGEM (AGREGAÇÃO)
# ==============================================================================
dem_30m <- rast(input_dem)

# Agrega de 30m para 90m (Fator 3). 
# Não gravamos em disco aqui. O 'terra' mantém como referência.
dem_90m <- aggregate(dem_30m, fact = 3, fun = mean)

# ==============================================================================
# 3. CÁLCULO DE DECLIVIDADE (% DE RAMPA)
# ==============================================================================
# Operações vetorizadas e "lazy": só serão de facto calculadas na gravação final
slope_rad <- terrain(dem_90m, v = "slope", unit = "radians")

# Converter radianos para porcentagem (Rampa % = tan(rad) * 100)
slope_pct <- tan(slope_rad) * 100

# ==============================================================================
# 4. FUNÇÃO DE CUSTO FÍSICA E EXPONENCIAL (ÁLGEBRA DE RASTERS)
# =============================================================================

# VARIÁVEIS DO PROJETO HISTÓRICO
rampa_maxima <- 1.8 # Limite crítico por lei/técnica (1,8%) para bitola métrica

# OTIMIZAÇÃO: Em vez de app() e uma função personalizada em R, usamos
# Álgebra de Rasters direta. Isso roda nativamente no motor C++ do 'terra',
# sendo ordens de magnitude mais rápido e eficiente no uso de CPU/RAM.

# Calcula o custo base (Fixo + Equação de Davis + Exponencial)
cost_base <- 1 + (20 * slope_pct) + (slope_pct^6)

# Aplica a barreira computacional para áreas inviáveis (> 1.8%)
# ifel() é a versão altamente otimizada do ifelse para o pacote terra
cost_final <- ifel(slope_pct > rampa_maxima, 999999, cost_base)

# ==============================================================================
# 5. EXECUÇÃO E GRAVAÇÃO
# ==============================================================================


# É neste momento que o 'terra' resolve toda a árvore de operações matematicas
# lendo o TIFF original por blocos, aplicando os cálculos em memória e gravando.
writeRaster(cost_final, 
            filename = output_cost,
            overwrite = TRUE,
            wopt = list(gdal = c("COMPRESS=LZW"))) # Gravação compactada

cat("Processamento concluído. O raster de custo otimizado foi salvo em:\n")
cat(output_cost, "\n")


# 1. Carregar o raster gerado
cost_raster <- rast("cost_raster_ferrovias_ne_1880_1920_90m.tif")

# 2. TRATAMENTO CRÍTICO PARA ESCALA DE CORES
# Transforma temporariamente o custo proibitivo (999999) em NA (dados ausentes) 
# apenas para a visualização. Isso permite que a paleta de cores se distribua 
# corretamente pelas áreas viáveis (de 1 até o custo máximo antes da barreira).
vis_raster <- ifel(cost_raster == 999999, NA, cost_raster)

# 3. PLOTAGEM OTIMIZADA
# O argumento 'maxcell' é vital aqui. Ele faz uma amostragem (downsample) na hora
# de desenhar na tela, evitando que sua interface gráfica congele.
plot(vis_raster, 
     main = "Matriz de Custo Ferroviário\n(Áreas em branco = Rampas > 1.8%)", 
     col = hcl.colors(100, palette = "Lajolla"), # Paleta perceptualmente uniforme
     maxcell = 5e5, # Limita a renderização a 500.000 pixels
     axes = FALSE,
     box = FALSE)

