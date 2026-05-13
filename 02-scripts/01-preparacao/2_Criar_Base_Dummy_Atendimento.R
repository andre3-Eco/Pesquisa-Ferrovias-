# ==============================================================================
# CRIAR BASE DE DUMMY DE ATENDIMENTO POR FERROVIA
# Saída: base_dummy_atendimento_ferrovias.csv
# ==============================================================================
# Esta base contém dummies indicando se uma AMC é atendida por ferrovia:
#   - dummy_atendida_sintetica: 1 se distância até sintética ≤ limiar
#   - dummy_atendida_real_YYYY: 1 se distância até real (acumulada até YYYY) ≤ limiar
#   Também exporta versão contínua (dist_inversa) como medida alternativa
# ==============================================================================

# 1. PACOTES E CONFIGURAÇÕES ---------------------------------------------------
library(sf)
library(tidyverse)
library(geobr)

cat("========================================================================\n")
cat("CRIANDO BASE DE DUMMY DE ATENDIMENTO POR FERROVIA\n")
cat("========================================================================\n\n")

if (!exists("data.wd")) data.wd <- getwd()

sf_use_s2(FALSE)

# 2. PARÂMETRO: DEFINIR LIMIAR DE DISTÂNCIA (em km) ---------------------------
# AMCs com distância até ferrovia ≤ limiar são consideradas "atendidas"
LIMIAR_KM <- 25  # Você pode ajustar esse valor
# Opções comuns: 10 km (muito restritivo), 25 km (moderado), 50 km (permissivo)

cat(sprintf("Limiar de distância definido: %.0f km\n", LIMIAR_KM))
cat("(AMCs com distância ≤ limiar são consideradas 'atendidas')\n\n")

# 3. CARREGAMENTO DE DADOS GEOESPACIAIS ----------------------------------------
cat("Etapa 1: Carregando dados geoespaciais...\n\n")

## 3a. AMCs do Nordeste
cat("  → Baixando AMCs (1970-2010) do IPEA...\n")
amcs_70_10 <- read_comparable_areas(start_year = 1970, end_year = 2010)

amcs_nordeste <- amcs_70_10 |>
  filter(substr(list_code_muni_2010, 1, 1) == "2")

cat(sprintf("    ✓ %d AMCs do Nordeste carregadas\n\n", nrow(amcs_nordeste)))

## 3b. Ferrovias Reais (cronológicas)
cat("  → Carregando ferrovias reais cronológicas...\n")
ferrovias_reais <- st_read(
  paste0(data.wd, "/Dados pesquisa (Ferrovias)/ferrovias_cronologicas.gpkg"),
  quiet = TRUE
)

cat(sprintf("    ✓ %d segmentos de ferrovias reais carregados\n\n", nrow(ferrovias_reais)))

## 3c. Ferrovias Sintéticas
cat("  → Carregando rede sintética (LCP sem mar)...\n")
ferrovias_sinteticas <- st_read(
  paste0(data.wd, "/Dados pesquisa (Ferrovias)/Rotas_LCP_OD_Real_SemMar.gpkg"),
  quiet = TRUE
)

cat(sprintf("    ✓ %d rotas sintéticas carregadas\n\n", nrow(ferrovias_sinteticas)))

# 4. PADRONIZAÇÃO DE PROJEÇÃO -------------------------------------------------
cat("Etapa 2: Padronizando projeção (UTM 24S - EPSG 31984)...\n\n")

crs_projeto <- 31984

amcs_ne_utm      <- st_transform(amcs_nordeste, crs = crs_projeto)
ferro_reais_utm  <- st_transform(ferrovias_reais, crs = crs_projeto)
ferro_sintet_utm <- st_transform(ferrovias_sinteticas, crs = crs_projeto)

cat("  ✓ Todas as camadas projetadas para UTM 24S\n\n")

# 5. GERAÇÃO DE CENTRÓIDES ---------------------------------------------------
cat("Etapa 3: Gerando centróides das AMCs...\n\n")

amc_pontos <- st_centroid(amcs_ne_utm)

cat(sprintf("  ✓ %d centróides criados\n\n", nrow(amc_pontos)))

# 6. DUMMY PARA REDE SINTÉTICA -----------------------------------------------
cat("Etapa 4: Criando dummy para rede sintética...\n\n")

malha_sintet_unida <- st_union(ferro_sintet_utm)

distancias_sintet <- st_distance(amc_pontos, malha_sintet_unida)
distancias_sintet_km <- as.numeric(distancias_sintet) / 1000

# Dummy: 1 se atendida (distância ≤ limiar)
amc_pontos$dummy_atendida_sintetica <- as.integer(distancias_sintet_km <= LIMIAR_KM)

# Medida contínua: inversa da distância (utilidade decresce com distância)
amc_pontos$cobertura_continua_sintetica <- 1 / (1 + distancias_sintet_km)

atendidas_sintet <- sum(amc_pontos$dummy_atendida_sintetica)
pct_atendidas_sintet <- 100 * mean(amc_pontos$dummy_atendida_sintetica)

cat(sprintf("  ✓ Coluna 'dummy_atendida_sintetica' criada\n"))
cat(sprintf("    - AMCs atendidas: %d (%.1f%%)\n", atendidas_sintet, pct_atendidas_sintet))
cat(sprintf("    - AMCs não atendidas: %d (%.1f%%)\n\n",
            nrow(amc_pontos) - atendidas_sintet, 100 - pct_atendidas_sintet))

# 7. DUMMIES CRONOLÓGICAS PARA REDE REAL -------------------------------------
cat("Etapa 5: Criando dummies cronológicas para rede real...\n\n")

# Identifica os anos únicos
anos_disponiveis <- sort(unique(na.omit(ferro_reais_utm$ano_inaug)))

cat(sprintf("  Processando %d anos de dados...\n\n", length(anos_disponiveis)))

for(i in seq_along(anos_disponiveis)) {
  ano <- anos_disponiveis[i]
  
  # Filtra ferrovias até o ano (inclusivo)
  ferrovia_sub <- ferro_reais_utm |>
    filter(ano_inaug <= ano)
  
  # Unifica geometria
  malha_ano_unida <- st_union(ferrovia_sub)
  
  # Calcula distâncias
  distancias_ano <- st_distance(amc_pontos, malha_ano_unida)
  distancias_ano_km <- as.numeric(distancias_ano) / 1000
  
  # Cria dummy
  col_dummy_name <- paste0("dummy_atendida_real_", ano)
  amc_pontos[[col_dummy_name]] <- as.integer(distancias_ano_km <= LIMIAR_KM)
  
  # Cria medida contínua (opcional, para análises complementares)
  col_continua_name <- paste0("cobertura_continua_real_", ano)
  amc_pontos[[col_continua_name]] <- 1 / (1 + distancias_ano_km)
  
  # Feedback
  if (i %% 10 == 0 || i == length(anos_disponiveis)) {
    atendidas_ano <- sum(amc_pontos[[col_dummy_name]])
    pct_ano <- 100 * mean(amc_pontos[[col_dummy_name]])
    cat(sprintf("  ✓ Ano %d (%d/%d): %d AMCs atendidas (%.1f%%)\n",
                ano, i, length(anos_disponiveis), atendidas_ano, pct_ano))
  }
}

cat("\n  ✓ Todas as dummies cronológicas criadas\n\n")

# 8. PREPARAÇÃO DA BASE FINAL -------------------------------------------------
cat("Etapa 6: Preparando base de dados final...\n\n")

base_dummy <- amc_pontos |>
  st_drop_geometry() |>
  select(
    code_amc,
    dummy_atendida_sintetica,
    cobertura_continua_sintetica,
    starts_with("dummy_atendida_real_"),
    starts_with("cobertura_continua_real_")
  ) |>
  as.data.frame()

# Reordenar colunas para melhor legibilidade
cols_dummies_real <- grep("^dummy_atendida_real_", names(base_dummy), value = TRUE) |> sort()
cols_continuas_real <- grep("^cobertura_continua_real_", names(base_dummy), value = TRUE) |> sort()

base_dummy <- base_dummy |>
  select(
    code_amc,
    dummy_atendida_sintetica,
    cobertura_continua_sintetica,
    all_of(cols_dummies_real),
    all_of(cols_continuas_real)
  )

cat(sprintf("  ✓ Base final contém:\n"))
cat(sprintf("    - %d AMCs\n", nrow(base_dummy)))
cat(sprintf("    - %d colunas\n", ncol(base_dummy)))
cat(sprintf("    - 1 dummy sintética + %d dummies reais cronológicas\n", length(anos_disponiveis)))
cat(sprintf("    - Medidas contínuas (cobertura) para cada período\n\n"))

# 9. ESTATÍSTICAS DESCRITIVAS -------------------------------------------------
cat("Etapa 7: Computando estatísticas descritivas...\n\n")

cat("EVOLUÇÃO DO ATENDIMENTO (rede real):\n")
cat("Ano\t| AMCs Atendidas\t| % Atendidas\n")
cat(strrep("-", 40), "\n")

for(ano in anos_disponiveis[c(1, seq(10, length(anos_disponiveis), 10))]) {
  col_name <- paste0("dummy_atendida_real_", ano)
  if (col_name %in% names(base_dummy)) {
    atendidas <- sum(base_dummy[[col_name]])
    pct <- 100 * mean(base_dummy[[col_name]])
    cat(sprintf("%d\t| %d\t\t| %.1f%%\n", ano, atendidas, pct))
  }
}

cat("\n")

# 10. EXPORTAÇÃO ---------------------------------------------------------------
cat("Etapa 8: Exportando bases de dados...\n\n")

# Base com dummies (binária)
output_dummy <- paste0(data.wd, "/base_dummy_atendimento_ferrovias.csv")
write_csv(base_dummy, output_dummy)
cat(sprintf("  ✓ Base com dummies: %s\n", basename(output_dummy)))

# Base apenas com dummies (mais compacta)
base_dummy_only <- base_dummy |>
  select(code_amc, dummy_atendida_sintetica, starts_with("dummy_atendida_real_"))

output_dummy_only <- paste0(data.wd, "/base_dummy_atendimento_simples.csv")
write_csv(base_dummy_only, output_dummy_only)
cat(sprintf("  ✓ Base simplificada (só dummies): %s\n\n", basename(output_dummy_only)))

# 11. SUMÁRIO FINAL -----------------------------------------------------------
cat("========================================================================\n")
cat("✅ BASE DE DUMMY DE ATENDIMENTO CRIADA COM SUCESSO!\n")
cat("========================================================================\n\n")

cat("RESUMO DAS BASES:\n")
cat(sprintf("  • Limiar de atendimento: %.0f km\n", LIMIAR_KM))
cat(sprintf("  • Total de AMCs: %d\n\n", nrow(base_dummy)))

cat("ARQUIVO 1: base_dummy_atendimento_ferrovias.csv\n")
cat(sprintf("  • %d colunas (inclui medidas contínuas)\n", ncol(base_dummy)))
cat("  • Variáveis:\n")
cat("    - code_amc\n")
cat("    - dummy_atendida_sintetica: 0/1 (rede sintética)\n")
cat("    - cobertura_continua_sintetica: [0,1]\n")
cat("    - dummy_atendida_real_YYYY: 0/1 (rede real até YYYY)\n")
cat("    - cobertura_continua_real_YYYY: [0,1]\n\n")

cat("ARQUIVO 2: base_dummy_atendimento_simples.csv\n")
cat("  • Versão compacta com apenas as dummies\n")
cat("  • Mais adequada para modelos econométricos\n\n")

cat("COMO USAR:\n")
cat("  1. Para análise causal: use dummy_atendida_real_YYYY\n")
cat("  2. Para gradação de impacto: use cobertura_continua_real_YYYY\n")
cat("  3. Combine com outras bases usando code_amc como chave\n\n")

cat("Próximos passos:\n")
cat("  1. Verificar: 3_Criar_Base_Densidade_Ferrovias.R\n")
cat("  2. Integrar bases em análises econométricas\n\n")
