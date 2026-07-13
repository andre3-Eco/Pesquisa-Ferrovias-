# ==============================================================================
# Etapa 17
# CRIAR BASE DE DENSIDADE DE BUFFER USANDO REDE FAKE (PLACEBO CONTINENTAL)
# Placebo In-Space: instrumento = densidade da rede sintética transladada aleatoriamente
# ==============================================================================

library(sf)
library(tidyverse)
library(furrr)
library(future)

if (!exists("data.wd")) {
  data.wd <- normalizePath(file.path(getwd(), "..", ".."))
}
setwd(data.wd)

sf_use_s2(FALSE)

# -------------------- PARÂMETROS E PARALELIZAÇÃO --------------------
raios_m <- c(5000, 10000, 20000, 50000)   # 5, 10, 20, 50 km
raios_km <- raios_m / 1000

# Usar múltiplos núcleos
plan(multisession, workers = availableCores() - 1)

# -------------------- CARREGAMENTO DE DADOS --------------------
crs_projeto <- 31984

amcs_ne_utm <- readRDS("01-dados/processados/amcs_geometria.rds") %>% 
  st_transform(crs = crs_projeto)

# Carrega a nova rede placebo estrutural gerada pela Etapa 16 otimizada
ferro_placebo_utm <- st_read("05-geometrias/Rotas_LCP_Fake_Random.gpkg", quiet = TRUE) %>% 
  st_transform(crs = crs_projeto)

if (!"ano_inaug" %in% names(ferro_placebo_utm)) {
  stop("ERRO: Coluna 'ano_inaug' ausente na base de ferrovia placebo.")
}

amcs_base <- amcs_ne_utm %>%
  mutate(area_amc_km2 = as.numeric(st_area(.)) / 1e6) %>%
  st_drop_geometry() %>%
  select(code_amc, area_amc_km2)

# -------------------- PRÉ-CÁLCULO DE BUFFERS --------------------

buffers_precalc_placebo <- list()

for (r in raios_m) {
  nome_raio <- as.character(r)
  buffers_precalc_placebo[[nome_raio]] <- st_buffer(ferro_placebo_utm, dist = r)
}

# -------------------- FUNÇÃO DE CÁLCULO RÁPIDO --------------------
calcular_densidade_rapida <- function(ferrovias_buffer, amcs_geo, base_areas) {
  if (nrow(ferrovias_buffer) == 0) return(rep(0, nrow(base_areas)))
  
  buffer_unido <- st_union(ferrovias_buffer)
  
  # Pré-filtro de interseção para não calcular áreas onde o buffer não passa
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
anos_disponiveis <- sort(unique(na.omit(ferro_placebo_utm$ano_inaug)))

cat(sprintf("  Encontrados %d anos únicos (%d a %d)\n\n",
            length(anos_disponiveis), min(anos_disponiveis), max(anos_disponiveis)))

# -------------------- PROCESSAMENTO PARALELO (LONG FORMAT) --------------------

processar_ano <- function(ano) {
  # Inicia um tibble já no formato de painel para o ano corrente
  df_res_ano <- amcs_base %>%
    select(code_amc) %>%
    mutate(ano = ano)
  
  for (k in seq_along(raios_m)) {
    r_m <- raios_m[k]
    r_nome <- as.character(r_m)
    r_km <- raios_km[k]
    
    placebo_ano <- buffers_precalc_placebo[[r_nome]] %>% filter(ano_inaug <= ano)
    
    dens_placebo <- calcular_densidade_rapida(placebo_ano, amcs_ne_utm, amcs_base)
    
    # Adiciona a coluna com o nome limpo (sem o ano no nome da variável)
    df_res_ano[[paste0("dens_placebo_", r_km, "km")]] <- dens_placebo
  }
  return(df_res_ano)
}

# future_map_dfr processa em paralelo e aplica um "bind_rows" automático,
# gerando um painel empilhado perfeitamente formatado para regressões.
painel_densidade_placebo <- future_map_dfr(anos_disponiveis, processar_ano, .progress = TRUE)

# -------------------- EXPORTAÇÃO FINAL --------------------
output_dir <- "01-dados/processados"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

arquivo_csv <- paste0(output_dir, "/painel_densidade_placebo_long.csv")
arquivo_rds <- paste0(output_dir, "/painel_densidade_placebo_long.rds")

write_csv(painel_densidade_placebo, arquivo_csv)
saveRDS(painel_densidade_placebo, arquivo_rds)
