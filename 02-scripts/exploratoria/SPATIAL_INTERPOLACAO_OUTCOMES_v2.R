# ============================================================
# INTERPOLAÇÃO ESPACIAL DE OUTCOMES HISTÓRICOS — v2
# ============================================================
# Correções em relação à v1:
#   1. IDW feito em escala LOG para variáveis totalmente positivas
#      (PIB e população têm distribuições extremamente assimétricas;
#       interpolação em nível é dominada por outliers grandes)
#   2. Back-transform com exp() após IDW
#   3. Variáveis com negativos no dado original → IDW em nível
#      (não é possível logar; negativos vêm do dado bruto, não da interpolação)
#   4. Leave-one-out cross-validation para reportar RMSE por variável
# ============================================================

library(sf)
library(sp)
library(tidyverse)
library(gstat)

setwd("C:/Users/André Elias/Documents/Pesquisa (Ferrovias)")
sf_use_s2(FALSE)

# ---- 1. CARREGAR DADOS --------------------------------------------------------
# Nota: amcs_geometria.rds na raiz do projeto e outcomes_amc_wide.rds
# já contêm somente as AMCs do Nordeste (1323 AMCs) — não precisa filtrar.
cat("Carregando geometrias das AMCs do Nordeste...\n")
amcs_ne <- readRDS("amcs_geometria.rds")

cat("Carregando outcomes brutos (antes da interpolação)...\n")
outcomes_ne <- readRDS("01-dados/processados/outcomes/outcomes_amc_wide.rds")

cat(sprintf("AMCs no Nordeste: %d\n", nrow(amcs_ne)))
cat(sprintf("AMCs em outcomes_wide: %d\n", nrow(outcomes_ne)))

# ---- 2. JUNTAR GEOMETRIA + OUTCOMES ------------------------------------------
base_sf <- amcs_ne |> inner_join(outcomes_ne, by = "code_amc")

# ---- 4. CENTROIDES EM UTM 24S ------------------------------------------------
cat("Calculando centroides em UTM...\n")
base_utm <- st_transform(base_sf, crs = 31984)
base_utm$centroide <- st_centroid(base_utm)
base_pontos <- base_utm |>
  mutate(
    x = st_coordinates(centroide)[, 1],
    y = st_coordinates(centroide)[, 2]
  ) |>
  st_drop_geometry() |>
  select(code_amc, x, y, everything())

cat(sprintf("%d AMCs com coordenadas UTM\n", nrow(base_pontos)))

# ---- 5. IDENTIFICAR COLUNAS COM NA -------------------------------------------
cols_numericas <- setdiff(names(base_pontos), c("code_amc", "x", "y", "centroide"))

cols_com_na <- cols_numericas[sapply(cols_numericas, function(col) {
  vals <- base_pontos[[col]]
  any(is.na(vals) | is.nan(vals) | is.infinite(vals))
})]

cat(sprintf("\nColunas com NAs para interpolar: %d\n", length(cols_com_na)))
for (col in cols_com_na) {
  n_na  <- sum(is.na(base_pontos[[col]]))
  n_neg <- sum(base_pontos[[col]] < 0, na.rm = TRUE)
  flag  <- if (n_neg > 0) sprintf(" ⚠ %d negativos no dado original", n_neg) else ""
  cat(sprintf("  %-30s %d NAs%s\n", col, n_na, flag))
}

# ---- 6. FUNÇÃO IDW COM OPÇÃO DE ESCALA LOG -----------------------------------
# idp = 2 (padrão), nmax = 15 vizinhos
# Se use_log = TRUE: interpola log(val) e back-transforma com exp()
# Se use_log = FALSE: interpola em nível

idw_interpolar <- function(col, base_pontos, use_log, idp = 2, nmax = 15) {

  obs <- base_pontos |>
    filter(!is.na(.data[[col]]) & !is.nan(.data[[col]]) & !is.infinite(.data[[col]]))

  if (nrow(obs) < 10) return(list(valores = NULL, loo_rmse = NA, escala = NA))

  amcs_com_na <- base_pontos |>
    filter(is.na(.data[[col]])) |>
    select(code_amc, x, y)

  if (nrow(amcs_com_na) == 0) return(list(valores = NULL, loo_rmse = NA, escala = "sem_nas"))

  # Escolhe escala
  escala <- if (use_log) "log" else "nivel"

  if (use_log) {
    obs <- obs |> mutate(.val_idw = log(.data[[col]]))
  } else {
    obs <- obs |> mutate(.val_idw = .data[[col]])
  }

  sp_obs <- obs |> select(x, y, .val_idw)
  coordinates(sp_obs) <- ~ x + y
  proj4string(sp_obs) <- CRS(st_crs(31984)$proj4string)

  # ---- Leave-one-out CV ----
  loo_pred <- numeric(nrow(obs))
  for (i in seq_len(nrow(obs))) {
    sp_train <- sp_obs[-i, ]
    sp_test  <- sp_obs[i, ]
    tryCatch({
      pred_i <- idw(
        formula  = .val_idw ~ 1,
        locations = sp_train,
        newdata   = sp_test,
        idp = idp, nmax = nmax
      )
      loo_pred[i] <- pred_i$var1.pred
    }, error = function(e) { loo_pred[i] <<- NA })
  }
  obs_vals <- obs$.val_idw
  loo_resid <- obs_vals - loo_pred
  loo_rmse_escala <- sqrt(mean(loo_resid^2, na.rm = TRUE))

  # Converte RMSE para escala original se log
  if (use_log) {
    # RMSE em log é difícil de interpretar diretamente;
    # calculamos também o RMSE em nível usando médias geométricas
    loo_rmse <- sqrt(mean((exp(obs_vals) - exp(loo_pred))^2, na.rm = TRUE))
    loo_rmse_relativo <- sqrt(mean(((exp(obs_vals) - exp(loo_pred)) / exp(obs_vals))^2, na.rm = TRUE))
  } else {
    loo_rmse <- loo_rmse_escala
    loo_rmse_relativo <- sqrt(mean((loo_resid / obs_vals)^2, na.rm = TRUE))
  }

  # ---- Interpolação pontual nos NAs ----
  sp_na <- amcs_com_na
  coordinates(sp_na) <- ~ x + y
  proj4string(sp_na) <- CRS(st_crs(31984)$proj4string)

  idw_result <- idw(
    formula   = .val_idw ~ 1,
    locations = sp_obs,
    newdata   = sp_na,
    idp = idp, nmax = nmax
  )

  pred_vals <- idw_result$var1.pred

  if (use_log) pred_vals <- exp(pred_vals)

  valores_interp <- amcs_com_na |>
    mutate(valor_interp = pred_vals) |>
    select(code_amc, valor_interp)

  list(
    valores       = valores_interp,
    loo_rmse      = loo_rmse,
    loo_rmse_rel  = loo_rmse_relativo,
    escala        = escala
  )
}

# ---- 7. INTERPOLAR CADA COLUNA -----------------------------------------------
cat("\n--- Iniciando interpolação ---\n")

base_interp  <- base_pontos
resumo_cv    <- list()

for (i in seq_along(cols_com_na)) {
  col <- cols_com_na[i]
  cat(sprintf("\n[%d/%d] %s ... ", i, length(cols_com_na), col))

  vals_obs <- base_pontos[[col]]
  n_neg    <- sum(vals_obs < 0, na.rm = TRUE)
  n_zero   <- sum(vals_obs == 0, na.rm = TRUE)
  n_na     <- sum(is.na(vals_obs))

  # Define escala: log se todos os observados são positivos
  use_log <- (n_neg == 0 & n_zero == 0)
  escala_label <- if (use_log) "LOG" else "NÍVEL"
  cat(sprintf("[escala: %s] ", escala_label))

  resultado <- idw_interpolar(col, base_pontos, use_log = use_log)

  if (!is.null(resultado$valores) && resultado$escala != "sem_nas") {
    map_interp <- resultado$valores

    # Substitui apenas os NAs
    na_idx <- which(is.na(base_interp[[col]]))
    for (idx in na_idx) {
      amc_code  <- base_interp$code_amc[idx]
      match_val <- map_interp$code_amc == amc_code
      if (any(match_val)) {
        base_interp[[col]][idx] <- map_interp$valor_interp[match_val][1]
      }
    }

    cat(sprintf(
      "OK | LOO-RMSE relativo = %.1f%%",
      resultado$loo_rmse_rel * 100
    ))
  } else {
    cat("sem NAs ou dados insuficientes")
  }

  resumo_cv[[col]] <- tibble(
    variavel      = col,
    n_na_original = n_na,
    n_negativos   = n_neg,
    escala        = escala_label,
    loo_rmse      = resultado$loo_rmse,
    loo_rmse_rel  = resultado$loo_rmse_rel
  )
}

# ---- 8. RESUMO CV ------------------------------------------------------------
cat("\n\n=== RESUMO DA QUALIDADE DA INTERPOLAÇÃO (Leave-One-Out CV) ===\n")

tabela_cv <- bind_rows(resumo_cv) |>
  mutate(loo_rmse_rel_pct = round(ifelse(is.na(loo_rmse_rel), NA, loo_rmse_rel * 100), 1)) |>
  select(variavel, n_na_original, n_negativos, escala, loo_rmse_rel_pct)

print(tabela_cv, n = nrow(tabela_cv))

# ---- 9. NAs REMANESCENTES ---------------------------------------------------
cat("\nNAs remanescentes após interpolação:\n")
for (col in cols_com_na) {
  depois <- sum(is.na(base_interp[[col]]))
  if (depois > 0) cat(sprintf("  ⚠ %s: %d NAs restantes\n", col, depois))
}
cat("  (sem listagem = zero NAs)\n")

# ---- 10. SALVAR --------------------------------------------------------------
cat("\nSalvando resultados...\n")

dir.create("01-dados/processados/outcomes/interpolados", showWarnings = FALSE, recursive = TRUE)

write.csv(base_interp,
  "01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.csv",
  row.names = FALSE)

saveRDS(base_interp,
  "01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.rds")

write.csv(tabela_cv,
  "01-dados/processados/outcomes/interpolados/resumo_cv_interpolacao.csv",
  row.names = FALSE)

cat("\n========================================\n")
cat("   INTERPOLAÇÃO v2 CONCLUÍDA\n")
cat("========================================\n")
cat(sprintf("AMCs Nordeste: %d\n", nrow(base_interp)))
cat(sprintf("Colunas interpoladas: %d\n", length(cols_com_na)))
cat("Arquivos gerados:\n")
cat("  - outcomes_amc_ne_interpolado.csv / .rds\n")
cat("  - resumo_cv_interpolacao.csv\n")
cat("========================================\n")
