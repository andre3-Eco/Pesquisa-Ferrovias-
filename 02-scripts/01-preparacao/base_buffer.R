# ==============================================================================
# CRIAR BASE UNIFICADA DE DENSIDADE DE FERROVIAS (REAL E SINTÉTICA LCP)
# Método adaptado do paper "Old but gold" (Baerlocher et al., 2026)
#
# Saída: base_densidade_buffer_completa.csv
# ==============================================================================

# 1. PACOTES E CONFIGURAÇÕES ---------------------------------------------------
library(sf)
library(tidyverse)

cat("========================================================================\n")
cat("CRIANDO BASE UNIFICADA DE DENSIDADE DE FERROVIAS (REAL E SINTÉTICA)\n")
cat("Buffer de 5km - Correção de Alinhamento Espacial Aplicada\n")
cat("========================================================================\n\n")

if (!exists("data.wd")) data.wd <- getwd()
sf_use_s2(FALSE) # Desativar geometria esférica para evitar problemas de topologia no st_buffer

# 2. CARREGAMENTO DE DADOS GEOESPACIAIS ----------------------------------------
cat("Etapa 1: Carregando dados geoespaciais...\n")

amcs_nordeste <- readRDS(paste0(data.wd, "/01-dados/processados/amcs_geometria.rds"))
ferrovias_reais <- st_read(paste0(data.wd, "/05-geometrias/ferrovias_cronologicas.gpkg"), quiet = TRUE)
ferrovias_sinteticas <- st_read(paste0(data.wd, "/05-geometrias/Rotas_LCP_OD_Real.gpkg"), quiet = TRUE)

if (!"ano_inaug" %in% names(ferrovias_reais) || !"ano_inaug" %in% names(ferrovias_sinteticas)) {
  stop("ERRO: Coluna 'ano_inaug' ausente em uma das bases de ferrovia.")
}

# 3. PADRONIZAÇÃO DE PROJEÇÃO (UTM 24S) E SETUP DE ÁREAS -----------------------
cat("Etapa 2: Padronizando projeções e calculando áreas base...\n")

crs_projeto <- 31984

amcs_ne_utm <- st_transform(amcs_nordeste, crs = crs_projeto)
ferro_reais_utm <- st_transform(ferrovias_reais, crs = crs_projeto)
ferro_sinteticas_utm <- st_transform(ferrovias_sinteticas, crs = crs_projeto)

# Isolar a área total de todas as AMCs originais
amcs_base <- amcs_ne_utm |>
  mutate(area_amc_km2 = as.numeric(st_area(amcs_ne_utm)) / 1e6) |>
  st_drop_geometry() |>
  select(code_amc, area_amc_km2)

# 4. PREPARAR DADOS TEMPORAIS --------------------------------------------------
# Identifica todos os anos onde houve alguma inauguração (real ou sintética)
anos_disponiveis <- sort(unique(c(
  na.omit(ferro_reais_utm$ano_inaug), 
  na.omit(ferro_sinteticas_utm$ano_inaug)
)))

cat(sprintf("  Encontrados %d anos únicos (%d a %d)\n\n", 
            length(anos_disponiveis), min(anos_disponiveis), max(anos_disponiveis)))

# 5. FUNÇÃO DE CÁLCULO DE DENSIDADE (COM CORREÇÃO DEFINITIVA DE ÁREA) ----------
calcular_densidade <- function(ferrovias_filtradas, amcs_geo, base_areas) {
  
  if (nrow(ferrovias_filtradas) == 0) {
    return(rep(0, nrow(base_areas)))
  }
  
  malha_unida <- st_union(ferrovias_filtradas)
  buffer_5km <- st_buffer(malha_unida, dist = 5000)
  intersecao <- st_intersection(amcs_geo, buffer_5km)
  
  if (nrow(intersecao) == 0) {
    return(rep(0, nrow(base_areas)))
  }
  
  # CORREÇÃO AQUI: Calculando a área passando o objeto 'intersecao' inteiro, 
  # sem tentar adivinhar o nome da coluna de geometria.
  intersecao$area_intersecao_km2 <- as.numeric(st_area(intersecao)) / 1e6
  
  # Agrupa por código da AMC somando as áreas dos pedaços interceptados
  intersecao_areas <- intersecao |>
    st_drop_geometry() |>
    group_by(code_amc) |>
    summarise(area_intersecao_km2 = sum(area_intersecao_km2, na.rm = TRUE))
  
  # Left join garante que todas as AMCs originais recebam um valor (0 para as que ficaram de fora)
  vetor_densidade <- base_areas |>
    left_join(intersecao_areas, by = "code_amc") |>
    mutate(
      area_intersecao_km2 = replace_na(area_intersecao_km2, 0),
      densidade = area_intersecao_km2 / area_amc_km2
    ) |>
    pull(densidade) # Extrai na ordem exata da base
  
  return(vetor_densidade)
}

# 6. LOOP POR ANO --------------------------------------------------------------
cat("Etapa 3: Iniciando cálculo histórico ano a ano...\n")

lista_resultados <- list()

for (j in seq_along(anos_disponiveis)) {
  ano <- anos_disponiveis[j]
  
  # Filtra até o ano atual
  reais_ano <- ferro_reais_utm |> filter(ano_inaug <= ano)
  sinteticas_ano <- ferro_sinteticas_utm |> filter(ano_inaug <= ano)
  
  # Calcula densidades usando a função corrigida
  dens_real <- calcular_densidade(reais_ano, amcs_ne_utm, amcs_base)
  dens_sint <- calcular_densidade(sinteticas_ano, amcs_ne_utm, amcs_base)
  
  # Armazena em um dataframe temporário
  df_ano <- data.frame(
    real = dens_real,
    sintetica = dens_sint
  )
  colnames(df_ano) <- c(paste0("densidade_buffer_real_", ano), 
                        paste0("densidade_buffer_sintetica_", ano))
  
  lista_resultados[[as.character(ano)]] <- df_ano
  
  # Feedback no console
  if (j %% 10 == 0 || j == length(anos_disponiveis)) {
    cat(sprintf("  ✓ Ano %d processado (%d/%d)\n", ano, j, length(anos_disponiveis)))
  }
}

# 7. CONSTRUIR BASE FINAL ------------------------------------------------------
cat("\nEtapa 4: Compilando e salvando bases...\n")

# Junta todas as colunas de todos os anos
resultados_combinados <- bind_cols(lista_resultados)

# Une com os dados base das AMCs
base_final <- amcs_base |>
  bind_cols(resultados_combinados)

# 8. EXPORTAÇÃO ----------------------------------------------------------------
output_dir <- paste0(data.wd, "/01-dados/processados")
if(!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

arquivo_completo <- paste0(output_dir, "/base_densidade_buffer_unificada.csv")
write_csv(base_final, arquivo_completo)

cat("\n=== RESUMO DA BASE GERADA ===\n")
cat(sprintf("  - AMCs processadas: %d\n", nrow(base_final)))
cat(sprintf("  - Anos cobertos: %d a %d\n", min(anos_disponiveis), max(anos_disponiveis)))
cat(sprintf("  - Variáveis geradas: %d\n", ncol(base_final)))
cat("\n✅ PROCESSO CONCLUÍDO COM SUCESSO!\n")