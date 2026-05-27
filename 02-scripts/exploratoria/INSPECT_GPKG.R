library(sf)

# Check the GPKG file
gpkg_path <- "C:/Users/André Elias/Documents/Pesquisa (Ferrovias)/05-geometrias/Rotas_LCP_OD_Real.gpkg"

cat("=== Inspecionando GPKG ===\n")
cat("Arquivo:", gpkg_path, "\n\n")

# List layers
layers <- st_layers(gpkg_path)
cat("Layers disponíveis:\n")
print(layers)
cat("\n")

# Read first layer
if (length(layers$name) > 0) {
  layer_name <- layers$name[1]
  cat("Lendo layer:", layer_name, "\n")
  
  data <- st_read(gpkg_path, layer = layer_name, quiet = TRUE)
  
  cat("Dimensões:", nrow(data), "linhas x", ncol(data), "colunas\n")
  cat("Tipo de geometria:", st_geometry_type(data), "\n")
  cat("CRS:", st_crs(data)$input, "\n\n")
  
  cat("Primeiras 6 linhas:\n")
  print(head(data))
  cat("\n")
  
  cat("Colunas disponíveis:\n")
  print(names(data))
  cat("\n")
  
  # Check for year column
  year_cols <- grep("ano|year|inaug|data", names(data), ignore.case = TRUE, value = TRUE)
  cat("Possíveis colunas de ano:\n")
  print(year_cols)
  cat("\n")
  
  if (length(year_cols) > 0) {
    for (col in year_cols) {
      cat(sprintf("Coluna '%s':\n", col))
      print(summary(data[[col]]))
      cat("\n")
    }
  }
}