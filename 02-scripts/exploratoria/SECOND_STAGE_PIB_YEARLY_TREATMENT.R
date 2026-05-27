# ==============================================================================
# SECOND-STAGE REGRESSIONS: PIB OVER TIME WITH YEARLY TREATMENTS
# Using interpolated PIB outcomes and synthetic railway treatments (dummy, density)
# For each year, estimate: PIB_{i,t} = β * Treatment_{i,t} + controls + state_FE + ε_{i,t}
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
cat("SECOND-STAGE: PIB OVER TIME WITH YEARLY TREATMENTS\n")
cat("(Using interpolated outcomes and synthetic railway treatments)\n")
cat("========================================================================\n\n")

# ------------------------------------------------------------------------------
# 1. LOAD INTERPOLATED OUTCOMES DATA
# ------------------------------------------------------------------------------
cat("1. Loading interpolated outcomes data...\n")
outcomes_interp <- read_csv("01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.csv")

cat(sprintf("   Loaded %d AMCs with %d columns\n", nrow(outcomes_interp), ncol(outcomes_interp)))

# ------------------------------------------------------------------------------
# 2. LOAD SYNTHETIC RAILWAY VARIABLES BY YEAR (from our previous script)
# ------------------------------------------------------------------------------
cat("2. Loading synthetic railway variables by year...\n")
sintetica_cronologica <- readRDS("01-dados/processados/base_sintetica_cronologica.rds")

cat(sprintf("   Loaded synthetic data: %d AMCs, %d columns\n", 
            nrow(sintetica_cronologica), ncol(sintetica_cronologica)))

# ------------------------------------------------------------------------------
# 3. PREPARE CONTROLS
# ------------------------------------------------------------------------------
cat("3. Preparing control variables...\n")

# Load AMC geometry for spatial lag
amcs_geo <- readRDS("amcs_geometria.rds")
amcs_ne <- amcs_geo 

# Project to UTM for spatial calculations
crs_proj <- 31984  # UTM 24S
amcs_ne_utm <- st_transform(amcs_ne, crs = crs_proj)

# Compute centroids and spatial lag of synthetic distance
amc_centroids <- st_centroid(amcs_ne_utm)


amcs_ne_utm_poly <- amcs_ne_utm  # already in UTM
vizinhanza <- poly2nb(amcs_ne_utm_poly, queen = TRUE)
pesos_w <- nb2listw(vizinhanza, style = "W", zero.policy = TRUE)

# We'll need the synthetic distance for the spatial lag
# Get it from the synthetic database
dist_sint_var <- names(sintetica_cronologica) %>% 
  str_subset("^dist_rail_sintetica_\\d{4}$") %>% 
  .[1]  # Get first one to know the pattern

if (length(dist_sint_var) == 0) {
  # Fallback: compute from base data if not in sintetica_cronologica
  cat("   Computing spatial lag from base data...\n")
  base_dist <- read_csv("01-dados/processados/base_distancias_amcs_nordeste_semmar.csv")
  
  # Usando left_join seguro ao invés de deframe()
  amcs_ne_utm <- amcs_ne_utm %>%
    left_join(base_dist %>% select(code_amc, dist_rail_sintetica_km), by = "code_amc")
  
  # Adicionando NAOK = TRUE para ignorar AMCs isoladas sem dados
  amcs_ne_utm$dist_sintetica_vizinhos <- lag.listw(pesos_w, 
                                                   amcs_ne_utm$dist_rail_sintetica_km, 
                                                   zero.policy = TRUE,
                                                   NAOK = TRUE)
} else {
  # Extract synthetic distance from our database
  dist_long <- sintetica_cronologica %>%
    select(code_amc, matches("^dist_rail_sintetica_\\d{4}$")) %>%
    pivot_longer(-code_amc, names_to = "year_str", values_to = "dist_val") %>%
    mutate(year = as.numeric(str_extract(year_str, "\\d{4}"))) %>%
    arrange(code_amc, year)
  
  # Let's use the most recent year available
  max_year <- max(dist_long$year, na.rm = TRUE)
  
  dist_sint_latest <- dist_long %>%
    filter(year == max_year) %>%
    select(code_amc, dist_val) %>%
    distinct() # Previne duplicações
  
  # Usando left_join seguro ao invés de deframe()
  amcs_ne_utm <- amcs_ne_utm %>%
    left_join(dist_sint_latest, by = "code_amc")
  
  # Adicionando NAOK = TRUE para a função não quebrar se houver NAs
  amcs_ne_utm$dist_sintetica_vizinhos <- lag.listw(pesos_w, 
                                                   amcs_ne_utm$dist_val, 
                                                   zero.policy = TRUE,
                                                   NAOK = TRUE)
}

# Load other controls
ctrl_clima <- readRDS("01-dados/processados/controles_clima_amcs_nordeste.rds")
ctrl_rios  <- readRDS("01-dados/processados/controles_rios_amcs_nordeste.rds")
ctrl_solo  <- readRDS("01-dados/processados/controles_solo_amcs_nordeste.rds")

cat("   Controls loaded.\n")

# ------------------------------------------------------------------------------
# 4. PREPARE OUTCOME DATA (PIB TOTAL) - RESHAPE TO LONG
# ------------------------------------------------------------------------------
cat("4. Preparing PIB outcome data (reshaping to long format)...\n")

# Identify PIB total columns (pib_XXXX)
pib_cols <- names(outcomes_interp) %>%
  str_subset("^pib_\\d{4}$") %>%
  sort()

cat(sprintf("   Found %d PIB total columns (from %s to %s)\n", 
            length(pib_cols), 
            pib_cols[1], 
            pib_cols[length(pib_cols)]))

# Reshape outcomes to long format
pib_long <- outcomes_interp %>%
  select(code_amc, all_of(pib_cols)) %>%
  pivot_longer(-code_amc, 
               names_to = "year_str", 
               values_to = "pib_total") %>%
  mutate(year = as.numeric(str_extract(year_str, "\\d{4}"))) %>%
  select(code_amc, year, pib_total) %>%
  arrange(code_amc, year)

cat(sprintf("   Reshaped to %d rows (AMC-year observations)\n", nrow(pib_long)))

# ------------------------------------------------------------------------------
# 5. PREPARE TREATMENT DATA (DUMMY AND DENSITY) - RESHAPE TO LONG
# ------------------------------------------------------------------------------
cat("5. Preparing treatment data (dummy and density, reshaping to long)...\n")

# Identify dummy and density columns in the synthetic database
dummy_cols <- names(sintetica_cronologica) %>%
  str_subset("^dummy_atendida_sintetica_\\d{4}$") %>%
  sort()

densidade_cols <- names(sintetica_cronologica) %>%
  str_subset("^densidade_sintetica_\\d{4}$") %>%
  sort()

cat(sprintf("   Found %d dummy columns and %d density columns\n", 
            length(dummy_cols), length(densidade_cols)))

# Reshape dummy to long
dummy_long <- sintetica_cronologica %>%
  select(code_amc, all_of(dummy_cols)) %>%
  pivot_longer(-code_amc, 
               names_to = "year_str", 
               values_to = "dummy_sintetica") %>%
  mutate(year = as.numeric(str_extract(year_str, "\\d{4}"))) %>%
  select(code_amc, year, dummy_sintetica) %>%
  arrange(code_amc, year)

# Reshape density to long
densidade_long <- sintetica_cronologica %>%
  select(code_amc, all_of(densidade_cols)) %>%
  pivot_longer(-code_amc, 
               names_to = "year_str", 
               values_to = "densidade_sintetica") %>%
  mutate(year = as.numeric(str_extract(year_str, "\\d{4}"))) %>%
  select(code_amc, year, densidade_sintetica) %>%
  arrange(code_amc, year)

# ------------------------------------------------------------------------------
# 6. JOIN ALL DATA
# ------------------------------------------------------------------------------
cat("6. Joining all data...\n")

# 1. Calcular a área real das AMCs em km2 usando a geometria UTM
amcs_ne_utm$area_km2 <- as.numeric(st_area(amcs_ne_utm)) / 1000000

# Start with PIB long format
panel_data <- pib_long %>%
  # Join treatment variables
  left_join(dummy_long, by = c("code_amc", "year")) %>%
  left_join(densidade_long, by = c("code_amc", "year")) %>%
  
  # Add geographic and control variables (AGORA COM area_km2)
  left_join(amcs_ne_utm %>% 
              select(code_amc, dist_sintetica_vizinhos, area_km2) %>% 
              st_drop_geometry(), 
            by = "code_amc") %>%
  
  left_join(ctrl_clima %>% select(code_amc, bio_1, bio_12, bio_15), by = "code_amc") %>%
  left_join(ctrl_rios %>% select(code_amc, dist_rio_km, densidade_hidro_km_km2), by = "code_amc") %>%
  left_join(ctrl_solo %>% select(code_amc, pct_solo_latossolos, pct_solo_neossolos), by = "code_amc") %>%
  
  # 2. Criar o Efeito Fixo de Estado (state_abbr) a partir dos 2 primeiros dígitos do código da AMC do IBGE
  mutate(state_abbr = as.character(substr(code_amc, 1, 2))) %>%
  
  # Filter out missing values in key variables
  filter(!is.na(pib_total),
         !is.na(dummy_sintetica),
         !is.na(densidade_sintetica),
         !is.na(dist_sintetica_vizinhos)) %>%
  arrange(code_amc, year)

cat(sprintf("   Final panel data: %d observations (%d AMCs × %d years)\n", 
            nrow(panel_data),
            length(unique(panel_data$code_amc)),
            length(unique(panel_data$year))))
# ------------------------------------------------------------------------------
# 7. RUN SECOND-STAGE REGRESSIONS FOR EACH YEAR
# ------------------------------------------------------------------------------
for (idx in seq_along(anos_disponiveis)) {
  ano <- anos_disponiveis[idx]
  
  # Progress indicator
  if (idx %% 10 == 0 || idx == 1 || idx == length(anos_disponiveis)) {
    cat(sprintf("   Processing year %d (%d/%d)...\n", ano, idx, length(anos_disponiveis)))
  }
  
  # Filter data for this year
  df_ano <- panel_data %>%
    filter(year == ano)
  
  if (nrow(df_ano) < 10) {
    next
  }
  
  # --- Regression 1: Dummy as treatment ---
  tryCatch({
    form_dummy <- as.formula(sprintf("pib_total ~ dummy_sintetica + %s | state_abbr", controls_str))
    modelo_dummy <- feols(form_dummy, data = df_ano, se = "cluster", cluster = ~code_amc)
    
    resultados[[length(resultados) + 1]] <- tibble(
      ano = ano,
      tratamento = "dummy",
      variavel_endogena = "pib_total",
      variavel_tratamento = "dummy_sintetica",
      coeficiente = coef(modelo_dummy)[["dummy_sintetica"]],
      erro_padrao = se(modelo_dummy)[["dummy_sintetica"]],
      t_estatistica = coef(modelo_dummy)[["dummy_sintetica"]] / se(modelo_dummy)[["dummy_sintetica"]],
      p_valor = 2 * (1 - pnorm(abs(coef(modelo_dummy)[["dummy_sintetica"]] / se(modelo_dummy)[["dummy_sintetica"]]))),
      r2 = as.numeric(fitstat(modelo_dummy, "r2")[[1]]), # <-- CORRIGIDO AQUI
      n_observacoes = nobs(modelo_dummy)
    )
  }, error = function(e) {
    cat(sprintf("     Error in dummy regression for year %d: %s\n", ano, e$message))
  })
  
  # --- Regression 2: Density as treatment ---
  tryCatch({
    form_dens <- as.formula(sprintf("pib_total ~ densidade_sintetica + %s | state_abbr", controls_str))
    modelo_dens <- feols(form_dens, data = df_ano, se = "cluster", cluster = ~code_amc)
    
    resultados[[length(resultados) + 1]] <- tibble(
      ano = ano,
      tratamento = "densidade",
      variavel_endogena = "pib_total",
      variavel_tratamento = "densidade_sintetica",
      coeficiente = coef(modelo_dens)[["densidade_sintetica"]],
      erro_padrao = se(modelo_dens)[["densidade_sintetica"]],
      t_estatistica = coef(modelo_dens)[["densidade_sintetica"]] / se(modelo_dens)[["densidade_sintetica"]],
      p_valor = 2 * (1 - pnorm(abs(coef(modelo_dens)[["densidade_sintetica"]] / se(modelo_dens)[["densidade_sintetica"]]))),
      r2 = as.numeric(fitstat(modelo_dens, "r2")[[1]]), # <-- CORRIGIDO AQUI
      n_observacoes = nobs(modelo_dens)
    )
  }, error = function(e) {
    cat(sprintf("     Error in density regression for year %d: %s\n", ano, e$message))
  })
}
# ------------------------------------------------------------------------------
# 8. COMPILE AND SAVE RESULTS
# ------------------------------------------------------------------------------
cat("8. Compiling results...\n")
resultados_df <- bind_rows(resultados)

# Add significance stars
resultados_df <- resultados_df %>%
  mutate(
    significancia = case_when(
      p_valor < 0.01 ~ "***",
      p_valor < 0.05 ~ "**",
      p_valor < 0.10 ~ "*",
      TRUE ~ ""
    ),
    coeficiente_sig = sprintf("%+.4f%s", coeficiente, significancia)
  )

# Save to CSV
output_file <- "03-resultados/csv/second_stage_pib_tratamentos_sinteticos_por_ano.csv"
write_csv(resultados_df, output_file)
cat(sprintf("   Results saved to: %s\n", output_file))

# ------------------------------------------------------------------------------
# 9. SUMMARY
# ------------------------------------------------------------------------------
cat("\n========================================\n")
cat("   SUMMARY\n")
cat("========================================\n")
cat(sprintf("Total regressions run: %d\n", nrow(resultados_df)))
cat(sprintf("Years: %d to %d (%d years)\n", 
            min(anos_disponiveis), max(anos_disponiveis), length(anos_disponiveis)))
cat(sprintf("Treatments: dummy, densidad (2 treatments per year)\n"))

# Check significance levels
sig_counts <- resultados_df %>%
  mutate(sig_level = case_when(
    p_valor < 0.01 ~ "p<0.01",
    p_valor < 0.05 ~ "p<0.05",
    p_valor < 0.10 ~ "p<0.10",
    TRUE ~ "ns"
  )) %>%
  count(tratamento, sig_level)

cat(sprintf("\nSignificance counts:\n"))
print(sig_counts)

# Show some descriptive stats
cat(sprintf("\nDescriptive statistics of coefficients:\n"))
for (trat in c("dummy", "densidade")) {
  subset <- resultados_df %>% filter(tratamento == trat)
  if (nrow(subset) > 0) {
    cat(sprintf("%s: mean=%+.4f, sd=%.4f, min=%+.4f, max=%+.4f\n",
                trat,
                mean(subset$coeficiente),
                sd(subset$coeficiente),
                min(subset$coeficiente),
                max(subset$coeficiente)))
  }
}

cat("\nDone.\n")