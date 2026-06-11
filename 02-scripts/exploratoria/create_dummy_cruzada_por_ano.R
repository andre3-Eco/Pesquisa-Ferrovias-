# Script to create yearly cumulative dummies indicating if AMC intersected by railway up to each year
# and merge into base integrada (wide format)

library(sf)
library(dplyr)

# Paths
amcs_path <- "amcs_geometria.rds"
rail_path <- "05-geometrias/ferrovias_cronologicas.gpkg"
base_path <- "01-dados/processados/base_completa_integrada.rds"
output_path <- "01-dados/processados/base_completa_integrada_com_dummy_cruzada_por_ano.rds"

# Load data
amcs <- readRDS(amcs_path)
rail <- st_read(rail_path, quiet = TRUE)

# Ensure same CRS
if (st_crs(amcs) != st_crs(rail)) {
  rail <- st_transform(rail, st_crs(amcs))
}

# Get unique years sorted
years <- sort(unique(rail$ano_inaug))
cat("Years range:", min(years), "-", max(years), "(n =", length(years), ")\n")

# Prepare result dataframe with code_amc
dummy_wide <- amcs %>% select(code_amc) %>% st_drop_geometry()

# Loop over years
for (y in years) {
  cat("Processing year", y, "... ")
  rail_up_to_y <- rail %>% filter(ano_inaug <= y)
  # Intersection
  intersects <- st_intersects(amcs, rail_up_to_y, sparse = FALSE) # logical matrix n_amcs x n_segments
  dummy <- as.integer(rowSums(intersects) > 0) # 1 if any intersection
  dummy_wide[[paste0("dummy_cruzada_", y)]] <- dummy
  cat("done\n")
}

# Merge with base integrada
base <- readRDS(base_path)
base <- base %>%
  left_join(dummy_wide, by = "code_amc")

# Save updated base
saveRDS(base, output_path)
write.csv(base, gsub("\\.rds$", ".csv", output_path), row.names = FALSE)

# Summary
cat("\nDummy variables created for years:", min(years), "to", max(years), "\n")
cat("Base integrada updated and saved to:", output_path, "\n")
# Show first few dummy columns
dummy_cols <- grep("^dummy_cruzada_", names(base), value = TRUE)
cat("Number of dummy columns:", length(dummy_cols), "\n")
if (length(dummy_cols) > 0) {
  cat("Example columns:", head(dummy_cols, 5), "\n")
}