# ==============================================================================
# CRIAR BASE DE DISTÂNCIAS DAS AMCs ATÉ FERROVIAS (REAL E SINTÉTICA)
# Saída: base_distancias_amcs_nordeste_semmar.csv
# ==============================================================================
# Esta base contém as distâncias de cada AMC até:
#   - Rede sintética (LCP): coluna estática dist_rail_sintetica_km
#   - Rede real cronológica: colunas dist_rail_real_YYYY para cada ano
# ==============================================================================
#   - Rede real cronológica: colunas dist_rail_real_YYYY para cada ano
# ==============================================================================

# 1. PACOTES E CONFIGURAÇÕES ---------------------------------------------------
library(sf)
library(tidyverse)
library(geobr)

cat("========================================================================\n")
cat("CRIANDO BASE DE DISTÂNCIAS: AMCs → Ferrovias (Real Cronológica + Sintética)\n")
cat("========================================================================\n\n")

if (!exists("data.wd")) data.wd <- getwd()

sf_use_s2(FALSE)

# 2. CARREGAMENTO DE DADOS GEOESPACIAIS ----------------------------------------
cat("Etapa 1: Carregando dados geoespaciais...\n\n")

## 2a. AMCs do Nordeste (1970-2010)
cat("  → Baixando AMCs (1970-2010) do IPEA...\n")
amcs_70_10 <- read_comparable_areas(start_year = 1970, end_year = 2010)

amcs_nordeste <- amcs_70_10 |>
  filter(substr(list_code_muni_2010, 1, 1) == "2")

cat(sprintf("    ✓ %d AMCs do Nordeste carregadas\n\n", nrow(amcs_nordeste)))

## 2b. Ferrovias Reais (cronológicas)
cat("  → Carregando ferrovias reais cronológicas...\n")
ferrovias_reais <- st_read(
  paste0(data.wd, "/Dados pesquisa (Ferrovias)/ferrovias_cronologicas.gpkg"),
  quiet = TRUE
)

cat(sprintf("    ✓ %d segmentos de ferrovias reais carregados\n\n", nrow(ferrovias_reais)))

## 2c. Ferrovias Sintéticas (LCP)
cat("  → Carregando rede sintética (LCP sem mar)...\n")
ferrovias_sinteticas <- st_read(
  paste0(data.wd, "/Dados pesquisa (Ferrovias)/Rotas_LCP_OD_Real_SemMar.gpkg"),
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

# 4. GERAÇÃO DE CENTRÓIDES DAS AMCs -------------------------------------------
cat("Etapa 3: Gerando centróides das AMCs...\n\n")

amc_pontos <- st_centroid(amcs_ne_utm)

cat(sprintf("  ✓ %d centróides criados\n\n", nrow(amc_pontos)))

# 5. DISTÂNCIA PARA REDE SINTÉTICA (VARIÁVEL INSTRUMENTAL) --------------------
cat("Etapa 4: Calculando distâncias para a rede sintética...\n\n")

malha_sintet_unida <- st_union(ferro_sintet_utm)

distancias_sintet <- st_distance(amc_pontos, malha_sintet_unida)
amc_pontos$dist_rail_sintetica_km <- as.numeric(distancias_sintet) / 1000

cat("  ✓ Coluna 'dist_rail_sintetica_km' criada\n")
cat(sprintf("    Média: %.2f km | Mediana: %.2f km | Max: %.2f km\n\n",
            mean(amc_pontos$dist_rail_sintetica_km, na.rm = TRUE),
            median(amc_pontos$dist_rail_sintetica_km, na.rm = TRUE),
            max(amc_pontos$dist_rail_sintetica_km, na.rm = TRUE)))

# 6. DISTÂNCIAS CRONOLÓGICAS PARA REDE REAL ----------------------------------
cat("Etapa 5: Calculando distâncias cronológicas para a rede real...\n\n")

# Identifica os anos únicos de inauguração
anos_disponiveis <- sort(unique(na.omit(ferro_reais_utm$ano_inaug)))

cat(sprintf("  Anos disponíveis: %d\n", length(anos_disponiveis)))
cat(sprintf("  Período: %d a %d\n\n", min(anos_disponiveis), max(anos_disponiveis)))

for(i in seq_along(anos_disponiveis)) {
  ano <- anos_disponiveis[i]
  
  # Filtra a malha existente ATÉ aquele ano (inclusivo)
  ferrovia_sub <- ferro_reais_utm |>
    filter(ano_inaug <= ano)
  
  # Unifica a geometria do ano
  malha_ano_unida <- st_union(ferrovia_sub)
  
  # Calcula distâncias
  distancias_ano <- st_distance(amc_pontos, malha_ano_unida)
  
  # Cria coluna com nome sistemático
  col_name <- paste0("dist_rail_real_", ano)
  amc_pontos[[col_name]] <- as.numeric(distancias_ano) / 1000
  
  # Feedback a cada 10 anos
  if (i %% 10 == 0 || i == length(anos_disponiveis)) {
    cat(sprintf("  ✓ Ano %d (%d/%d): coluna '%s' criada\n",
                ano, i, length(anos_disponiveis), col_name))
  }
}

cat("\n  ✓ Todas as distâncias cronológicas calculadas\n\n")

# 7. PREPARAÇÃO DA BASE FINAL -------------------------------------------------
cat("Etapa 6: Preparando base de dados final...\n\n")

base_distancias <- amc_pontos |>
  st_drop_geometry() |>
  select(code_amc, dist_rail_sintetica_km, starts_with("dist_rail_real_")) |>
  as.data.frame()

cat(sprintf("  ✓ Base final contém:\n")
cat(sprintf("    - %d AMCs\n", nrow(base_distancias))
cat(sprintf("    - %d colunas\n", ncol(base_distancias))
cat(sprintf("    - 1 coluna sintética + %d colunas reais cronológicas\n\n",
            ncol(base_distancias) - 2))

# Verificar missings
missing_count <- base_distancias |>
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

# 8. EXPORTAÇÃO ---------------------------------------------------------------
cat("Etapa 7: Exportando base de dados...\n\n")

output_file <- paste0(data.wd, "/base_distancias_amcs_nordeste_semmar.csv")

write_csv(base_distancias, output_file)

cat(sprintf("  ✓ Arquivo salvo: %s\n\n", basename(output_file)))

# 9. SUMÁRIO FINAL -----------------------------------------------------------
cat("========================================================================\n")
cat("✅ BASE DE DISTÂNCIAS CRIADA COM SUCESSO!\n")
cat("========================================================================\n\n")

cat("RESUMO DA BASE:\n")
cat(sprintf("  • Arquivo: base_distancias_amcs_nordeste_semmar.csv\n"))
cat(sprintf("  • Linhas: %d AMCs\n", nrow(base_distancias))
cat(sprintf("  • Colunas: %d\n\n", ncol(base_distancias))

cat("VARIÁVEIS:\n")
cat("  • code_amc: Código único da AMC\n")
cat("  • dist_rail_sintetica_km: Distância até rede sintética (estática)\n")
cat("  • dist_rail_real_YYYY: Distância até rede real acumulada até ano YYYY\n\n")

cat("Próximos passos:\n")
cat("  1. Executar: 2_Criar_Base_Dummy_Atendimento.R\n")
cat("  2. Executar: 3_Criar_Base_Densidade_Ferrovias.R\n")
cat("  3. Usar as bases em análises econométricas\n\n")
