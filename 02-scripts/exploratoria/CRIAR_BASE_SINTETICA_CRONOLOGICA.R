# ==============================================================================
# CRIAR BASE DE VARIÁVEIS SINTÉTICAS CRONOLÓGICAS
# Baseado nos scripts: 
#   1_Criar_Base_Distancias.R
#   2_Criar_Base_Dummy_Atendimento.R  
#   3_Criar_Base_Densidade_Ferrovias.R
# 
# Mas processando APENAS a rede sintética (Rotas_LCP_OD_Real.gpkg)
# e gerando variáveis POR ANO de inauguração (acumuladas)
# ==============================================================================

library(sf)
library(tidyverse)
library(geobr)

cat("========================================================================\n")
cat("CRIANDO BASE DE VARIÁVEIS SINTÉTICAS CRONOLÓGICAS\n")
cat("(Processando apenas rede sintética com variáveis por ano)\n")
cat("========================================================================\n\n")

if (!exists("data.wd")) data.wd <- getwd()

sf_use_s2(FALSE)

# 1. CARREGAMENTO DE DADOS ---------------------------------------------------
cat("Etapa 1: Carregando dados geoespaciais...\n\n")

## 1a. AMCs do Nordeste (1970-2010)
cat("  → Baixando AMCs (1970-2010) do IPEA...\n")
amcs_70_10 <- read_comparable_areas(start_year = 1970, end_year = 2010)

amcs_nordeste <- amcs_70_10 |>
  filter(substr(list_code_muni_2010, 1, 1) == "2") |>
  distinct(code_amc, .keep_all = TRUE)

cat(sprintf("    ✓ %d AMCs do Nordeste carregadas\n\n", nrow(amcs_nordeste)))

## 1b. Ferrovias Sintéticas (LCP)
cat("  → Carregando rede sintética (LCP OD Real)...\n")
ferrovias_sinteticas <- st_read(
  paste0(data.wd, "/05-geometrias/Rotas_LCP_OD_Real.gpkg"),
  quiet = TRUE
)

cat(sprintf("    ✓ %d rotas sintéticas carregadas\n\n", nrow(ferrovias_sinteticas)))

# Verificar se tem coluna de ano
if (!"ano_inaug" %in% names(ferrovias_sinteticas)) {
  stop("ERRO: Coluna 'ano_inaug' não encontrada no GPKG sintético")
}

anos_disponiveis <- sort(unique(na.omit(ferrovias_sinteticas$ano_inaug)))
cat(sprintf("    Anos de inauguração disponíveis: %d a %d (%d anos únicos)\n\n", 
            min(anos_disponiveis), max(anos_disponiveis), length(anos_disponiveis)))

# 2. PADRONIZAÇÃO DE PROJEÇÃO ------------------------------------------------
cat("Etapa 2: Padronizando projeção (UTM 24S - EPSG 31984)...\n\n")

crs_projeto <- 31984

amcs_ne_utm      <- st_transform(amcs_nordeste, crs = crs_projeto)
ferro_sintet_utm <- st_transform(ferrovias_sinteticas, crs = crs_projeto)

cat("  ✓ Todas as camadas projetadas para UTM 24S\n\n")

# 3. CÁLCULO DE ÁREA DAS AMCs ------------------------------------------------
cat("Etapa 3: Calculando área de cada AMC...\n\n")

# Área em m² convertida para km²
amcs_ne_utm$area_km2 <- st_area(amcs_ne_utm) |>
  units::set_units(km^2) |>
  as.numeric()

cat(sprintf("  ✓ Áreas calculadas\n"))
cat(sprintf("    Média: %.0f km² | Mediana: %.0f km² | Max: %.0f km²\n\n",
            mean(amcs_ne_utm$area_km2),
            median(amcs_ne_utm$area_km2),
            max(amcs_ne_utm$area_km2)))

# 4. GERAÇÃO DE CENTRÓIDES DAS AMCs ------------------------------------------
cat("Etapa 4: Gerando centróides das AMCs...\n\n")

amc_pontos <- st_centroid(amcs_ne_utm)

cat(sprintf("  ✓ %d centróides criados\n\n", nrow(amc_pontos)))

# 5. PROCESSAMENTO CRONOLÓGICO PARA REDE SINTÉTICA --------------------------
cat("Etapa 5: Calculando variáveis sintéticas cronológicas...\n\n")

cat(sprintf("  Processando %d períodos cronológicos...\n\n", length(anos_disponiveis)))

# Lista para armazenar resultados por ano (mais eficiente que modificar in-place)
resultados_por_ano <- list()

for (idx in seq_along(anos_disponiveis)) {
  ano <- anos_disponiveis[idx]
  
  # Progress feedback
  if (idx %% 10 == 0 || idx == length(anos_disponiveis) || idx == 1) {
    cat(sprintf("  → Ano %d (%d/%d)...\n", ano, idx, length(anos_disponiveis)))
  }
  
  # Filtra ferrovias sintéticas até este ano (inclusivo)
  ferro_sintet_ano <- ferro_sintet_utm |>
    filter(ano_inaug <= ano)
  
  # ================================
  # 5.1 DISTÂNCIA ATÉ REDE SINTÉTICA
  # ================================
  malha_sintet_ano_unida <- st_union(ferro_sintet_ano)
  distancias_ano <- st_distance(amc_pontos, malha_sintet_ano_unida)
  distancias_ano_km <- as.numeric(distancias_ano) / 1000
  
  # ================================
  # 5.2 DUMMY DE ATENDIMENTO (≤ 25 km)
  # ================================
  dummy_ano <- as.integer(distancias_ano_km <= 25)
  
  # ================================
  # 5.3 MEDIDA CONTÍNUA (inversa da distância)
  # ================================
  cobertura_continua_ano <- 1 / (1 + distancias_ano_km)
  
  # ================================
  # 5.4 COMPRIMENTO DE FERROVIA SINTÉTICA POR AMC
  # ================================
  comprimento_ano <- numeric(nrow(amcs_ne_utm))
  
  # Para cada AMC, calcula quanto da rede sintética passa por ela
  for (i in 1:nrow(amcs_ne_utm)) {
    amc <- amcs_ne_utm[i, ]
    
    # Intersecção com ferrovias sintéticas até este ano
    interseccao <- st_intersection(ferro_sintet_ano, amc)
    
    if (nrow(interseccao) > 0) {
      comprimento_total <- st_length(interseccao) |>
        units::set_units(km) |>
        sum() |>
        as.numeric()
      
      comprimento_ano[i] <- comprimento_total
    }
    # Senão, permanece 0 (inicializado acima)
  }
  
  # ================================
  # 5.5 DENSIDADE (km por 1000 km²)
  # ================================
  densidade_ano <- (comprimento_ano / amcs_ne_utm$area_km2) * 1000
  
  # Armazena resultados deste ano
  resultados_por_ano[[as.character(ano)]] <- list(
    dist = distancias_ano_km,
    dummy = dummy_ano,
    cobertura = cobertura_continua_ano,
    comprimento = comprimento_ano,
    densidade = densidade_ano
  )
}

cat("\n  ✓ Todas as variáveis cronológicas calculadas\n\n")

# 6. PREPARAÇÃO DA BASE FINAL -----------------------------------------------
cat("Etapa 6: Preparando base de dados final...\n\n")

# Começa com informações básicas das AMCs
base_final <- amcs_ne_utm |>
  st_drop_geometry() |>
  select(code_amc, area_km2) |>
  as.data.frame()

# Adiciona as variáveis sintéticas cronológicas
for (ano in anos_disponiveis) {
  ano_char <- as.character(ano)
  
  base_final[[paste0("dist_rail_sintetica_", ano)]] <- 
    resultados_por_ano[[ano_char]]$dist
  
  base_final[[paste0("dummy_atendida_sintetica_", ano)]] <- 
    resultados_por_ano[[ano_char]]$dummy
    
  base_final[[paste0("cobertura_continua_sintetica_", ano)]] <- 
    resultados_por_ano[[ano_char]]$cobertura
    
  base_final[[paste0("comprimento_sintetico_", ano)]] <- 
    resultados_por_ano[[ano_char]]$comprimento
    
  base_final[[paste0("densidade_sintetica_", ano)]] <- 
    resultados_por_ano[[ano_char]]$densidade
}

# Reordenar colunas para melhor legibilidade
cols_dist <- sort(grep("^dist_rail_sintetica_", names(base_final), value = TRUE))
cols_dummy <- sort(grep("^dummy_atendida_sintetica_", names(base_final), value = TRUE))
cols_cob <- sort(grep("^cobertura_continua_sintetica_", names(base_final), value = TRUE))
cols_comp <- sort(grep("^comprimento_sintetico_", names(base_final), value = TRUE))
cols_dens <- sort(grep("^densidade_sintetica_", names(base_final), value = TRUE))

base_final <- base_final |>
  select(
    code_amc,
    area_km2,
    all_of(cols_dist),
    all_of(cols_dummy),
    all_of(cols_cob),
    all_of(cols_comp),
    all_of(cols_dens)
  )

cat(sprintf("  ✓ Base final contém:\n"))
cat(sprintf("    - %d AMCs\n", nrow(base_final)))
cat(sprintf("    - %d colunas total\n", ncol(base_final)))
cat(sprintf("    - %d anos processados (%d a %d)\n", 
            length(anos_disponiveis), min(anos_disponiveis), max(anos_disponiveis)))
cat(sprintf("    - 5 variáveis por ano: dist, dummy, cobertura, comprimento, densidade\n\n"))

# 7. VERIFICAÇÃO DE DADOS AUSENTES -----------------------------------------
cat("Etapa 7: Verificando integridade dos dados...\n\n")

missing_count <- base_final |>
  summarise(across(everything(), ~sum(is.na(.)))) |>
  pivot_longer(everything()) |>
  filter(value > 0)

if (nrow(missing_count) == 0) {
  cat("  ✓ Sem valores ausentes na base\n\n")
} else {
  cat("  ⚠ Valores ausentes detectados:\n")
  print(missing_count)
  cat("\n")
}

# 8. ESTATÍSTICAS DESCRITIVAS (últimos e primeiros anos) -------------------
cat("Etapa 8: Computando estatísticas descritivas...\n\n")

# Anos para mostrar no resumo (primeiros, últimos e alguns intermediários)
anos_para_mostrar <- unique(c(
  head(anos_disponiveis, 5),
  tail(anos_disponiveis, 5),
  anos_disponiveis[seq(1, length(anos_disponiveis), length.out = 10)]
))
anos_para_mostrar <- sort(anos_para_mostrar)

cat("EVOLUÇÃO DA DENSIDADE SINTÉTICA (km de ferrovia por 1000 km² de AMC):\n")
cat("Ano\t| Média\t| Mediana\t| Máximo\n")
cat(strrep("-", 50), "\n")

for (ano in anos_para_mostrar) {
  col_name <- paste0("densidade_sintetica_", ano)
  if (col_name %in% names(base_final)) {
    media <- mean(base_final[[col_name]], na.rm = TRUE)
    mediana <- median(base_final[[col_name]], na.rm = TRUE)
    maximo <- max(base_final[[col_name]], na.rm = TRUE)
    cat(sprintf("%d\t| %.2f\t| %.2f\t| %.2f\n", ano, media, mediana, maximo))
  }
}
cat("\n")

cat("EVOLUÇÃO DO DUMMY DE ATENDIMENTO SINTÉTICO (≤ 25 km):\n")
cat("Ano\t| AMCs Atendidas\t| % Atendidas\n")
cat(strrep("-", 45), "\n")

for (ano in anos_para_mostrar) {
  col_name <- paste0("dummy_atendida_sintetica_", ano)
  if (col_name %in% names(base_final)) {
    atendidas <- sum(base_final[[col_name]])
    pct <- 100 * mean(base_final[[col_name]])
    cat(sprintf("%d\t| %d\t\t| %.1f%%\n", ano, atendidas, pct))
  }
}
cat("\n")

# 9. EXPORTAÇÃO -------------------------------------------------------------
cat("Etapa 9: Exportando base de dados...\n\n")

output_file <- paste0(data.wd, "/01-dados/processados/base_sintetica_cronologica.csv")
write_csv(base_final, output_file)

cat(sprintf("  ✓ Arquivo salvo: %s\n", basename(output_file)))
cat(sprintf("    Localização completa: %s\n\n", output_file))

# Também salvar versão RDS para carregamento mais rápido
output_rds <- paste0(data.wd, "/01-dados/processados/base_sintetica_cronologica.rds")
saveRDS(base_final, output_rds)
cat(sprintf("  ✓ Versão RDS salva: %s\n\n", basename(output_rds)))

# 10. RESUMO FINAL ----------------------------------------------------------
cat("========================================\n")
cat("   PROCESSO CONCLUÍDO\n")
cat("========================================\n")
cat(sprintf("AMCs processadas: %d\n", nrow(base_final)))
cat(sprintf("Anos de inauguração: %d a %d (%d anos)\n", 
            min(anos_disponiveis), max(anos_disponiveis), length(anos_disponiveis)))
cat(sprintf("Variáveis criadas: 5 × %d = %d colunas cronológicas\n", 
            length(anos_disponiveis), length(anos_disponiveis) * 5))
cat(sprintf("Total de colunas: %d (incluindo code_amc e area_km2)\n", ncol(base_final)))
cat(sprintf("\nArquivos gerados:\n"))
cat(sprintf("  - %s\n", basename(output_file)))
cat(sprintf("  - %s\n", basename(output_rds)))
cat(sprintf("\nPróximos passos:\n"))
