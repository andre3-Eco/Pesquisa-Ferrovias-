# ============================================================
# INTERPOLAÇÃO ESPACIAL DE OUTCOMES HISTÓRICOS (pré-1970)
# ============================================================
# Objetivo: Preencher NAs em variáveis de PIB e população
# para AMCs do Nordeste usando Inverse Distance Weighting (IDW)
# e gerar mapas de calor para validação visual.
# ============================================================

library(sf)
library(sp)
library(tidyverse)
library(gstat)
library(viridis)
library(patchwork)

# ---- CONFIGURAÇÃO ----
setwd("C:/Users/André Elias/Documents/Pesquisa (Ferrovias)")

# ---- 1. CARREGAR DADOS ----
cat("Carregando geometrias das AMCs...\n")
amcs_geo <- readRDS("amcs_geometria.rds")

cat("Carregando outcomes...\n")
outcomes <- readRDS("01-dados/processados/outcomes/outcomes_amc_wide.rds")

# ---- 2. FILTRAR NORDESTE (código da AMC começa com 2) ----
cat("Filtrando AMCs do Nordeste...\n")
amcs_ne <- amcs_geo %>%
  filter(substr(as.character(code_amc), 1, 1) == "2")

outcomes_ne <- outcomes %>%
  filter(substr(as.character(code_amc), 1, 1) == "2")

cat(sprintf("AMCs no Nordeste: %d\n", nrow(amcs_ne)))

# ---- 3. JUNTAR GEOMETRIA + OUTCOMES ----
cat("Unindo geometria com outcomes...\n")
base_sf <- amcs_ne %>%
  inner_join(outcomes_ne, by = "code_amc")

# ---- 4. CALCULAR CENTROIDES (em UTM para distâncias em metros) ----
cat("Calculando centroides em UTM...\n")
# EPSG:31984 = UTM zona 24S (abrange o Nordeste)
base_utm <- st_transform(base_sf, crs = 31984)
base_utm$centroide <- st_centroid(base_utm)
base_pontos <- base_utm %>%
  mutate(
    x = st_coordinates(centroide)[, 1],
    y = st_coordinates(centroide)[, 2]
  ) %>%
  st_drop_geometry() %>%
  select(code_amc, x, y, everything())

cat(sprintf("%d AMCs com coordenadas UTM\n", nrow(base_pontos)))

# ---- 5. IDENTIFICAR COLUNAS COM NA ----
# Pega colunas de pib_*, pop_*, pibag_*, pibi_*, pibse_*, pibg_*
# que tenham pelo menos 1 NA (excluindo code_amc, x, y)
cols_numericas <- setdiff(names(base_pontos), c("code_amc", "x", "y", "centroide"))

cols_com_na <- c()
for (col in cols_numericas) {
  vals <- base_pontos[[col]]
  if (any(is.na(vals) | is.nan(vals) | is.infinite(vals))) {
    cols_com_na <- c(cols_com_na, col)
  }
}

cat(sprintf("\nColunas com NAs encontradas: %d\n", length(cols_com_na)))
for (col in cols_com_na) {
  na_count <- sum(is.na(base_pontos[[col]]))
  cat(sprintf("  %s: %d NAs\n", col, na_count))
}

# ---- 6. Grade Regular para Interpolação (grid espacial para mapas) ----
cat("\nCriando grade regular para interpolação...\n")
x_range <- range(base_pontos$x, na.rm = TRUE)
y_range <- range(base_pontos$y, na.rm = TRUE)

# Aumenta um pouco o bounding box
x_pad <- diff(x_range) * 0.05
y_pad <- diff(y_range) * 0.05

grid <- expand.grid(
  x = seq(x_range[1] - x_pad, x_range[2] + x_pad, length.out = 200),
  y = seq(y_range[1] - y_pad, y_range[2] + y_pad, length.out = 200)
)
coordinates(grid) <- ~ x + y
proj4string(grid) <- CRS(st_crs(31984)$proj4string)

# ---- 7. INTERPOLAR CADA COLUNA COM NA ----
resultados_interp <- base_pontos %>% select(code_amc, x, y)
dir.create("03-resultados/graficos/interpolacao", showWarnings = FALSE, recursive = TRUE)
dir.create("01-dados/processados/outcomes/interpolados", showWarnings = FALSE, recursive = TRUE)

plot_list <- list()

for (i in seq_along(cols_com_na)) {
  col <- cols_com_na[i]
  cat(sprintf("\n[%d/%d] Interpolando: %s ... ", i, length(cols_com_na), col))
  
  # Pega valores observados (sem NA)
  obs <- base_pontos %>%
    filter(!is.na(.data[[col]]) & !is.nan(.data[[col]]) & !is.infinite(.data[[col]]))
  
  if (nrow(obs) < 10) {
    cat(sprintf("APENAS %d observações — pulando.\n", nrow(obs)))
    next
  }
  
  # Prepara dados espaciais para IDW
  sp_obs <- obs
  coordinates(sp_obs) <- ~ x + y
  proj4string(sp_obs) <- CRS(st_crs(31984)$proj4string)
  
  # IDW interpolation
  # Use power parameter 2 (default)
  idw_result <- idw(
    formula = as.formula(paste0("`", col, "` ~ 1")),
    locations = sp_obs,
    newdata = grid,
    idp = 2,
    nmax = 15
  )
  
  # Extrair predição do grid interpolado
  pred <- as.data.frame(idw_result)
  
  # Para cada AMC com NA, pegar o valor do grid no ponto do centroide
  amcs_com_na <- base_pontos %>%
    filter(is.na(.data[[col]])) %>%
    select(code_amc, x, y)
  
  if (nrow(amcs_com_na) > 0) {
    # Interpolação pontual: pegar valores IDW nos pontos exatos
    sp_na <- amcs_com_na
    coordinates(sp_na) <- ~ x + y
    proj4string(sp_na) <- CRS(st_crs(31984)$proj4string)
    
    idw_pontual <- idw(
      formula = as.formula(paste0("`", col, "` ~ 1")),
      locations = sp_obs,
      newdata = sp_na,
      idp = 2,
      nmax = 15
    )
    
    valores_interp <- amcs_com_na %>%
      mutate(var1.pred = idw_pontual$var1.pred) %>%
      select(code_amc, var1.pred)
    
    resultados_interp <- resultados_interp %>%
      left_join(valores_interp %>% rename_with(~ paste0(col, "_interp"), .cols = var1.pred), by = "code_amc")
  }
  
  # ---- HEAT MAP: Observado vs Interpolado ----
  # Dados observados
  df_obs <- as.data.frame(sp_obs)
  
  # Usar base_sf original para o fundo de polígonos (mapa base)
  base_utm_sf <- base_utm %>% select(code_amc)
  
  # Cortar grid para o bounding box das AMCs do NE
  p1 <- ggplot() +
    geom_sf(data = base_utm_sf, fill = "gray95", color = "gray70", size = 0.2) +
    geom_point(data = df_obs, aes(x = x, y = y, color = .data[[col]]), size = 1.2) +
    scale_color_viridis_c(option = "H", name = "Observado") +
    labs(
      title = paste0(col, " — Observado"),
      subtitle = sprintf("%d AMCs com dados", nrow(obs))
    ) +
    theme_minimal() +
    theme(legend.position = "right")
  
  p2 <- ggplot() +
    geom_sf(data = base_utm_sf, fill = "gray95", color = "gray70", size = 0.2) +
    geom_raster(data = pred, aes(x = x, y = y, fill = var1.pred)) +
    scale_fill_viridis_c(option = "H", name = "Interpolado") +
    geom_point(data = df_obs, aes(x = x, y = y), color = "black", size = 0.5, alpha = 0.4) +
    labs(
      title = paste0(col, " — Interpolado (IDW)"),
      subtitle = sprintf("%d AMCs interpoladas via IDW", nrow(amcs_com_na))
    ) +
    theme_minimal() +
    theme(legend.position = "right")
  
  combined <- p1 + p2 + plot_layout(ncol = 2, guides = "collect")
  ggsave(
    sprintf("03-resultados/graficos/interpolacao/heatmap_%s.png", col),
    combined,
    width = 16, height = 7, dpi = 150
  )
  
  cat(sprintf("OK → heatmap salvo\n", col))
}

# ---- 8. CRIAR BASE INTERPOLADA ----
cat("\n--- Criando base interpolada final ---\n")

# Substituir NAs originais pelos valores interpolados
base_interp <- base_pontos

for (col in cols_com_na) {
  interp_col <- paste0(col, "_interp")
  if (interp_col %in% names(resultados_interp)) {
    # Pega mapeamento: code_amc -> valor interpolado
    map_interp <- resultados_interp %>%
      select(code_amc, !!sym(interp_col)) %>%
      filter(!is.na(!!sym(interp_col)))
    
    # Apenas substitui onde era NA
    na_idx <- which(is.na(base_interp[[col]]))
    
    for (idx in na_idx) {
      amc_code <- base_interp$code_amc[idx]
      match_val <- map_interp$code_amc == amc_code
      if (any(match_val)) {
        base_interp[[col]][idx] <- map_interp[[interp_col]][match_val][1]
      }
    }
  }
}

# Contar quantos NAs foram preenchidos
cat(sprintf("\nResumo pós-interpolação:\n"))
for (col in cols_com_na) {
  antes <- sum(is.na(base_pontos[[col]]))
  depois <- sum(is.na(base_interp[[col]]))
  preenchidos <- antes - depois
  if (antes > 0) {
    cat(sprintf("  %s: %d → %d NAs (%d preenchidos)\n", col, antes, depois, preenchidos))
  }
}

# ---- 9. SALVAR RESULTADOS ----
cat("\nSalvando resultados...\n")

# 9a. Base completa interpolada (só AMCs NE)
write.csv(base_interp,
  "01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.csv",
  row.names = FALSE
)
saveRDS(base_interp,
  "01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.rds"
)

# 9b. Base wide original + colunas interpoladas (para join futuro)
write.csv(resultados_interp,
  "01-dados/processados/outcomes/interpolados/valores_interpolados_por_amc.csv",
  row.names = FALSE
)

# ---- 10. RELATÓRIO FINAL ----
cat("\n========================================\n")
cat("   INTERPOLAÇÃO CONCLUÍDA\n")
cat("========================================\n")
cat(sprintf("AMCs do Nordeste: %d\n", nrow(base_interp)))
cat(sprintf("Colunas com NAs originais: %d\n", length(cols_com_na)))
cat(sprintf("Heatmaps salvos em: 03-resultados/graficos/interpolacao/\n"))
cat(sprintf("Base interpolada: 01-dados/processados/outcomes/interpolados/\n"))
cat("\nArquivos gerados:\n")
cat("  - outcomes_amc_ne_interpolado.csv / .rds\n")
cat("  - valores_interpolados_por_amc.csv\n")
cat("  - heatmap_*.png (para cada coluna)\n")
cat("========================================\n")