# ==============================================================================
# Etapa 14
# CRIAR BASE DE DENSIDADE FUTURA DE FERROVIAS (REAL E SINTÉTICA)
# Placebo In-Time — Lógica "Future Density"
# ==============================================================================
# Para cada ano T, calcula a densidade de ferrovias inauguradas APÓS T.
# Isso inverte a acumulação: quanto mais antigo o ano, maior a "densidade futura".
#
# Uso:
#   Esta base serve como tratamento/instrumento no teste de Placebo In-Time.
#   Se future_density_T predizer PIB_T, significa que lugares destinados a
#   receber ferrovias no futuro já eram mais prósperos antes — evidência de
#   endogeneidade no placement das ferrovias.
#
# Diferença em relação a base_buffer.R:
#   base_buffer.R:        filter(ano_inaug <= ano)   → acumulado até T
#
# Saída: base_densidade_buffer_future.csv / .rds
# ==============================================================================

library(sf)
library(tidyverse)


if (!exists("data.wd")) data.wd <- getwd()
sf_use_s2(FALSE)

# ------------------------------------------------------------------------------
# 1. CARREGAR DADOS GEOESPACIAIS
# ------------------------------------------------------------------------------
cat("Etapa 1: Carregando dados geoespaciais...\n")

amcs_nordeste        <- readRDS(paste0(data.wd, "/01-dados/processados/amcs_geometria.rds"))
ferrovias_reais      <- st_read(paste0(data.wd, "/05-geometrias/ferrovias_cronologicas.gpkg"),  quiet = TRUE)
ferrovias_sinteticas <- st_read(paste0(data.wd, "/05-geometrias/Rotas_LCP_OD_Real.gpkg"),       quiet = TRUE)

if (!"ano_inaug" %in% names(ferrovias_reais) || !"ano_inaug" %in% names(ferrovias_sinteticas)) {
  stop("ERRO: Coluna 'ano_inaug' ausente em uma das bases de ferrovia.")
}

# ------------------------------------------------------------------------------
# 2. PROJEÇÃO E ÁREAS BASE
# ------------------------------------------------------------------------------
cat("Etapa 2: Padronizando projeções e calculando áreas base...\n")

crs_projeto <- 31984

amcs_ne_utm          <- st_transform(amcs_nordeste,        crs = crs_projeto)
ferro_reais_utm      <- st_transform(ferrovias_reais,      crs = crs_projeto)
ferro_sinteticas_utm <- st_transform(ferrovias_sinteticas, crs = crs_projeto)

amcs_base <- amcs_ne_utm |>
  mutate(area_amc_km2 = as.numeric(st_area(amcs_ne_utm)) / 1e6) |>
  st_drop_geometry() |>
  select(code_amc, area_amc_km2)

# ------------------------------------------------------------------------------
# 3. ANOS DISPONÍVEIS
# ------------------------------------------------------------------------------
anos_disponiveis <- sort(unique(c(
  na.omit(ferro_reais_utm$ano_inaug),
  na.omit(ferro_sinteticas_utm$ano_inaug)
)))

# Exclui o último ano: não há ferrovias "futuras" após o ano máximo
ano_max <- max(anos_disponiveis)
anos_loop <- anos_disponiveis[anos_disponiveis < ano_max]

cat(sprintf("  Anos a processar: %d (%d a %d)\n",
            length(anos_loop), min(anos_loop), ano_max - 1))
cat(sprintf("  (Ano %d excluído: future density = 0 para todos)\n\n", ano_max))

# ------------------------------------------------------------------------------
# 4. FUNÇÃO DE DENSIDADE (idêntica ao base_buffer.R)
# ------------------------------------------------------------------------------
calcular_densidade <- function(ferrovias_filtradas, amcs_geo, base_areas) {
  if (nrow(ferrovias_filtradas) == 0) return(rep(0, nrow(base_areas)))

  malha_unida <- st_union(ferrovias_filtradas)
  buffer_5km  <- st_buffer(malha_unida, dist = 5000)
  intersecao  <- st_intersection(amcs_geo, buffer_5km)

  if (nrow(intersecao) == 0) return(rep(0, nrow(base_areas)))

  intersecao$area_intersecao_km2 <- as.numeric(st_area(intersecao)) / 1e6

  intersecao_areas <- intersecao |>
    st_drop_geometry() |>
    group_by(code_amc) |>
    summarise(area_intersecao_km2 = sum(area_intersecao_km2, na.rm = TRUE))

  base_areas |>
    left_join(intersecao_areas, by = "code_amc") |>
    mutate(
      area_intersecao_km2 = replace_na(area_intersecao_km2, 0),
      densidade = area_intersecao_km2 / area_amc_km2
    ) |>
    pull(densidade)
}

# ------------------------------------------------------------------------------
# 5. LOOP POR ANO — filtro invertido
# ------------------------------------------------------------------------------

lista_resultados <- list()

for (j in seq_along(anos_loop)) {
  ano <- anos_loop[j]

  # Ferrovias inauguradas APÓS T (lógica invertida)
  reais_futuras      <- ferro_reais_utm      |> filter(ano_inaug > ano)
  sinteticas_futuras <- ferro_sinteticas_utm |> filter(ano_inaug > ano)

  dens_real <- calcular_densidade(reais_futuras,      amcs_ne_utm, amcs_base)
  dens_sint <- calcular_densidade(sinteticas_futuras, amcs_ne_utm, amcs_base)

  df_ano <- data.frame(dens_real, dens_sint)
  colnames(df_ano) <- c(
    paste0("densidade_buffer_real_future_",      ano),
    paste0("densidade_buffer_sintetica_future_", ano)
  )

  lista_resultados[[as.character(ano)]] <- df_ano

  if (j %% 10 == 0 || j == length(anos_loop)) {
    cat(sprintf("  ✓ Ano %d (%d/%d) | real≠0: %d AMCs | sint≠0: %d AMCs\n",
                ano, j, length(anos_loop),
                sum(dens_real > 0), sum(dens_sint > 0)))
  }
}

# ------------------------------------------------------------------------------
# 6. CONSTRUIR E SALVAR BASE FINAL
# ------------------------------------------------------------------------------


base_final <- amcs_base |>
  bind_cols(bind_cols(lista_resultados))

output_dir <- paste0(data.wd, "/01-dados/processados")
write_csv(base_final, paste0(output_dir, "/base_densidade_buffer_future.csv"))
saveRDS(base_final,   paste0(output_dir, "/base_densidade_buffer_future.rds"))

