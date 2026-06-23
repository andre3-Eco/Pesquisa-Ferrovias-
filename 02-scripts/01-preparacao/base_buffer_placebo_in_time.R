# ==============================================================================
# GERAR DENSIDADE DE BUFFER COM VARIAÇÃO INVERSA NO TEMPO
# Placebo In‑Time: usa apenas ferrovias que ainda serão construídas (future-only)
# ou uma janela deslizante de N anos antes do ano T.
# Saída: base_densidade_buffer_placebo_in_time.csv (ou .rds)
# ==============================================================================

# 1. PACOTES E CONFIGURAÇÕES ---------------------------------------------------
library(sf)
library(tidyverse)

cat("========================================================================\n")
cat("GERANDO DENSIDADE DE BUFFER – PLACEBO IN‑TIME (INVERSA NO TEMPO)\n")
cat("========================================================================\n\n")

if (!exists("data.wd")) data.wd <- getwd()
sf_use_s2(FALSE) # desativar geometria esférica

# 2. CARREGAMENTO DE DADOS GEOESPACIAIS ----------------------------------------
cat("Etapa 1: Carregando dados geoespaciais...\n")

amcs_nordeste   <- readRDS(paste0(data.wd, "/01-dados/processados/amcs_geometria.rds"))
ferrovias_reais <- st_read(paste0(data.wd, "/05-geometrias/ferrovias_cronologicas.gpkg"), quiet = TRUE)
ferrovias_sint  <- st_read(paste0(data.wd, "/05-geometrias/Rotas_LCP_OD_Real.gpkg"), quiet = TRUE)

if (!"ano_inaug" %in% names(ferrovias_reais) || !"ano_inaug" %in% names(ferrovias_sint)) {
  stop("ERRO: Coluna 'ano_inaug' ausente em uma das bases de ferrovia.")
}

# 3. PADRONIZAÇÃO DE PROJEÇÃO (UTM 24S) E SETUP DE ÁREAS -----------------------
cat("Etapa 2: Padronizando projeções e calculando áreas base...\n")
crs_projeto <- 31984

amcs_ne_utm   <- st_transform(amcs_nordeste, crs = crs_projeto)
ferro_reais_utm <- st_transform(ferrovias_reais, crs = crs_projeto)
ferro_sint_utm  <- st_transform(ferrovias_sint, crs = crs_projeto)

# Área total de cada AMC (km²)
amcs_base <- amcs_ne_utm %>%
  mutate(area_amc_km2 = as.numeric(st_area(amcs_ne_utm)) / 1e6) %>%
  st_drop_geometry() %>%
  select(code_amc, area_amc_km2)

# 4. PARÂMETROS DO TESTE PLACEBO IN‑TIME ---------------------------------------
# Escolha uma das opções abaixo:
#   - "future"   : usa somente ferrovias ainda a serem construídas (ano_inaug > ano)
#   - "windowN"  : usa janela de N anos antes do ano (ano_inaug > ano - N & ano_inaug <= ano)
tipo_inverso <- "future"          # <-- altere para "future", "window10", "window20", etc.
janela_anos  <- ifelse(grepl("window", tipo_inverso),
                       as.integer(sub("window", "", tipo_inverso)),
                       NA)

cat(sprintf("Modo de densidade inversa: %s\n", tipo_inverso))
if (!is.na(janela_anos)) cat(sprintf("Janela de %d anos antes do ano T\n", janela_anos))
cat("\n")

# 5. FUNÇÃO DE CÁLCULO DE DENSIDADE (mesma do script original) -----------------
calcular_densidade <- function(ferrovias_filtradas, amcs_geo, base_areas) {
  if (nrow(ferrovias_filtradas) == 0) {
    return(rep(0, nrow(base_areas)))
  }
  malha_unida   <- st_union(ferrovias_filtradas)
  buffer_5km    <- st_buffer(malha_unida, dist = 5000)   # 5 km em metros
  intersecao    <- st_intersection(amcs_geo, buffer_5km)
  if (nrow(intersecao) == 0) {
    return(rep(0, nrow(base_areas)))
  }
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

# 6. IDENTIFICAR ANOS DISPONÍVEIS ---------------------------------------------
cat("Etapa 3: Identificando anos de inauguração disponíveis...\n")
anos_disponiveis <- sort(unique(c(
  na.omit(ferro_reais_utm$ano_inaug),
  na.omit(ferro_sint_utm$ano_inaug)
)))
cat(sprintf("  Encontrados %d anos únicos (%d a %d)\n\n",
            length(anos_disponiveis), min(anos_disponiveis), max(anos_disponiveis)))

# 7. LOOP POR ANO --------------------------------------------------------------
cat("Etapa 4: Calculando densidade inversa ano a ano...\n")
lista_resultados <- list()

for (j in seq_along(anos_disponiveis)) {
  ano <- anos_disponiveis[j]
  
  # ----- FILTRAGEM INVERSA CONFORME O MODO ESCOLHIDO -----
  if (tipo_inverso == "future") {
    reais_ano     <- ferro_reais_utm     %>% filter(ano_inaug > ano)
    sinteticas_ano<- ferro_sint_utm      %>% filter(ano_inaug > ano)
  } else if (grepl("window", tipo_inverso)) {
    reais_ano     <- ferro_reais_utm     %>%
                    filter(ano_inaug > (ano - janela_anos) & ano_inaug <= ano)
    sinteticas_ano<- ferro_sint_utm      %>%
                    filter(ano_inaug > (ano - janela_anos) & ano_inaug <= ano)
  } else {
    stop("tipo_inverso não reconhecido")
  }
  
  # Cálculo das densidades
  dens_real <- calcular_densidade(reais_ano,   amcs_ne_utm, amcs_base)
  dens_sint <- calcular_densidade(sinteticas_ano, amcs_ne_utm, amcs_base)
  
  # Armazena em dataframe temporário
  df_ano <- data.frame(
    real = dens_real,
    sintetica = dens_sint
  )
  colnames(df_ano) <- c(
    paste0("densidade_buffer_real_", tipo_inverso, "_", ano),
    paste0("densidade_buffer_sintetica_", tipo_inverso, "_", ano)
  )
  
  lista_resultados[[as.character(ano)]] <- df_ano
  
  if (j %% 10 == 0 || j == length(anos_disponiveis)) {
    cat(sprintf("  ✓ Ano %d processado (%d/%d)\n", ano, j, length(anos_disponiveis)))
  }
}

# 8. CONSTRUIR BASE FINAL ------------------------------------------------------
cat("\nEtapa 5: Compilando e salvando bases...\n")
resultados_combinados <- bind_cols(lista_resultados)

base_final <- amcs_base %>%
  bind_cols(resultados_combinados)

# 9. EXPORTAÇÃO ---------------------------------------------------------------
output_dir <- paste0(data.wd, "/01-dados/processados")
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

sufixo <- ifelse(tipo_inverso == "future", "future", paste0("window", janela_anos))
arquivo_csv <- paste0(output_dir, "/base_densidade_buffer_placebo_in_time_", sufixo, ".csv")
arquivo_rds <- paste0(output_dir, "/base_densidade_buffer_placebo_in_time_", sufixo, ".rds")

write_csv(base_final, arquivo_csv)
saveRDS(base_final, arquivo_rds)

cat("\n=== RESUMO DA BASE GERADA ===\n")
cat(sprintf("  - AMCs processadas: %d\n", nrow(base_final)))
cat(sprintf("  - Anos cobertos: %d a %d\n", min(anos_disponiveis), max(anos_disponiveis)))
cat(sprintf("  - Variáveis geradas: %d\n", ncol(base_final)))
cat(sprintf("  - Arquivo CSV: %s\n", arquivo_csv))
cat(sprintf("  - Arquivo RDS: %s\n", arquivo_rds))
cat("\n✅ PROCESSO CONCLUÍDO COM SUCESSO!\n")