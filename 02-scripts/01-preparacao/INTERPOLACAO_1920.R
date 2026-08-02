# ============================================================
# INTERPOLAÇÃO ESPACIAL DOS DADOS DE 1920
# Lógica baseada em INTERPOLACAO_OUTCOMES09.R
# ============================================================

library(sf)
library(sp)
library(tidyverse)
library(gstat)

# Configurar Diretório
setwd("C:/Users/André Elias/Documents/Pesquisa (Ferrovias)")
sf_use_s2(FALSE)

# ---- 1. CARREGAR DADOS E MAPEAMENTO ------------------------------------------
amcs_ne <- readRDS("amcs_geometria.rds")

df_1920 <- read_csv("01-dados/dados_1920_final_completo.csv", show_col_types = FALSE) |>
  rename(
    sabem_7a14 = `sabem(7a14)`,
    nsabem_7a14 = `nsabem(7a14)`,
    sabem_15a = `sabem(15a)`,
    nsabem_15a = `nsabem(15a)`
  )

amc_mapping <- amcs_ne |>
  st_drop_geometry() |>
  select(code_amc, list_code_muni_2010) |>
  separate_rows(list_code_muni_2010, sep = ",") |>
  mutate(code_muni = as.numeric(list_code_muni_2010))

df_amc <- df_1920 |>
  inner_join(amc_mapping, by = "code_muni") |>
  group_by(code_amc) |>
  summarise(
    sabem_7a14 = sum(sabem_7a14, na.rm = TRUE),
    nsabem_7a14 = sum(nsabem_7a14, na.rm = TRUE),
    sabem_15a = sum(sabem_15a, na.rm = TRUE),
    nsabem_15a = sum(nsabem_15a, na.rm = TRUE),
    numeroestabelecimento = sum(numeroestabelecimento, na.rm = TRUE),
    commaquinas = sum(commaquinas, na.rm = TRUE),
    cominstruagra = sum(cominstruagra, na.rm = TRUE),
    fabeofi = sum(fabeofi, na.rm = TRUE),
    casaneg = sum(casaneg, na.rm = TRUE),
    popu = sum(popu, na.rm = TRUE)
  )

# Junta geometria + AMCs, deixando NA nos AMCs que não têm dados de 1920
base_sf <- amcs_ne |> left_join(df_amc, by = "code_amc")

# ---- 2. CENTROIDES EM UTM 24S ------------------------------------------------
base_utm <- st_transform(base_sf, crs = 31984)
base_utm$centroide <- st_centroid(base_utm)
base_pontos <- base_utm |>
  mutate(
    x = st_coordinates(centroide)[, 1],
    y = st_coordinates(centroide)[, 2]
  ) |>
  st_drop_geometry() |>
  select(code_amc, x, y, sabem_7a14, nsabem_7a14, sabem_15a, nsabem_15a, numeroestabelecimento, commaquinas, cominstruagra, fabeofi, casaneg, popu)

cat(sprintf("%d AMCs com coordenadas UTM preparadas\n", nrow(base_pontos)))

# ---- 3. FUNÇÃO IDW COM LOO-CV ------------------------------------------------
idw_interpolar <- function(col, base_pontos, use_log, idp = 2, nmax = 15) {
  obs <- base_pontos |>
    filter(!is.na(.data[[col]]) & !is.nan(.data[[col]]) & !is.infinite(.data[[col]]))
  
  if (nrow(obs) < 10) return(list(valores = NULL, loo_rmse = NA, escala = NA))
  
  amcs_com_na <- base_pontos |>
    filter(is.na(.data[[col]])) |>
    select(code_amc, x, y)
  
  if (nrow(amcs_com_na) == 0) return(list(valores = NULL, loo_rmse = NA, escala = "sem_nas"))
  
  escala <- if (use_log) "log" else "nivel"
  
  if (use_log) {
    obs <- obs |> mutate(.val_idw = log(.data[[col]]))
  } else {
    obs <- obs |> mutate(.val_idw = .data[[col]])
  }
  
  sp_obs <- obs |> select(x, y, .val_idw)
  coordinates(sp_obs) <- ~ x + y
  proj4string(sp_obs) <- CRS(st_crs(31984)$proj4string)
  
  # Leave-one-out CV
  loo_pred <- numeric(nrow(obs))
  for (i in seq_len(nrow(obs))) {
    sp_train <- sp_obs[-i, ]
    sp_test  <- sp_obs[i, ]
    tryCatch({
      pred_i <- idw(
        formula  = .val_idw ~ 1,
        locations = sp_train,
        newdata   = sp_test,
        idp = idp, nmax = nmax, debug.level = 0
      )
      loo_pred[i] <- pred_i$var1.pred
    }, error = function(e) { loo_pred[i] <<- NA })
  }
  obs_vals <- obs$.val_idw
  loo_resid <- obs_vals - loo_pred
  loo_rmse_escala <- sqrt(mean(loo_resid^2, na.rm = TRUE))
  
  if (use_log) {
    loo_rmse <- sqrt(mean((exp(obs_vals) - exp(loo_pred))^2, na.rm = TRUE))
    loo_rmse_relativo <- sqrt(mean(((exp(obs_vals) - exp(loo_pred)) / exp(obs_vals))^2, na.rm = TRUE))
  } else {
    loo_rmse <- loo_rmse_escala
    loo_rmse_relativo <- sqrt(mean((loo_resid / obs_vals)^2, na.rm = TRUE))
  }
  
  # Interpolação pontual nos NAs
  sp_na <- amcs_com_na
  coordinates(sp_na) <- ~ x + y
  proj4string(sp_na) <- CRS(st_crs(31984)$proj4string)
  
  idw_result <- idw(
    formula   = .val_idw ~ 1,
    locations = sp_obs,
    newdata   = sp_na,
    idp = idp, nmax = nmax, debug.level = 0
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

# ---- 4. INTERPOLAR CADA VARIÁVEL ---------------------------------------------
cols_com_na <- c("sabem_7a14", "nsabem_7a14", "sabem_15a", "nsabem_15a", 
                 "numeroestabelecimento", "commaquinas", "cominstruagra",
                 "fabeofi", "casaneg", "popu")

base_interp <- base_pontos
resumo_cv   <- list()

cat("Iniciando Interpolação (IDW)...\n")
for (i in seq_along(cols_com_na)) {
  col <- cols_com_na[i]
  cat(sprintf("\n[%d/%d] %s ... ", i, length(cols_com_na), col))
  
  vals_obs <- base_pontos[[col]]
  n_neg    <- sum(vals_obs < 0, na.rm = TRUE)
  n_zero   <- sum(vals_obs == 0, na.rm = TRUE)
  n_na     <- sum(is.na(vals_obs))
  
  # Logica do projeto: se tem zeros, vai pra nivel em vez de log
  # Como a interpolação logaritmo quebra em zeros
  use_log <- (n_neg == 0 & n_zero == 0)
  escala_label <- if (use_log) "LOG" else "NÍVEL"
  cat(sprintf("[escala: %s] ", escala_label))
  
  resultado <- idw_interpolar(col, base_pontos, use_log = use_log)
  
  if (!is.null(resultado$valores) && resultado$escala != "sem_nas") {
    map_interp <- resultado$valores
    
    na_idx <- which(is.na(base_interp[[col]]))
    for (idx in na_idx) {
      amc_code  <- base_interp$code_amc[idx]
      match_val <- map_interp$code_amc == amc_code
      if (any(match_val)) {
        base_interp[[col]][idx] <- map_interp$valor_interp[match_val][1]
      }
    }
    
    cat(sprintf("OK | LOO-RMSE = %.2f", resultado$loo_rmse))
  } else {
    cat("sem NAs ou dados insuficientes")
  }
  
  resumo_cv[[col]] <- tibble(
    variavel      = col,
    n_na_original = n_na,
    escala        = escala_label,
    loo_rmse      = resultado$loo_rmse
  )
}
cat("\n\n")

# ---- 5. SALVAR ---------------------------------------------------------------
dir.create("01-dados/processados/outcomes/interpolados", showWarnings = FALSE, recursive = TRUE)

# Junta com a geometria novamente (opcional, aqui salvamos só os dados agregados + interpolados)
write.csv(base_interp,
          "01-dados/processados/outcomes/interpolados/dados_1920_amc_interpolado.csv",
          row.names = FALSE)

saveRDS(base_interp,
        "01-dados/processados/outcomes/interpolados/dados_1920_amc_interpolado.rds")

tabela_cv <- bind_rows(resumo_cv)
write.csv(tabela_cv,
          "01-dados/processados/outcomes/interpolados/resumo_cv_1920.csv",
          row.names = FALSE)

cat("Processo finalizado! Arquivos interpolados salvos em '01-dados/processados/outcomes/interpolados/'.\n")
