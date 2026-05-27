# ==============================================================================
# SEGUNDO ESTÁGIO: IMPACTO DE LONGO PRAZO (PERSISTÊNCIA HISTÓRICA)
# Variável Dependente: PIB de 2010 (Fixo)
# Tratamento: Dummy e Densidade Sintética ao longo dos anos (Iterativo)
# ==============================================================================

library(sf)
library(dplyr)
library(tidyverse)
library(fixest)
library(stringr)
library(readr)
library(spdep)

sf_use_s2(FALSE)
if (!exists("data.wd")) data.wd <- getwd()

cat("========================================================================\n")
cat("TESTE DE PERSISTÊNCIA: EFEITO DA FERROVIA HISTÓRICA NO PIB 2010\n")
cat("========================================================================\n\n")

# ------------------------------------------------------------------------------
# 1. CARREGAR DADOS
# ------------------------------------------------------------------------------
cat("1. Carregando dados...\n")
outcomes_interp <- read_csv("01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.csv", show_col_types = FALSE)
sintetica_cronologica <- readRDS("01-dados/processados/base_sintetica_cronologica.rds")
ctrl_clima <- readRDS("01-dados/processados/controles_clima_amcs_nordeste.rds")
ctrl_rios  <- readRDS("01-dados/processados/controles_rios_amcs_nordeste.rds")
ctrl_solo  <- readRDS("01-dados/processados/controles_solo_amcs_nordeste.rds")

# ------------------------------------------------------------------------------
# 2. PREPARAR GEOMETRIA, ÁREA E LAG ESPACIAL
# ------------------------------------------------------------------------------
cat("2. Calculando área e Defasagem Espacial...\n")

# Carregar mapa e garantir que é do Nordeste
amcs_geo <- readRDS("amcs_geometria.rds")
amcs_ne <- amcs_geo 
if (nrow(amcs_ne) == 0) amcs_ne <- amcs_geo %>% filter(substr(as.character(list_code_muni_2010), 1, 1) == "2")
if (nrow(amcs_ne) == 0) amcs_ne <- amcs_geo

# Converter para UTM e calcular área
amcs_ne_utm <- st_transform(amcs_ne, crs = 31984)
amcs_ne_utm$area_km2 <- as.numeric(st_area(amcs_ne_utm)) / 1000000

# Extrair a distância sintética do painel (ano mais recente)
dist_long <- sintetica_cronologica %>%
  select(code_amc, matches("^dist_rail_sintetica_\\d{4}$")) %>%
  pivot_longer(-code_amc, names_to = "year_str", values_to = "dist_val") %>%
  mutate(year = as.numeric(str_extract(year_str, "\\d{4}")))

max_year <- max(dist_long$year, na.rm = TRUE)
dist_sint_latest <- dist_long %>% filter(year == max_year) %>% select(code_amc, dist_val) %>% distinct()

# Acoplar distância e calcular matriz de vizinhança
amcs_ne_utm <- amcs_ne_utm %>% left_join(dist_sint_latest, by = "code_amc")
vizinhanza <- poly2nb(amcs_ne_utm, queen = TRUE)
pesos_w <- nb2listw(vizinhanza, style = "W", zero.policy = TRUE)

amcs_ne_utm$dist_sintetica_vizinhos <- lag.listw(pesos_w, amcs_ne_utm$dist_val, zero.policy = TRUE, NAOK = TRUE)

# ------------------------------------------------------------------------------
# 3. CONSOLIDAR BASE CROSS-SECTION MESTRE
# ------------------------------------------------------------------------------
cat("3. Consolidando base de dados mestre...\n")

df_reg <- amcs_ne_utm %>%
  st_drop_geometry() %>%
  # Selecionar apenas controles espaciais para evitar duplicatas
  select(code_amc, area_km2, dist_sintetica_vizinhos) %>%
  
  # Travar Y: PIB de 2010
  left_join(outcomes_interp %>% select(code_amc, pib_2010), by = "code_amc") %>%
  
  # Travar X: Painel sintético inteiro
  left_join(sintetica_cronologica, by = "code_amc") %>%
  
  # Travar Controles Covariados
  left_join(ctrl_clima %>% select(code_amc, bio_1, bio_12, bio_15), by = "code_amc") %>%
  left_join(ctrl_rios %>% select(code_amc, dist_rio_km, densidade_hidro_km_km2), by = "code_amc") %>%
  left_join(ctrl_solo %>% select(code_amc, pct_solo_latossolos, pct_solo_neossolos), by = "code_amc") %>%
  
  # Criar Efeito Fixo de Estado
  mutate(state_abbr = as.character(substr(code_amc, 1, 2))) %>%
  
  # Limpar .x e .y caso existam e filtrar NAs críticos do PIB
  rename_with(~ str_remove(., "\\.x$"), ends_with(".x")) %>%
  select(-ends_with(".y")) %>%
  filter(!is.na(pib_2010), pib_2010 > 0)

cat(sprintf("   Base gerada: %d AMCs válidas e %d variáveis.\n\n", nrow(df_reg), ncol(df_reg)))

# ------------------------------------------------------------------------------
# 4. LOOP DE REGRESSÕES ITERATIVAS NO TEMPO
# ------------------------------------------------------------------------------
cat("4. Rodando regressões...\n")

anos_disponiveis <- names(sintetica_cronologica) %>%
  str_subset("^dummy_atendida_sintetica_\\d{4}$") %>%
  str_extract("\\d{4}") %>%
  unique() %>% sort()

controls_str <- "dist_sintetica_vizinhos + area_km2 + bio_1 + bio_12 + bio_15 + dist_rio_km + densidade_hidro_km_km2 + pct_solo_latossolos + pct_solo_neossolos"
resultados <- list()

for (ano in anos_disponiveis) {
  
  col_dummy <- paste0("dummy_atendida_sintetica_", ano)
  col_dens  <- paste0("densidade_sintetica_", ano)
  
  if (!(col_dummy %in% names(df_reg))) next
  
  # Filtra amostra válida do ano específico
  df_ano <- df_reg %>% filter(!is.na(.data[[col_dummy]]), !is.na(.data[[col_dens]]))
  if (nrow(df_ano) < 10) next
  
  # Modelo 1: Dummy de Atendimento
  tryCatch({
    form_dummy <- as.formula(sprintf("log(pib_2010) ~ %s + %s | state_abbr", col_dummy, controls_str))
    modelo_dummy <- feols(form_dummy, data = df_ano, se = "hetero")
    
    resultados[[length(resultados) + 1]] <- tibble(
      ano_tratamento = ano,
      tratamento_tipo = "dummy",
      variavel_endogena = "log(pib_2010)",
      variavel_tratamento = col_dummy,
      coeficiente = coef(modelo_dummy)[[col_dummy]],
      erro_padrao = se(modelo_dummy)[[col_dummy]],
      t_estatistica = coef(modelo_dummy)[[col_dummy]] / se(modelo_dummy)[[col_dummy]],
      p_valor = 2 * (1 - pnorm(abs(coef(modelo_dummy)[[col_dummy]] / se(modelo_dummy)[[col_dummy]]))),
      r2 = as.numeric(fitstat(modelo_dummy, "r2")[[1]]),
      n_observacoes = nobs(modelo_dummy)
    )
  }, error = function(e) { cat(sprintf("\n[ERRO DUMMY %s]: %s\n", ano, e$message)) })
  
  # Modelo 2: Densidade Ferroviária
  tryCatch({
    form_dens <- as.formula(sprintf("log(pib_2010) ~ %s + %s | state_abbr", col_dens, controls_str))
    modelo_dens <- feols(form_dens, data = df_ano, se = "hetero")
    
    resultados[[length(resultados) + 1]] <- tibble(
      ano_tratamento = ano,
      tratamento_tipo = "densidade",
      variavel_endogena = "log(pib_2010)",
      variavel_tratamento = col_dens,
      coeficiente = coef(modelo_dens)[[col_dens]],
      erro_padrao = se(modelo_dens)[[col_dens]],
      t_estatistica = coef(modelo_dens)[[col_dens]] / se(modelo_dens)[[col_dens]],
      p_valor = 2 * (1 - pnorm(abs(coef(modelo_dens)[[col_dens]] / se(modelo_dens)[[col_dens]]))),
      r2 = as.numeric(fitstat(modelo_dens, "r2")[[1]]),
      n_observacoes = nobs(modelo_dens)
    )
  }, error = function(e) { cat(sprintf("\n[ERRO DENSIDADE %s]: %s\n", ano, e$message)) })
  
  cat(sprintf("\r  Processando ano de tratamento: %s", ano))
}

# ------------------------------------------------------------------------------
# 5. COMPILAR E SALVAR RESULTADOS
# ------------------------------------------------------------------------------
cat("\n\n5. Compilando tabela final...\n")

resultados_df <- bind_rows(resultados) %>%
  mutate(
    significancia = case_when(p_valor < 0.01 ~ "***", p_valor < 0.05 ~ "**", p_valor < 0.10 ~ "*", TRUE ~ ""),
    coeficiente_sig = sprintf("%+.4f%s", coeficiente, significancia)
  )

dir.create("03-resultados/csv", showWarnings = FALSE, recursive = TRUE)
output_file <- "03-resultados/csv/second_stage_persistencia_pib2010.csv"
write_csv(resultados_df, output_file)

cat("========================================================================\n")
cat("✓ CONCLUÍDO! Tabela de coeficientes salva em:", output_file, "\n")
cat("========================================================================\n")