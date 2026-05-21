# ==============================================================================
# CRIAR BASE DE DENSIDADE DE FERROVIAS POR AMC
# Saída: base_densidade_ferrovias.csv
# ==============================================================================
# Esta base contém medidas de densidade (comprimento de ferrovia) em cada AMC:
#   - densidade_sintetica: km de ferrovia sintética por 1000 km² de área
#   - densidade_real_YYYY: km de ferrovia real (acumulada até YYYY) por 1000 km²
#   - comprimento_sintetico: km de ferrovia sintética (absoluto)
#   - comprimento_real_YYYY: km de ferrovia real (absoluto)
# ==============================================================================
#   - densidade_real_YYYY: km de ferrovia real (acumulada até YYYY) por 1000 km²
#   - comprimento_sintetico: km de ferrovia sintética (absoluto)
#   - comprimento_real_YYYY: km de ferrovia real (absoluto)
# ==============================================================================

# 1. PACOTES E CONFIGURAÇÕES ---------------------------------------------------
library(sf)
library(tidyverse)
library(geobr)

cat("========================================================================\n")
cat("CRIANDO BASE DE DENSIDADE DE FERROVIAS POR AMC\n")
cat("========================================================================\n\n")

if (!exists("data.wd")) data.wd <- getwd()

sf_use_s2(FALSE)

# 2. CARREGAMENTO DE DADOS GEOESPACIAIS ----------------------------------------
cat("Etapa 1: Carregando dados geoespaciais...\n\n")

## 2a. AMCs do Nordeste
cat("  → Baixando AMCs (1970-2010) do IPEA...\n")
amcs_70_10 <- read_comparable_areas(start_year = 1970, end_year = 2010)

amcs_nordeste <- amcs_70_10 |>
  filter(substr(list_code_muni_2010, 1, 1) == "2") |>
  distinct(code_amc, .keep_all = TRUE)

cat(sprintf("    ✓ %d AMCs do Nordeste carregadas\n\n", nrow(amcs_nordeste)))

## 2b. Ferrovias Reais (cronológicas)
cat("  → Carregando ferrovias reais cronológicas...\n")
ferrovias_reais <- st_read(
  paste0(data.wd, "/05-geometrias/ferrovias_cronologicas.gpkg"),
  quiet = TRUE
)

cat(sprintf("    ✓ %d segmentos de ferrovias reais carregados\n\n", nrow(ferrovias_reais)))

## 2c. Ferrovias Sintéticas
cat("  → Carregando rede sintética (LCP sem mar)...\n")
ferrovias_sinteticas <- st_read(
  paste0(data.wd, "/05-geometrias/Rotas_LCP_OD_Real.gpkg"),
  quiet = TRUE
)

cat(sprintf("    ✓ %d rotas sintéticas carregadas\n\n", nrow(ferrovias_sinteticas)))

# 3. PADRONIZAÇÃO DE PROJEÇÃO -------------------------------------------------
cat("Etapa 2: Padronizando projeção (UTM 24S - EPSG 31984)...\n\n")

crs_projeto <- 31984

amcs_ne_utm      <- st_transform(amcs_nordeste, crs = crs_projeto)
ferro_reais_utm  <- st_transform(ferrovias_reais, crs = crs_projeto)
ferro_sintet_utm <- st_transform(ferrovias_sinteticas, crs = crs_projeto)

cat("  ✓ Todas as camadas projetadas para UTM 24S\n\n")

# 4. CÁLCULO DE ÁREA DAS AMCs -------------------------------------------------
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

# 5. COMPRIMENTO DE FERROVIA SINTÉTICA POR AMC --------------------------------
cat("Etapa 4: Calculando comprimento de ferrovia sintética por AMC...\n\n")

# Inicializa coluna
amcs_ne_utm$comprimento_sintetico_km <- 0

# Para cada AMC, encontra quantos km de ferrovia sintética passam por ela
for(i in 1:nrow(amcs_ne_utm)) {
  if (i %% 50 == 0) cat(sprintf("  Processando AMC %d/%d...\n", i, nrow(amcs_ne_utm)))
  
  amc <- amcs_ne_utm[i, ]
  
  # Encontra intersecção com ferrovias sintéticas
  interseccao <- st_intersection(ferro_sintet_utm, amc)
  
  # Calcula o comprimento total
  if (nrow(interseccao) > 0) {
    comprimento_total <- st_length(interseccao) |>
      units::set_units(km) |>
      sum() |>
      as.numeric()
    
    amcs_ne_utm$comprimento_sintetico_km[i] <- comprimento_total
  }
}

cat(sprintf("  ✓ Comprimento de ferrovia sintética calculado\n"))
cat(sprintf("    Média: %.2f km | Mediana: %.2f km | Max: %.2f km\n\n",
            mean(amcs_ne_utm$comprimento_sintetico_km),
            median(amcs_ne_utm$comprimento_sintetico_km),
            max(amcs_ne_utm$comprimento_sintetico_km)))

# Densidade normalizada (por 1000 km² de área)
amcs_ne_utm$densidade_sintetica <- (amcs_ne_utm$comprimento_sintetico_km / amcs_ne_utm$area_km2) * 1000

cat(sprintf("  ✓ Densidade sintética calculada (por 1000 km²)\n"))
cat(sprintf("    Média: %.2f km | Mediana: %.2f km | Max: %.2f km\n\n",
            mean(amcs_ne_utm$densidade_sintetica),
            median(amcs_ne_utm$densidade_sintetica),
            max(amcs_ne_utm$densidade_sintetica)))

# 6. COMPRIMENTO CRONOLÓGICO DE FERROVIA REAL POR AMC -------------------------
cat("Etapa 5: Calculando comprimento cronológico de ferrovia real por AMC...\n\n")

# Identifica anos únicos
anos_disponiveis <- sort(unique(na.omit(ferro_reais_utm$ano_inaug)))

cat(sprintf("  Processando %d períodos...\n\n", length(anos_disponiveis)))

for(j in seq_along(anos_disponiveis)) {
  ano <- anos_disponiveis[j]
  
  # Inicializa coluna para este ano
  col_comp_name <- paste0("comprimento_real_", ano)
  col_dens_name <- paste0("densidade_real_", ano)
  
  amcs_ne_utm[[col_comp_name]] <- 0
  
  # Filtra ferrovias até este ano (inclusivo)
  ferrovia_ano <- ferro_reais_utm |>
    filter(ano_inaug <= ano)
  
  # Para cada AMC, calcula intersecção com ferrovias
  for(i in 1:nrow(amcs_ne_utm)) {
    amc <- amcs_ne_utm[i, ]
    
    # Intersecção
    interseccao <- st_intersection(ferrovia_ano, amc)
    
    # Comprimento
    if (nrow(interseccao) > 0) {
      comprimento_total <- st_length(interseccao) |>
        units::set_units(km) |>
        sum() |>
        as.numeric()
      
      amcs_ne_utm[[col_comp_name]][i] <- comprimento_total
    }
  }
  
  # Calcula densidade para este ano
  amcs_ne_utm[[col_dens_name]] <- (amcs_ne_utm[[col_comp_name]] / amcs_ne_utm$area_km2) * 1000
  
  # Feedback
  if (j %% 10 == 0 || j == length(anos_disponiveis)) {
    cat(sprintf("  ✓ Ano %d (%d/%d): densidade calculada\n", ano, j, length(anos_disponiveis)))
  }
}

cat("\n  ✓ Todas as densidades cronológicas calculadas\n\n")

# 7. PREPARAÇÃO DA BASE FINAL -------------------------------------------------
cat("Etapa 6: Preparando base de dados final...\n\n")

base_densidade <- amcs_ne_utm |>
  st_drop_geometry() |>
  select(
    code_amc,
    area_km2,
    comprimento_sintetico_km,
    densidade_sintetica,
    starts_with("comprimento_real_"),
    starts_with("densidade_real_")
  ) |>
  as.data.frame()

# Reordenar colunas
cols_comp_real <- grep("^comprimento_real_", names(base_densidade), value = TRUE) |> sort()
cols_dens_real <- grep("^densidade_real_", names(base_densidade), value = TRUE) |> sort()

base_densidade <- base_densidade |>
  select(
    code_amc,
    area_km2,
    comprimento_sintetico_km,
    densidade_sintetica,
    all_of(cols_comp_real),
    all_of(cols_dens_real)
  )

cat(sprintf("  ✓ Base final contém:\n"))
cat(sprintf("    - %d AMCs\n", nrow(base_densidade)))
cat(sprintf("    - %d colunas\n", ncol(base_densidade)))
cat(sprintf("    - 1 conjunto sintético + %d períodos reais\n", length(anos_disponiveis)))
cat(sprintf("    - Medidas em comprimento absoluto (km) e densidade (km/1000km²)\n\n"))

# 8. ESTATÍSTICAS DESCRITIVAS -------------------------------------------------
cat("Etapa 7: Computando estatísticas descritivas...\n\n")

cat("EVOLUÇÃO DA DENSIDADE (km de ferrovia por 1000 km² de AMC):\n")
cat("Ano\t| Média\t| Mediana\t| Máximo\n")
cat(strrep("-", 50), "\n")

for(ano in anos_disponiveis[c(1, seq(10, length(anos_disponiveis), 10))]) {
  col_name <- paste0("densidade_real_", ano)
  if (col_name %in% names(base_densidade)) {
    media <- mean(base_densidade[[col_name]], na.rm = TRUE)
    mediana <- median(base_densidade[[col_name]], na.rm = TRUE)
    maximo <- max(base_densidade[[col_name]], na.rm = TRUE)
    cat(sprintf("%d\t| %.2f\t| %.2f\t| %.2f\n", ano, media, mediana, maximo))
  }
}

cat("\n")

# 9. VERIFICAÇÃO DE DADOS AUSENTES -------------------------------------------
cat("Etapa 8: Verificando integridade dos dados...\n\n")

missing_count <- base_densidade |>
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

# 10. EXPORTAÇÃO ---------------------------------------------------------------
cat("Etapa 9: Exportando base de dados...\n\n")

output_file <- paste0(data.wd, "/01-dados/processados/base_densidade_ferrovias.csv")
write_csv(base_densidade, output_file)
cat(sprintf("  ✓ Arquivo salvo: %s\n\n", basename(output_file)))

# Versão compacta com apenas densidades (para análises principais), Não inclui os comprimentos absolutos das ferrovias
base_dens_only <- base_densidade |>
  select(code_amc, area_km2, densidade_sintetica, starts_with("densidade_real_"))

output_dens_only <- paste0(data.wd, "/01-dados/processados/base_densidade_simplificada.csv")
write_csv(base_dens_only, output_dens_only)
cat(sprintf("  ✓ Base simplificada (só densidades): %s\n\n", basename(output_dens_only)))

