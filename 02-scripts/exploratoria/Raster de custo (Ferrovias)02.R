# ==============================================================================
# CONFIGURAÇÃO E LIMPEZA DO AMBIENTE
# ==============================================================================
rm(list = setdiff(ls(), c("data.wd", "output.wd")))

# Carregar apenas o pacote essencial para grandes rasters (terra)
if (!require("terra")) install.packages("terra")
library(terra)

# Definir caminhos

data.wd <- getwd() 
dem_path <- paste0(data.wd, "\alt_nordeste_completo_COP30_30m.tif")
output_dir <- paste0(data.wd)

# Garantir que o diretório exista
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# ==============================================================================
# 1. CARREGAMENTO E AGREGAÇÃO (Simulação de Terraplenagem)
# ==============================================================================
cat("Carregando DEM e aplicando agregação para 90m...\n")

# Ler o raster original
elev_raw <- rast("alt_nordeste_completo_COP30_30m.tif")

# Agregação: Fator 3 (30m * 3 = 90m)
# Isso filtra micro-obstáculos e obriga o modelo a considerar patamares reais
elev_agg <- aggregate(elev_raw, fact = 3, fun = "mean", na.rm = TRUE)

# Salvar intermediário
writeRaster(
  elev_agg, 
  filename = paste0(output_dir, "elev_90m.tif"), 
  overwrite = TRUE, 
  gdal = c("COMPRESS=LZW", "PREDICTOR=2") # A correção está aqui
)

# ==============================================================================
# 2. CÁLCULO DE DECLIVIDADE E DEFINIÇÃO DE BARREIRAS
# ==============================================================================
cat("Calculando declividade e aplicando limite crítico (1.8%)...\n")

# Calcular inclinação em graus
slope_deg <- terrain(elev_agg, v = "slope", unit = "degrees")

# Converter para porcentagem
slope_pct <- tan(slope_deg * pi / 180) * 100

# Criar máscara de barreiras físicas (Limite Histórico: 1.8%)
# Qualquer célula acima disso é intransitável para locomotivas a vapor da época
max_gradient <- 1.8 
barrier_mask <- slope_pct > max_gradient

# ==============================================================================
# 3. MODELAGEM DE CUSTO BASEADA EM FÍSICA 
# ==============================================================================
cat("Gerando matriz de custo com fricção exponencial e anisotropia...\n")

# Preparar rasters auxiliares para resolução espacial (metros)
# Resolução aproximada em graus (ajuste fino baseado na latitude média seria ideal, 
# mas usaremos uma aproximação robusta para a região Nordeste ~ -10 a -15 lat)
lat_mean <- -12 
earth_radius <- 6371000
deg_to_rad <- pi / 180

# Tamanho do pixel em metros (aproximado para o centro da área)
cell_size_m <- res(elev_agg)[1] * deg_to_rad * earth_radius * cos(lat_mean * deg_to_rad)

# Calcular diferença vertical potencial por célula (para um passo de 1 célula)
# Nota: Para anisotropia real em 'gdistance', precisaríamos de uma função de transição.
# Aqui criamos um Raster de Custo Estático que penaliza severamente a subida 
# e moderadamente a descida íngreme, simulando a resistência média direcional.

# Função de Custo Personalizada:
# Custo Base = 1 (terreno plano)
# Se Subida: Custo = exp(k * slope_pct) -> Penalidade exponencial brutal
# Se Descida Suave (< 1.8%): Custo reduzido ligeiramente (eficiência gravitacional)
# Se Descida Íngreme (perto do limite): Aumento de custo (risco de frenagem/compressão)

# Parâmetros da Equação Adaptada (Simulando Davis + Fator de Segurança)
exp_power <- 8 # Potência alta para criar a "parede" computacional
base_friction <- 1.0

# Inicializar raster de custo
cost_raster <- elev_agg
values(cost_raster) <- base_friction

# Extrair valores de inclinação para cálculo vetorializado (mais rápido que loop)
s_vals <- values(slope_pct)
c_vals <- values(cost_raster)

# Lógica Vetorializada:
# 1. Aplicar Barreira Infinita
c_vals[barrier_mask[]] <- Inf

# 2. Calcular penalidade para células transitáveis
valid_idx <- !is.infinite(c_vals) & !is.na(s_vals)

if (any(valid_idx)) {
  s_valid <- s_vals[valid_idx]
  
  # Modelo Híbrido Anisotrópico Simplificado para Raster Estático:
  # Assumimos que o trem encontrará trechos de subida e descida.
  # A subida domina o consumo energético (Lei de Davis: Resistência Gravitacional).
  # A descida íngreme aumenta o risco operacional (freios).
  
  # Componente de Subida (Dominante): exp(slope^8)
  uphill_penalty <- exp((s_valid / 10)^exp_power) 
  
  # Componente de Descida/Risco: Se inclinação > 1%, adiciona fator de segurança linear
  # (Simula a dificuldade de controlar o trem em descidas longas)
  risk_factor <- ifelse(s_valid > 1.0, 1 + (s_valid * 0.5), 1)
  
  # Custo Final da Célula
  c_vals[valid_idx] <- base_friction * uphill_penalty * risk_factor
}

# Reatribuir valores ao raster
values(cost_raster) <- c_vals

# Tratamento de NA (áreas sem dados) como barreiras também
cost_raster[is.na(cost_raster)] <- Inf

# ==============================================================================
# 4. OTIMIZAÇÃO DE MEMÓRIA E EXPORTAÇÃO
# ==============================================================================
cat("Salvando matrizes de custo otimizadas no disco...\n")

# Nome do arquivo de saída
cost_file <- paste0(output_dir, "friction_railway_exponential_90m.tif")

# Escrever no disco com compressão LZW para economizar espaço e I/O
writeRaster(
  cost_raster, 
  filename = cost_file, 
  overwrite = TRUE, 
  datatype = "FLT4S", 
  # Removido 'compression = "lzw"' daqui
  gdal = c("COMPRESS=LZW", "PREDICTOR=2", "BIGTIFF=YES") 
)

cat("Processamento concluído.\n")
cat("Arquivo de atrito gerado:", cost_file, "\n")
cat("Resolução efetiva: 90m | Limite Máximo de Inclinação: 1.8%\n")
cat("Próximo passo: Utilizar este raster como input na função 'shortestPath' do pacote terra ou gdistance.\n")

# Limpeza explícita de objetos grandes para liberar RAM antes do próximo passo
rm(elev_raw, elev_agg, slope_deg, slope_pct, cost_raster, barrier_mask)
gc()


plot(cost_raster, 
     main = "Matriz de Custo Ferroviário (Fricção Exponencial)",
     col = terrain.colors(100), # Cores de terreno (verde=baixo custo, marrom/vermelho=alto custo)
     box = FALSE)


