# ==============================================================================
# FIRST-STAGE REGRESSIONS: SYNTHETIC INSTRUMENT vs REAL ENDOGENOUS BY YEAR
# For each year and each treatment (distance, dummy, density), estimate:
#   real_Y ~ synthetic + controls + state_abbr
# and report the first-stage F-statistic (instrument strength).
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
cat("FIRST-STAGE: SYNTHETIC INSTRUMENT vs REAL ENDOGENOUS BY YEAR\n")
cat("========================================================================\n\n")

# ------------------------------------------------------------------------------
# 1. LOAD BASE DATA
# ------------------------------------------------------------------------------
cat("1. Loading base data...\n")
base <- read_csv("01-dados/processados/base_completa_integrada.csv")

# ------------------------------------------------------------------------------
# 2. LOAD AMC GEOMETRY (for spatial lag)
# ------------------------------------------------------------------------------
cat("2. Loading AMC geometry...\n")
amcs_geo <- readRDS("amcs_geometria.rds")

# Filter to Northeast (code_amc starts with "2")
amcs_ne <- amcs_geo %>%
  filter(substr(as.character(code_amc), 1, 1) == "2")

# ------------------------------------------------------------------------------
# 3. PREPARE CONTROLS
# ------------------------------------------------------------------------------
cat("3. Preparing controls...\n")

# 3a. Spatial lag of synthetic distance (need to compute)
# Project to UTM for distance calculations
crs_proj <- 31984  # UTM 24S
amcs_ne_utm <- st_transform(amcs_ne, crs = crs_proj)

# Compute centroids
amc_centroids <- st_centroid(amcs_ne_utm)

# Distance matrix (we'll use spdep or direct distance)
# For simplicity, we'll use k-nearest neighbors or distance band.
# But the existing scripts use queen contiguity. Let's replicate that.

amcs_ne_utm <- amcs_ne_utm %>%
  left_join(base %>% select(code_amc, dist_rail_sintetica_km), by = "code_amc")

# Queen contiguity
vizinhanza <- poly2nb(amcs_ne_utm, queen = TRUE)
pesos_w <- nb2listw(vizinhanza, style = "W", zero.policy = TRUE)

# Spatial lag of synthetic distance
amcs_ne_utm$dist_sintetica_vizinhos <- lag.listw(pesos_w, amcs_ne_utm$dist_rail_sintetica_km, zero.policy = TRUE)



# 3b. Load other controls (climate, rio, solo)
cat("   Loading control variables...\n")
ctrl_clima <- readRDS("01-dados/processados/controles_clima_amcs_nordeste.rds")
ctrl_rios  <- readRDS("01-dados/processados/controles_rios_amcs_nordeste.rds")
ctrl_solo  <- readRDS("01-dados/processados/controles_solo_amcs_nordeste.rds")

# Join controls to base
base <- base %>%
  left_join(amcs_ne_utm %>% select(code_amc, dist_sintetica_vizinhos), by = "code_amc") %>%
  left_join(ctrl_clima %>% select(code_amc, bio_1, bio_12, bio_15), by = "code_amc") %>%
  left_join(ctrl_rios %>% select(code_amc, dist_rio_km, densidade_hidro_km_km2), by = "code_amc") %>%
  left_join(ctrl_solo %>% select(code_amc, pct_solo_latossolos, pct_solo_neossolos), by = "code_amc")

# ------------------------------------------------------------------------------
# 4. IDENTIFY YEARS AND TREATMENTS
# ------------------------------------------------------------------------------
cat("4. Identifying available years and treatments...\n")

# Get all column names
cols <- colnames(base)

# Extract years for each type of real variable
years_dist <- cols %>%
  str_subset("^dist_rail_real_\\d{4}$") %>%
  str_extract("\\d{4}") %>%
  as.integer()

years_dummy <- cols %>%
  str_subset("^dummy_atendida_real_\\d{4}$") %>%
  str_extract("\\d{4}") %>%
  as.integer()

years_dens <- cols %>%
  str_subset("^densidade_real_\\d{4}$") %>%
  str_extract("\\d{4}") %>%
  as.integer()

# Use the intersection (should be same)
years <- sort(unique(c(years_dist, years_dummy, years_dens)))
cat(sprintf("   Found %d years: %d to %d\n", length(years), min(years), max(years)))

# Define treatments
tratamentos <- list(
  list(name = "Distancia", 
       real_prefix = "dist_rail_real_",
       synth = "dist_rail_sintetica_km",
       endo_sufix = ""),  # already in prefix
  list(name = "Dummy",
       real_prefix = "dummy_atendida_real_",
       synth = "dummy_atendida_sintetica",
       endo_sufix = ""),
  list(name = "Densidade",
       real_prefix = "densidade_real_",
       synth = "densidade_sintetica",
       endo_sufix = "")
)

# ------------------------------------------------------------------------------
# 5. LOOP OVER YEARS AND TREATMENTS
# ------------------------------------------------------------------------------
cat("5. Running first-stage regressions...\n")
resultados <- list()

for (ano in years) {
  for (trat in tratamentos) {
    # Construct variable names
    endo_var <- paste0(trat$real_prefix, ano)
    inst_var <- trat$synth  # synthetic is time-invariant
    
    # Check if variables exist
    if (!(endo_var %in% cols)) {
      next
    }
    if (!(inst_var %in% cols)) {
      next
    }
    
    # Prepare data for this regression
    df <- base %>%
      select(code_amc, 
             all_of(endo_var),
             all_of(inst_var),
             dist_sintetica_vizinhos,
             bio_1, bio_12, bio_15,
             dist_rio_km, densidade_hidro_km_km2,
             pct_solo_latossolos, pct_solo_neossolos,
             state_abbr) %>%
      filter(!is.na(.data[[endo_var]]),
             !is.na(.data[[inst_var]])) %>%
      # Also filter out infinite values
      filter(is.finite(.data[[endo_var]]),
             is.finite(.data[[inst_var]]))
    
    if (nrow(df) < 10) {
      next
    }
    
    # Formula: endo ~ inst + controls | state_abbr
    controls_str <- "dist_sintetica_vizinhos + bio_1 + bio_12 + bio_15 + dist_rio_km + densidade_hidro_km_km2 + pct_solo_latossolos + pct_solo_neossolos"
    form_str <- sprintf("%s ~ %s + %s | state_abbr", endo_var, inst_var, controls_str)
    
    tryCatch({
      modelo <- feols(as.formula(form_str), data = df, se = "hetero")
      
      # Extract instrument coefficient and stats
      coef_inst <- coef(modelo)[[inst_var]]
      se_inst   <- se(modelo)[[inst_var]]
      t_inst    <- coef_inst / se_inst
      p_inst    <- 2 * (1 - pnorm(abs(t_inst)))
      f_stat    <- t_inst^2  #in just-identified case, F = t^2
      
      resultados[[length(resultados) + 1]] <- tibble(
        ano = ano,
        tratamento = trat$name,
        variavel_endogena = endo_var,
        variavel_instrumento = inst_var,
        coeficiente = coef_inst,
        erro_padrao = se_inst,
        t_estatistica = t_inst,
        p_valor = p_inst,
        F_estatistica = f_stat,
        n_observacoes = nrow(df)
      )
      
    }, error = function(e) {
      cat(sprintf("  Error for year %d, treatment %s: %s\n", ano, trat$name, e$message))
    })
  }
  
  # Progress
  if (which(years == ano) %% 10 == 0) {
    cat(sprintf("  Processed year %d (%d/%d)\n", ano, which(years == ano), length(years)))
  }
}

# ------------------------------------------------------------------------------
# 6. COMPILE AND SAVE RESULTS
# ------------------------------------------------------------------------------
cat("6. Compiling results...\n")
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
output_file <- "03-resultados/csv/first_stage_sintetica_vs_real_por_ano.csv"
write_csv(resultados_df, output_file)
cat(sprintf("   Results saved to: %s\n", output_file))

# ------------------------------------------------------------------------------
# 7. SUMMARY
# ------------------------------------------------------------------------------
cat("\n========================================\n")
cat("   SUMMARY\n")
cat("========================================\n")
cat(sprintf("Total regressions run: %d\n", nrow(resultados_df)))
cat(sprintf("Years: %d to %d\n", min(years), max(years)))
cat(sprintf("Treatments: distance, dummy, density\n"))

# Check for weak instruments (F < 10)
weak <- resultados_df %>% filter(F_estatistica < 10)
cat(sprintf("Regressions with F-stat < 10 (weak instrument): %d\n", nrow(weak)))

if (nrow(weak) > 0) {
  cat("   Examples of weak instruments:\n")
  print(weak %>% select(ano, tratamento, F_estatistica) %>% head(5))
}

# Check for strong instruments (F > 10)
strong <- resultados_df %>% filter(F_estatistica >= 10)
cat(sprintf("Regressions with F-stat >= 10: %d\n", nrow(strong)))

cat("\nDone.\n")