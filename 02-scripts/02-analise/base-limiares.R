# ==============================================================================
# CRIAR BASE DE DUMMY DE ATENDIMENTO POR FERROVIA (MÚLTIPLOS LIMIARES)
# ==============================================================================
# Esta base gera arquivos separados para diferentes limiares de distância,
# calculando a matriz espacial apenas uma vez (altamente otimizado).
# ==============================================================================

library(sf)
library(tidyverse)
library(geobr)

cat("========================================================================\n")
cat("CRIANDO BASE DE DUMMY DE ATENDIMENTO POR FERROVIA (MÚLTIPLOS LIMIARES)\n")
cat("========================================================================\n\n")

if (!exists("data.wd")) data.wd <- getwd()

sf_use_s2(FALSE)

# 2. PARÂMETRO: DEFINIR VETOR DE LIMIARES (em km) ------------------------------
# Defina aqui todos os cortes que deseja testar em suas análises de robustez.
LIMIARES_KM <- c(10, 25, 50, 100)

cat(sprintf("Limiares de distância que serão testados: %s km\n\n", paste(LIMIARES_KM, collapse = ", ")))

# 3. CARREGAMENTO DE DADOS GEOESPACIAIS ----------------------------------------
cat("Etapa 1: Carregando dados geoespaciais...\n\n")

amcs_70_10 <- read_comparable_areas(start_year = 1970, end_year = 2010)
amcs_nordeste <- amcs_70_10 |> filter(substr(list_code_muni_2010, 1, 1) == "2")

ferrovias_reais <- st_read(paste0(data.wd, "/05-geometrias/ferrovias_cronologicas.gpkg"), quiet = TRUE)
ferrovias_sinteticas <- st_read(paste0(data.wd, "/05-geometrias/Rotas_LCP_OD_Real.gpkg"), quiet = TRUE)

# 4. PADRONIZAÇÃO DE PROJEÇÃO E CENTRÓIDES -------------------------------------
cat("Etapa 2: Projetando (UTM 24S) e gerando centróides...\n\n")

crs_projeto <- 31984
amcs_ne_utm      <- st_transform(amcs_nordeste, crs = crs_projeto)
ferro_reais_utm  <- st_transform(ferrovias_reais, crs = crs_projeto)
ferro_sintet_utm <- st_transform(ferrovias_sinteticas, crs = crs_projeto)

amc_pontos <- st_centroid(amcs_ne_utm)

# 5. PREPARAÇÃO DAS LISTAS DE RESULTADOS ---------------------------------------
# Cria uma lista onde cada elemento é um dataframe para um limiar específico
lista_bases <- lapply(LIMIARES_KM, function(x) {
  amc_pontos |> st_drop_geometry() |> select(code_amc)
})
names(lista_bases) <- paste0("km_", LIMIARES_KM)

# 6. DISTÂNCIAS DA REDE SINTÉTICA ----------------------------------------------
cat("Etapa 3: Processando rede sintética para todos os limiares...\n")

malha_sintet_unida <- st_union(ferro_sintet_utm)
distancias_sintet_km <- as.numeric(st_distance(amc_pontos, malha_sintet_unida)) / 1000
cobertura_sintet <- 1 / (1 + distancias_sintet_km)

# Popula as bases com a sintética
for (i in seq_along(LIMIARES_KM)) {
  limiar <- LIMIARES_KM[i]
  lista_bases[[i]]$dummy_atendida_sintetica <- as.integer(distancias_sintet_km <= limiar)
  lista_bases[[i]]$cobertura_continua_sintetica <- cobertura_sintet
}
cat("  ✓ Dummies sintéticas criadas.\n\n")

# 7. DISTÂNCIAS DA REDE REAL (LOOP DE ANOS) ------------------------------------
cat("Etapa 4: Processando dummies cronológicas para rede real...\n")

anos_disponiveis <- sort(unique(na.omit(ferro_reais_utm$ano_inaug)))

for(ano in anos_disponiveis) {
  
  # Filtra ferrovias até o ano
  ferrovia_sub <- ferro_reais_utm |> filter(ano_inaug <= ano)
  malha_ano_unida <- st_union(ferrovia_sub)
  
  # Computa distância APENAS UMA VEZ por ano
  distancias_ano_km <- as.numeric(st_distance(amc_pontos, malha_ano_unida)) / 1000
  cobertura_ano <- 1 / (1 + distancias_ano_km)
  
  # Aplica a distância para todos os limiares
  col_dummy <- paste0("dummy_atendida_real_", ano)
  col_cont  <- paste0("cobertura_continua_real_", ano)
  
  for (i in seq_along(LIMIARES_KM)) {
    limiar <- LIMIARES_KM[i]
    lista_bases[[i]][[col_dummy]] <- as.integer(distancias_ano_km <= limiar)
    lista_bases[[i]][[col_cont]]  <- cobertura_ano
  }
  
  if (ano %% 10 == 0 || ano == max(anos_disponiveis)) {
    cat(sprintf("  ✓ Ano %d processado.\n", ano))
  }
}

cat("\n  ✓ Todas as distâncias reais computadas e divididas por limiar.\n\n")

# 8. EXPORTAÇÃO DOS ARQUIVOS (UM POR LIMIAR) -----------------------------------
cat("Etapa 5: Exportando arquivos CSV de sensibilidade...\n\n")

dir.create(paste0(data.wd, "/01-dados/processados/limiares_atendimento"), showWarnings = FALSE, recursive = TRUE)

for (i in seq_along(LIMIARES_KM)) {
  limiar <- LIMIARES_KM[i]
  base_final <- lista_bases[[i]]
  
  # Ordenar colunas logicamente
  cols_dummies_real <- grep("^dummy_atendida_real_", names(base_final), value = TRUE) |> sort()
  cols_continuas_real <- grep("^cobertura_continua_real_", names(base_final), value = TRUE) |> sort()
  
  base_final <- base_final |>
    select(code_amc, dummy_atendida_sintetica, cobertura_continua_sintetica,
           all_of(cols_dummies_real), all_of(cols_continuas_real))
  
  # Exportar Base Completa
  caminho_completa <- sprintf("%s/01-dados/processados/limiares_atendimento/base_dummy_ferrovias_%dkm.csv", data.wd, limiar)
  write_csv(base_final, caminho_completa)
  
  # Exportar Base Simples (Apenas Dummies)
  base_simples <- base_final |> select(code_amc, dummy_atendida_sintetica, starts_with("dummy_atendida_real_"))
  caminho_simples <- sprintf("%s/01-dados/processados/limiares_atendimento/base_dummy_simples_%dkm.csv", data.wd, limiar)
  write_csv(base_simples, caminho_simples)
  
  cat(sprintf("  ✓ Exportado: base_dummy_ferrovias_%dkm.csv\n", limiar))
}

cat("\n========================================================================\n")
cat("PROCESSO CONCLUÍDO COM SUCESSO!\n")
cat("Os arquivos estão salvos na pasta: 01-dados/processados/limiares_atendimento/\n")