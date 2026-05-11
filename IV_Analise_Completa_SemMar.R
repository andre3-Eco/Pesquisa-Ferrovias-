# ==============================================================================
# ANÁLISE IV COMPLETA — REDE SINTÉTICA LCP (SEM MAR)
# Três especificações:
#   1. Amostra completa
#   2. Restrita a AMCs ≤ 200 km das ferrovias reais
#   3. Restrita a ≤ 200 km e excluindo AMCs nas pontas das ferrovias
# ==============================================================================
# PRÉ-REQUISITO: o objeto `população` deve estar carregado na sessão.
#   Ele é usado para agregar população municipal ao nível de AMC.
# ==============================================================================
# ==============================================================================
# PRÉ-REQUISITO: o objeto `população` deve estar carregado na sessão.
#   Ele é usado para agregar população municipal ao nível de AMC.
# ==============================================================================

# 1. PACOTES -------------------------------------------------------------------
library(sf)
library(dplyr)
library(tidyverse)
library(geobr)
library(spdep)
library(lmtest)
library(sandwich)
library(fixest)

if (!exists("data.wd")) data.wd <- getwd()

sf_use_s2(FALSE)

# 2. CARREGAMENTO DOS DADOS ----------------------------------------------------

## 2a. Distâncias (rede sintética sem mar + redes reais cronológicas)
cat("Lendo base de distâncias...\n")
base_distancias <- read_csv(
  paste0(data.wd, "/base_distancias_amcs_nordeste_semmar.csv"),
  show_col_types = FALSE
)

## 2b. Ferrovias reais (para extrair pontas)
cat("Lendo ferrovias reais...\n")
ferrovias_reais <- st_read(
  paste0(data.wd, "/Dados pesquisa (Ferrovias)/ferrovias_cronologicas.gpkg"),
  quiet = TRUE
)

## 2c. Geometria das AMCs do Nordeste (via geobr)
cat("Baixando geometria das AMCs...\n")
amcs_geometria <- read_comparable_areas(start_year = 1970, end_year = 2010) |>
  filter(substr(list_code_muni_2010, 1, 1) == "2") |>
  distinct(code_amc, .keep_all = TRUE) |>
  st_make_valid() |>
  st_transform(31984)

## 2d. Dicionário AMC e agregação de população
cat("Agregando população municipal para AMCs...\n")
amc_lookup <- read_comparable_areas(start_year = 1970, end_year = 2010) |>
  st_drop_geometry() |>
  select(code_muni = list_code_muni_2010, code_amc) |>
  mutate(code_muni = as.character(code_muni))

pop_clean <- população |>
  rename(code_muni = `Cód.`) |>
  mutate(code_muni = as.character(code_muni))

pop_amc <- pop_clean |>
  inner_join(amc_lookup, by = "code_muni") |>
  group_by(code_amc) |>
  summarise(across(starts_with("20"), sum, na.rm = TRUE)) |>
  ungroup()

# 3. IDENTIFICAÇÃO DAS AMCs NAS PONTAS DAS FERROVIAS --------------------------
cat("Identificando AMCs nas pontas das ferrovias...\n")

# Pontos de INÍCIO: primeiro ponto do primeiro segmento de cada ferrovia
origens_pts <- ferrovias_reais |>
  group_by(id) |>
  filter(cod_part == min(cod_part)) |>
  ungroup() |>
  suppressWarnings(st_cast("POINT")) |>
  group_by(id) |>
  slice(1) |>
  ungroup() |>
  st_transform(31984)

# Pontos de FIM: último ponto do último segmento de cada ferrovia
destinos_pts <- ferrovias_reais |>
  group_by(id) |>
  filter(cod_part == max(cod_part)) |>
  ungroup() |>
  suppressWarnings(st_cast("POINT")) |>
  group_by(id) |>
  slice(n()) |>
  ungroup() |>
  st_transform(31984)

# AMCs que contêm pelo menos uma extremidade
extremidades <- bind_rows(
  origens_pts  |> select(id, Nome) |> mutate(tipo = "origem"),
  destinos_pts |> select(id, Nome) |> mutate(tipo = "destino")
)

codes_pontas <- st_join(
  amcs_geometria |> select(code_amc),
  extremidades,
  join = st_contains
) |>
  st_drop_geometry() |>
  filter(!is.na(id)) |>
  distinct(code_amc) |>
  pull(code_amc)

cat(sprintf("AMCs nas pontas das ferrovias: %d\n\n", length(codes_pontas)))

# 4. CONSTRUÇÃO DA BASE ANALÍTICA COMPLETA ------------------------------------
cat("Construindo base analítica...\n")

base_iv_sf <- amcs_geometria |>
  inner_join(pop_amc,       by = "code_amc") |>
  inner_join(base_distancias |> select(-starts_with("list")), by = "code_amc")

cat(sprintf("AMCs na base completa: %d\n", nrow(base_iv_sf)))

# 5. FUNÇÃO AUXILIAR: roda primeiro + segundo estágio -------------------------
rodar_iv <- function(dados, label) {

  cat(sprintf("\n%s\n", strrep("=", 70)))
  cat(sprintf("  ESPECIFICAÇÃO: %s  (N = %d AMCs)\n", label, nrow(dados)))
  cat(sprintf("%s\n", strrep("=", 70)))

  # --- Matriz de vizinhança e defasagem espacial ---
  vizinhos <- poly2nb(dados, queen = TRUE)
  pesos    <- nb2listw(vizinhos, style = "W", zero.policy = TRUE)

  dados$dist_sintetica_vizinhos <- lag.listw(
    pesos, dados$dist_rail_sintetica_km, zero.policy = TRUE
  )

  # --- Primeiro Estágio ---
  cat("\n--- PRIMEIRO ESTÁGIO ---\n")

  modelo_fs <- lm(
    dist_rail_real_2003 ~ dist_rail_sintetica_km + dist_sintetica_vizinhos,
    data = dados
  )

  vcov_hc   <- vcovHC(modelo_fs, type = "HC1")
  res_fs    <- coeftest(modelo_fs, vcov = vcov_hc)
  f_stat    <- waldtest(modelo_fs, vcov = vcov_hc)
  r2        <- summary(modelo_fs)$r.squared

  print(res_fs)
  cat(sprintf("\nTeste F conjunto: %.2f  |  R²: %.4f\n", f_stat$F[2], r2))

  # --- Segundo Estágio ---
  cat("\n--- SEGUNDO ESTÁGIO (IV-2SLS) ---\n")

  modelo_ss <- feols(
    log(`2003`) ~ dist_sintetica_vizinhos |
      dist_rail_real_2003 ~ dist_rail_sintetica_km,
    data = dados
  )

  print(summary(modelo_ss))

  # Retorna estatísticas pré-computadas para a tabela comparativa
  # fixest: coef() e pvalue() extraem diretamente do segundo estágio
  invisible(list(
    fs      = modelo_fs,
    ss      = modelo_ss,
    n       = nrow(dados),
    label   = label,
    beta_fs = res_fs["dist_rail_sintetica_km", "Estimate"],
    f_val   = f_stat$F[2],
    r2      = r2,
    beta_iv = coef(modelo_ss)["fit_dist_rail_real_2003"],
    pval_iv = pvalue(modelo_ss)["fit_dist_rail_real_2003"]
  ))
}

# 6. ESPECIFICAÇÃO 1: Amostra Completa ----------------------------------------
resultados_completa <- rodar_iv(base_iv_sf, "Amostra Completa")

# 7. ESPECIFICAÇÃO 2: Restrita a ≤ 200 km -------------------------------------
base_200km <- base_iv_sf |>
  filter(dist_rail_real_2003 <= 200)

resultados_200km <- rodar_iv(base_200km, "Amostra ≤ 200 km das ferrovias reais")

# 8. ESPECIFICAÇÃO 3: ≤ 200 km e sem pontas -----------------------------------
base_sem_pontas <- base_200km |>
  filter(!code_amc %in% codes_pontas)

cat(sprintf("\nAMCs excluídas (pontas dentro do raio): %d\n",
            nrow(base_200km) - nrow(base_sem_pontas)))

resultados_sem_pontas <- rodar_iv(
  base_sem_pontas,
  "Amostra ≤ 200 km, sem AMCs nas pontas das ferrovias"
)

# 9. TABELA COMPARATIVA -------------------------------------------------------
cat(sprintf("\n%s\n", strrep("=", 70)))
cat("  TABELA COMPARATIVA DOS RESULTADOS\n")
cat(sprintf("%s\n", strrep("=", 70)))

tabela <- map_dfr(
  list(resultados_completa, resultados_200km, resultados_sem_pontas),
  ~ tibble(
    Especificação       = .x$label,
    N                   = .x$n,
    `β sintético (1ºE)` = round(.x$beta_fs, 4),
    `F-stat`            = round(.x$f_val,   1),
    `R² (1ºE)`          = round(.x$r2,      3),
    `β IV (2ºE)`        = round(.x$beta_iv, 5),
    `p-valor (2ºE)`     = round(.x$pval_iv, 4)
  )
)

print(tabela, width = Inf)
