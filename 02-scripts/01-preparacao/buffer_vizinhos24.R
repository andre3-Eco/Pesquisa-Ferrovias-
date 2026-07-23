# ==============================================================================
# Etapa 24
# CRIAR BASE UNIFICADA DE DENSIDADE, DUMMY E SPILLOVERS (VIZINHOS)
# Método adaptado do paper "Old but gold" (Baerlocher et al., 2026)
# ==============================================================================

# 1. PACOTES E CONFIGURAÇÕES ---------------------------------------------------
library(sf)
library(tidyverse)
library(geobr)
library(spdep) # ADICIONADO para calcular matriz de vizinhança espacial

if (!exists("data.wd")) data.wd <- getwd()
sf_use_s2(FALSE) # Desativar geometria esférica para evitar problemas de topologia no st_buffer

# 2. CARREGAMENTO DE DADOS GEOESPACIAIS ----------------------------------------

# Baixa todas as AMCs comparáveis entre 1970 e 2010
amcs_all <- read_comparable_areas(start_year = 1970, end_year = 2010)

# Mantém apenas as AMCs do Nordeste (código do município começa com "2")
amcs_geometria <- amcs_all |>
  dplyr::filter(substr(list_code_muni_2010, 1, 1) == "2") |>
  dplyr::distinct(code_amc, .keep_all = TRUE)   

saveRDS(amcs_geometria, file = "01-dados/processados/amcs_geometria.rds")

amcs_nordeste <- readRDS(paste0(data.wd, "/01-dados/processados/amcs_geometria.rds")) 
ferrovias_reais <- st_read(paste0(data.wd, "/05-geometrias/ferrovias_cronologicas.gpkg"), quiet = TRUE)
ferrovias_sinteticas <- st_read(paste0(data.wd, "/05-geometrias/Rotas_LCP_OD_Real.gpkg"), quiet = TRUE)

if (!"ano_inaug" %in% names(ferrovias_reais) || !"ano_inaug" %in% names(ferrovias_sinteticas)) {
  stop("ERRO: Coluna 'ano_inaug' ausente em uma das bases de ferrovia.")
}

# 3. PADRONIZAÇÃO DE PROJEÇÃO (UTM 24S) E SETUP DE ÁREAS -----------------------

crs_projeto <- 31984

amcs_ne_utm <- st_transform(amcs_nordeste, crs = crs_projeto)
ferro_reais_utm <- st_transform(ferrovias_reais, crs = crs_projeto)
ferro_sinteticas_utm <- st_transform(ferrovias_sinteticas, crs = crs_projeto)

# Isolar a área total de todas as AMCs originais
amcs_base <- amcs_ne_utm |>
  mutate(area_amc_km2 = as.numeric(st_area(amcs_ne_utm)) / 1e6) |>
  st_drop_geometry() |>
  select(code_amc, area_amc_km2)

# ================= NOVIDADE: MATRIZ DE VIZINHANÇA ESPACIAL ====================
# Cria a lista de vizinhos contíguos (fronteiras compartilhadas - Queen contiguity)
lista_vizinhos <- poly2nb(amcs_ne_utm, queen = TRUE)
# Transforma a lista em uma matriz de pesos espaciais normalizada pela linha (média)
# zero.policy = TRUE permite que ilhas (ex: Fernando de Noronha) não quebrem o código
pesos_espaciais <- nb2listw(lista_vizinhos, style = "W", zero.policy = TRUE)
# ==============================================================================

# 4. PREPARAR DADOS TEMPORAIS --------------------------------------------------
anos_disponiveis <- sort(unique(c(
  na.omit(ferro_reais_utm$ano_inaug), 
  na.omit(ferro_sinteticas_utm$ano_inaug)
)))

cat(sprintf("  Encontrados %d anos únicos (%d a %d)\n\n", 
            length(anos_disponiveis), min(anos_disponiveis), max(anos_disponiveis)))

# 5. FUNÇÃO DE CÁLCULO AMPLIADA ------------------------------------------------
calcular_tratamentos <- function(ferrovias_filtradas, amcs_geo, base_areas, matriz_pesos) {
  
  # Se não houver ferrovia no ano, retorna zeros para tudo
  if (nrow(ferrovias_filtradas) == 0) {
    n_linhas <- nrow(base_areas)
    return(tibble(
      dens = rep(0, n_linhas),
      dummy = rep(0, n_linhas),
      vizinhos = rep(0, n_linhas)
    ))
  }
  
  malha_unida <- st_union(ferrovias_filtradas)
  buffer_5km <- st_buffer(malha_unida, dist = 5000)
  intersecao <- st_intersection(amcs_geo, buffer_5km)
  
  if (nrow(intersecao) == 0) {
    n_linhas <- nrow(base_areas)
    return(tibble(
      dens = rep(0, n_linhas),
      dummy = rep(0, n_linhas),
      vizinhos = rep(0, n_linhas)
    ))
  }
  
  intersecao$area_intersecao_km2 <- as.numeric(st_area(intersecao)) / 1e6
  
  intersecao_areas <- intersecao |>
    st_drop_geometry() |>
    group_by(code_amc) |>
    summarise(area_intersecao_km2 = sum(area_intersecao_km2, na.rm = TRUE))
  
  # Base com densidade e dummy calculadas no nível AMC
  base_calculada <- base_areas |>
    left_join(intersecao_areas, by = "code_amc") |>
    mutate(
      area_intersecao_km2 = replace_na(area_intersecao_km2, 0),
      densidade = area_intersecao_km2 / area_amc_km2,
      # NOVA REGRA: Se a densidade for maior que 0, a AMC é considerada atendida
      dummy_atend = ifelse(densidade > 0, 1, 0) 
    )
  
  # Extração estrita para manter a ordem vetorial
  vetor_densidade <- base_calculada |> pull(densidade)
  vetor_dummy <- base_calculada |> pull(dummy_atend)
  
  # NOVA REGRA: Calcula o lag espacial (média da densidade dos vizinhos)
  vetor_vizinhos <- lag.listw(matriz_pesos, vetor_densidade, zero.policy = TRUE)
  
  return(tibble(
    dens = vetor_densidade,
    dummy = vetor_dummy,
    vizinhos = vetor_vizinhos
  ))
}

# 6. LOOP POR ANO --------------------------------------------------------------

lista_resultados <- list()

for (j in seq_along(anos_disponiveis)) {
  ano <- anos_disponiveis[j]
  
  reais_ano <- ferro_reais_utm |> filter(ano_inaug <= ano)
  sinteticas_ano <- ferro_sinteticas_utm |> filter(ano_inaug <= ano)
  
  # Calcula usando a função atualizada, repassando os pesos espaciais
  res_real <- calcular_tratamentos(reais_ano, amcs_ne_utm, amcs_base, pesos_espaciais)
  res_sint <- calcular_tratamentos(sinteticas_ano, amcs_ne_utm, amcs_base, pesos_espaciais)
  
  # Armazena em um dataframe nomeando dinamicamente cada tipo de variável
  df_ano <- tibble(
    !!paste0("dens_real_", ano) := res_real$dens,
    !!paste0("dummy_real_", ano) := res_real$dummy,
    !!paste0("vizinhos_dens_real_", ano) := res_real$vizinhos,
    
    !!paste0("dens_sint_", ano) := res_sint$dens,
    !!paste0("dummy_sint_", ano) := res_sint$dummy,
    !!paste0("vizinhos_dens_sint_", ano) := res_sint$vizinhos
  )
  
  lista_resultados[[as.character(ano)]] <- df_ano
  
  if (j %% 10 == 0 || j == length(anos_disponiveis)) {
    cat(sprintf("  ✓ Ano %d processado (%d/%d)\n", ano, j, length(anos_disponiveis)))
  }
}

# 7. CONSTRUIR BASE FINAL ------------------------------------------------------

resultados_combinados <- bind_cols(lista_resultados)

base_final <- amcs_base |>
  bind_cols(resultados_combinados)

# 8. EXPORTAÇÃO ----------------------------------------------------------------
output_dir <- paste0(data.wd, "/01-dados/processados")
if(!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

arquivo_completo <- paste0(output_dir, "/base_densidade_buffer_vizinhos.csv") 
write_csv(base_final, arquivo_completo)

arquivo_rds <- paste0(output_dir, "/base_densidade_buffer_vizinhos.rds")
saveRDS(base_final, arquivo_rds)

