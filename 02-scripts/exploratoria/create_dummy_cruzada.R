# Script to create dummy indicating if AMC intersected by any railway line
# and merge into base integrada

library(sf)
library(dplyr)

# Paths
amcs_path <- "amcs_geometria.rds"
rail_path <- "05-geometrias/ferrovias_cronologicas.gpkg"
base_path <- "01-dados/processados/base_completa_integrada.rds"
output_path <- "01-dados/processados/base_completa_integrada_com_dummy_cruzada.rds"

# Load data
amcs <- readRDS(amcs_path)
rail <- st_read(rail_path, quiet = TRUE)

# Ensure same CRS
if (st_crs(amcs) != st_crs(rail)) {
  rail <- st_transform(rail, st_crs(amcs))
}

# Intersection: does each AMC geometry intersect any rail line?
intersects <- st_intersects(amcs, rail, sparse = FALSE) # returns logical matrix
dummy <- as.integer(rowSums(intersects) > 0) # 1 if any intersection

# Add dummy to amcs sf
amcs <- amcs %>%
  mutate(dummy_cruzada = dummy)

# Keep only code_amc and dummy for merging
dummy_df <- amcs %>% select(code_amc, dummy_cruzada) %>% st_drop_geometry()

# Load base integrada
base <- readRDS(base_path)

# Merge dummy into base by code_amc
base <- base %>%
  left_join(dummy_df, by = "code_amc")

# If any NAs (should not), set to 0
base <- base %>%
  mutate(dummy_cruzada = ifelse(is.na(dummy_cruzada), 0, dummy_cruzada))

# Save updated base
saveRDS(base, output_path)
write.csv(base, gsub("\\.rds$", ".csv", output_path), row.names = FALSE)

# Print summary
cat("Dummy created: dummy_cruzada\n")
cat("Number of AMCs:", nrow(amcs), "\n")
cat("Number intersected:", sum(dummy), "(", round(mean(dummy)*100,1), "%)\n")
cat("Base integrada updated and saved to:", output_path, "\n")