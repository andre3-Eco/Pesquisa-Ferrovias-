# ==============================================================================
# Etapa 19
# GERAR BASE DE DENSIDADE DE BUFFER PARA MÚLTIPLOS RAIOS 
# ==============================================================================

library(sf)
library(tidyverse)
library(furrr)  # Para processamento paralelo
library(future)

if (!exists("data.wd")) data.wd <- getwd()
cat("========================================================================\n")
cat("GERANDO DENSIDADE DE BUFFER – MÚLTIPLOS RAIOS (VERSÃO OTIMIZADA)\n")
cat("========================================================================\n\n")

sf_use_s2(FALSE)

# -------------------- PARÂMETROS E CONFIGURAÇÃO PARALELA --------------------
raios_m <- c(5000, 10000, 20000, 50000)
raios_km <- raios_m / 1000

# Define o uso de múltiplos núcleos do processador (deixe 1 livre para o sistema)
plan(multisession, workers = availableCores() - 1)

# -------------------- CARREGAMENTO DE DADOS GEOESPACIAIS --------------------
cat("Etapa 1: Carregando e padronizando dados geoespaciais...\n")
crs_projeto <- 31984

amcs_ne_utm <- readRDS(paste0(data.wd, "/01-dados/processados/amcs_geometria.rds")) %>% 
  st_transform(crs = crs_projeto)

ferro_reais_utm <- st_read(paste0(data.wd, "/05-geometrias/ferrovias_cronologicas.gpkg"), quiet = TRUE) %>% 
  st_transform(crs = crs_projeto)

ferro_sint_utm <- st_read(paste0(data.wd, "/05-geometrias/Rotas_LCP_OD_Real.gpkg"), quiet = TRUE) %>% 
  st_transform(crs = crs_projeto)

if (!"ano_inaug" %in% names(ferro_reais_utm) || !"ano_inaug" %in% names(ferro_sint_utm)) {
  stop("ERRO: Coluna 'ano_inaug' ausente em uma das bases de ferrovia.")
}

amcs_base <- amcs_ne_utm %>%
  mutate(area_amc_km2 = as.numeric(st_area(amcs_ne_utm)) / 1e6) %>%
  st_drop_geometry() %>%
  select(code_amc, area_amc_km2)

# -------------------- PRÉ-CÁLCULO DOS BUFFERS (O Segredo da Otimização) --------------------
cat("Etapa 2: Pré-calculando buffers para todos os segmentos...\n")
# Em vez de calcular o buffer em cada loop, calculamos uma vez para toda a base
buffers_precalc_real <- list()
buffers_precalc_sint <- list()

for (r in raios_m) {
  nome_raio <- as.character(r)
  buffers_precalc_real[[nome_raio]] <- st_buffer(ferro_reais_utm, dist = r)
  buffers_precalc_sint[[nome_raio]] <- st_buffer(ferro_sint_utm, dist = r)
}

# -------------------- FUNÇÃO DE DENSIDADE OTIMIZADA --------------------
calcular_densidade_rapida <- function(ferrovias_buffer, amcs_geo, base_areas) {
  if (nrow(ferrovias_buffer) == 0) return(rep(0, nrow(base_areas)))
  
  # Une apenas os polígonos já calculados (muito mais rápido do que unir linhas + buffer)
  buffer_unido <- st_union(ferrovias_buffer)
  
  # Pré-filtro: identifica apenas os AMCs que tocam o buffer para evitar interseções inúteis
  amcs_intersecao_idx <- st_intersects(amcs_geo, buffer_unido, sparse = FALSE)[, 1]
  amcs_alvo <- amcs_geo[amcs_intersecao_idx, ]
  
  if (nrow(amcs_alvo) == 0) return(rep(0, nrow(base_areas)))
  
  intersecao <- st_intersection(amcs_alvo, buffer_unido)
  intersecao$area_intersecao_km2 <- as.numeric(st_area(intersecao)) / 1e6
  
  intersecao_areas <- intersecao %>%
    st_drop_geometry() %>%
    group_by(code_amc) %>%
    summarise(area_intersecao_km2 = sum(area_intersecao_km2, na.rm = TRUE))
  
  vetor_densidade <- base_areas %>%
    left_join(intersecao_areas, by = "code_amc") %>%
    mutate(
      area_intersecao_km2 = replace_na(area_intersecao_km2, 0),
      densidade = area_intersecao_km2 / area_amc_km2
    ) %>%
    pull(densidade)
  
  return(vetor_densidade)
}

# -------------------- ANOS DISPONÍVEIS --------------------
anos_disponiveis <- sort(unique(c(
  na.omit(ferro_reais_utm$ano_inaug),
  na.omit(ferro_sint_utm$ano_inaug)
)))
cat(sprintf("  Encontrados %d anos únicos (%d a %d)\n\n",
            length(anos_disponiveis), min(anos_disponiveis), max(anos_disponiveis)))

# -------------------- PROCESSAMENTO PARALELO (MÁGICA DO FURRR) --------------------
cat("Etapa 3: Calculando densidade ano a ano em paralelo...\n")

processar_ano <- function(ano) {
  # O output será uma linha (ou bloco) que depois juntaremos
  df_res_ano <- data.frame(matrix(ncol = length(raios_m) * 2, nrow = nrow(amcs_base)))
  col_names <- c(
    paste0("densidade_buffer_real_", raios_km, "km_", ano),
    paste0("densidade_buffer_sintetica_", raios_km, "km_", ano)
  )
  colnames(df_res_ano) <- col_names
  
  for (k in seq_along(raios_m)) {
    r_m <- raios_m[k]
    r_nome <- as.character(r_m)
    r_km <- raios_km[k]
    
    # Filtra os buffers pré-calculados até o ano da iteração
    reais_ano <- buffers_precalc_real[[r_nome]] %>% filter(ano_inaug <= ano)
    sinteticas_ano <- buffers_precalc_sint[[r_nome]] %>% filter(ano_inaug <= ano)
    
    # Calcula densidade
    dens_real <- calcular_densidade_rapida(reais_ano, amcs_ne_utm, amcs_base)
    dens_sint <- calcular_densidade_rapida(sinteticas_ano, amcs_ne_utm, amcs_base)
    
    # Preenche as colunas do ano
    df_res_ano[[paste0("densidade_buffer_real_", r_km, "km_", ano)]] <- dens_real
    df_res_ano[[paste0("densidade_buffer_sintetica_", r_km, "km_", ano)]] <- dens_sint
  }
  
  return(df_res_ano)
}

# future_map_dfc une as colunas automaticamente após rodar em paralelo
resultados_combinados <- future_map_dfc(anos_disponiveis, processar_ano, .progress = TRUE)

# -------------------- CONSTRUIR BASE FINAL E EXPORTAR --------------------
cat("\nEtapa 4: Compilando e salvando bases...\n")
base_final <- bind_cols(amcs_base, resultados_combinados)

output_dir <- paste0(data.wd, "/01-dados/processados")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

write_csv(base_final, paste0(output_dir, "/base_densidade_buffer_multiraio.csv"))
saveRDS(base_final, paste0(output_dir, "/base_densidade_buffer_multiraio.rds"))

cat("\n✅ PROCESSO CONCLUÍDO COM SUCESSO!\n")