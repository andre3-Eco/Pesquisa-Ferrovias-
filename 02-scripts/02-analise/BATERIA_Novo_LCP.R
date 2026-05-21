# ==============================================================================
# BATERIA IV — 4 ESCOPOS DE OUTCOMES 
# ==============================================================================
# Script : 9_Bateria_Novos_Outcomes_Sensibilidade_Pontas.R
#
# OBJETIVO:
#   Variar a amostra sistematicamente testando o efeito da exclusão das AMCs
#   localizadas nas extremidades das ferrovias históricas reais, utilizando
#   a lista previamente gerada (lista_amcs_pontas).
# ==============================================================================

library(sf)
library(dplyr)
library(spdep)
library(fixest)
library(tidyr)
library(readr)
library(stringr)

sf_use_s2(FALSE)

if (!exists("data.wd")) data.wd <- getwd()

cat("\n", strrep("=", 80), "\n")
cat("BATERIA IV — TESTE DE SENSIBILIDADE: EXCLUSÃO DE PONTAS\n")
cat("Data:", format(Sys.time(), "%d/%m/%Y %H:%M:%S"), "\n")
cat(strrep("=", 80), "\n\n")

# ==============================================================================
# SEÇÃO 1: CONSTRUIR BASE MESTRE
# ==============================================================================
cat("SEÇÃO 1: Carregando e integrando bases...\n")

base_completa <- read_csv("01-dados/processados/base_completa_integrada.csv")
base_iv_sf <- amcs_geometria |> inner_join(base_completa, by = "code_amc")

outcomes_wide <- readRDS("01-dados/processados/outcomes/outcomes_amc_wide.rds")

if (!exists("ctrl_clima")) ctrl_clima <- readRDS("01-dados/processados/controles_clima_amcs_nordeste.rds")
if (!exists("ctrl_rios"))  ctrl_rios  <- readRDS("01-dados/processados/controles_rios_amcs_nordeste.rds")
if (!exists("ctrl_solo"))  ctrl_solo  <- readRDS("01-dados/processados/controles_solo_amcs_nordeste.rds")

base_mestre <- base_iv_sf |>
  left_join(outcomes_wide, by = "code_amc") |>
  left_join(ctrl_clima |> select(code_amc, bio_1, bio_12, bio_15), by = "code_amc") |>
  left_join(ctrl_rios |> select(code_amc, dist_rio_km, densidade_hidro_km_km2), by = "code_amc") |>
  left_join(ctrl_solo |> select(code_amc, pct_solo_latossolos, pct_solo_neossolos, pct_solo_luvissolos, pct_solo_planossolos), by = "code_amc")

cat(sprintf("  ✓ Base mestre: %d AMCs × %d colunas\n\n", nrow(base_mestre), ncol(base_mestre)))

# ==============================================================================
# SEÇÃO 2: EXTRAIR AMCs DAS PONTAS VIA OBJETO 'lista_amcs_pontas'
# ==============================================================================
cat("SEÇÃO 2: Extraindo códigos de AMCs a partir de lista_amcs_pontas...\n")

if (!exists("lista_amcs_pontas")) stop("'lista_amcs_pontas' não encontrado no Environment.")

# Quebra a string "3001 e 3002" em um vetor limpo de IDs numéricos
codes_pontas_corr <- lista_amcs_pontas$amcs_codigo |>
  stringr::str_split(" e ") |>
  unlist() |>
  as.numeric() |>
  na.omit() |>
  unique() |>
  sort()

cat(sprintf("  Total de AMCs nas pontas identificadas para exclusão: %d\n\n", length(codes_pontas_corr)))

# ==============================================================================
# SEÇÃO 3: DEFINIR OUTCOMES 
# ==============================================================================
cat("SEÇÃO 3: Definindo outcomes...\n")

outcomes_config <- list(
  list(escopo = "1_PIB", nome = "pib_2000", coluna = "pib_2000", rotulo = "PIB Total (2000)", ano_trat = 1972, transf = "log"),
  list(escopo = "1_PIB", nome = "pib_2010", coluna = "pib_2010", rotulo = "PIB Total (2010)", ano_trat = 1985, transf = "log"),
  list(escopo = "1_PIB", nome = "pib_percapita_2000", coluna = "pib_percapita_2000", rotulo = "PIB per capita (2000)", ano_trat = 1972, transf = "log"),
  list(escopo = "1_PIB", nome = "pib_percapita_2010", coluna = "pib_percapita_2010", rotulo = "PIB per capita (2010)", ano_trat = 1985, transf = "log"),
  list(escopo = "2_Pop", nome = "pop_total_1991", coluna = "pop_total_1991", rotulo = "Pop. Total (1991)", ano_trat = 1969, transf = "log"),
  list(escopo = "2_Pop", nome = "pop_total_2000", coluna = "pop_total_2000", rotulo = "Pop. Total (2000)", ano_trat = 1972, transf = "log"),
  list(escopo = "2_Pop", nome = "pop_total_2010", coluna = "pop_total_2010", rotulo = "Pop. Total (2010)", ano_trat = 1985, transf = "log"),
  list(escopo = "2_Pop", nome = "tx_urban_2010", coluna = "tx_urbanizacao_2010", rotulo = "Taxa de Urbanização (2010)", ano_trat = 1985, transf = "nivel"),
  list(escopo = "3_PAM", nome = "valproducao_2000", coluna = "valor_producao_mil_reais_2000", rotulo = "Valor Prod. Agrícola (2000)", ano_trat = 1972, transf = "log"),
  list(escopo = "3_PAM", nome = "valproducao_2010", coluna = "valor_producao_mil_reais_2010", rotulo = "Valor Prod. Agrícola (2010)", ano_trat = 1985, transf = "log"),
  list(escopo = "4_Social", nome = "idhm_2000", coluna = "adh_idhm_2000", rotulo = "IDHM (2000)", ano_trat = 1972, transf = "nivel"),
  list(escopo = "4_Social", nome = "idhm_2010", coluna = "adh_idhm_2010", rotulo = "IDHM (2010)", ano_trat = 1985, transf = "nivel"),
  list(escopo = "4_Social", nome = "rdpc_2000", coluna = "adh_rdpc_2000", rotulo = "Renda per capita (2000)", ano_trat = 1972, transf = "log"),
  list(escopo = "4_Social", nome = "rdpc_2010", coluna = "adh_rdpc_2010", rotulo = "Renda per capita (2010)", ano_trat = 1985, transf = "log"),
  list(escopo = "4_Social", nome = "pmpob_2010", coluna = "adh_pmpob_2010", rotulo = "% Pobres (2010)", ano_trat = 1985, transf = "nivel")
)

# ==============================================================================
# SEÇÃO 4: DEFINIR ESPECIFICAÇÕES EM "ESPELHO"
# ==============================================================================
# A amostra (Toda vs. 200km) e a inclusão das pontas (Com vs. Sem).
# Mantemos o bloco de controles "Completo" constante para isolar a variação amostral.

cat("SEÇÃO 4: Definindo especificações de sensibilidade...\n\n")

ctrl_padrao <- "dist_sintetica_vizinhos + bio_1 + bio_12 + bio_15 + dist_rio_km + pct_solo_latossolos"

especificacoes <- list(
  list(
    nome = "1_AmostraTotal_ComPontas", rotulo = "Toda Amostra [COM Pontas]",
    filtro_200 = FALSE, excl_pontas = FALSE,
    fe_formula = "state_abbr", controles = ctrl_padrao, ctrl_tipo = "completo"
  ),
  list(
    nome = "2_AmostraTotal_SemPontas", rotulo = "Toda Amostra [SEM Pontas]",
    filtro_200 = FALSE, excl_pontas = TRUE,
    fe_formula = "state_abbr", controles = ctrl_padrao, ctrl_tipo = "completo"
  ),
  list(
    nome = "3_Amostra200km_ComPontas", rotulo = "Dist ≤200km [COM Pontas]",
    filtro_200 = TRUE, excl_pontas = FALSE,
    fe_formula = "state_abbr", controles = ctrl_padrao, ctrl_tipo = "completo"
  ),
  list(
    nome = "4_Amostra200km_SemPontas", rotulo = "Dist ≤200km [SEM Pontas]",
    filtro_200 = TRUE, excl_pontas = TRUE,
    fe_formula = "state_abbr", controles = ctrl_padrao, ctrl_tipo = "completo"
  )
)

# ==============================================================================
# SEÇÃO 5: FUNÇÃO DE ESTIMAÇÃO IV 
# ==============================================================================
estimar_iv <- function(df, endogena, instrumento, outcome_col, fe_formula, controles, transf, nome_esp, nome_trat, nome_out, nome_escopo, ano_trat) {
  tryCatch({
    df <- df |> dplyr::rename(Y = all_of(outcome_col))
    df <- df |> dplyr::filter(!is.na(.data[[endogena]]), !is.na(.data[[instrumento]]), !is.na(Y))
    if (transf == "log") df <- df |> dplyr::filter(Y > 0)
    
    n_obs <- nrow(df)
    if (n_obs < 30) stop("Amostra insuficiente (N < 30)")
    
    lhs <- if (transf == "log") "log(Y)" else "Y"
    parte_ctrl <- if (is.null(controles) || nchar(trimws(controles)) == 0) "1" else controles
    
    formula_iv <- if (fe_formula == "1") {
      as.formula(sprintf("%s ~ %s | %s ~ %s", lhs, parte_ctrl, endogena, instrumento))
    } else {
      as.formula(sprintf("%s ~ %s | %s | %s ~ %s", lhs, parte_ctrl, fe_formula, endogena, instrumento))
    }
    
    modelo <- feols(formula_iv, data = df, se = "hetero")
    nome_coef <- paste0("fit_", endogena)
    
    coef_ss <- coef(modelo)[nome_coef]
    se_ss   <- se(modelo)[nome_coef]
    t_ss    <- coef_ss / se_ss
    p_ss    <- 2 * (1 - pnorm(abs(t_ss)))
    
    fstat_obj <- fitstat(modelo, "ivf")[[1]]
    f_stat    <- if (is.list(fstat_obj)) fstat_obj$stat else as.numeric(fstat_obj)
    
    data.frame(
      escopo = nome_escopo, especificacao = nome_esp, tratamento = nome_trat, ano_trat = ano_trat, outcome = nome_out,
      transf = transf, n_obs = n_obs, coef_ss = coef_ss, se_ss = se_ss, t_stat = t_ss, p_value = p_ss, f_stat = f_stat,
      erro = NA_character_, stringsAsFactors = FALSE
    )
  }, error = function(e) {
    data.frame(escopo=nome_escopo, especificacao=nome_esp, tratamento=nome_trat, ano_trat=ano_trat, outcome=nome_out, transf=transf, n_obs=NA_integer_, coef_ss=NA_real_, se_ss=NA_real_, t_stat=NA_real_, p_value=NA_real_, f_stat=NA_real_, erro=e$message, stringsAsFactors=FALSE)
  })
}

# ==============================================================================
# SEÇÃO 6: EXECUTAR BATERIA
# ==============================================================================
cat(strrep("=", 80), "\n")
cat("EXECUTANDO BATERIA\n")
cat(strrep("=", 80), "\n\n")

cols_controles <- c("dist_sintetica_vizinhos", "bio_1", "bio_12", "bio_15", "dist_rio_km", "densidade_hidro_km_km2", "pct_solo_latossolos", "pct_solo_neossolos", "pct_solo_luvissolos", "pct_solo_planossolos")

resultados <- data.frame()
contador   <- 0L
n_total <- length(especificacoes) * length(outcomes_config) * 3

for (esp in especificacoes) {
  cat(sprintf("\n%s\n  ESPECIFICAÇÃO: %s\n%s\n", strrep("-", 60), esp$rotulo, strrep("-", 60)))
  
  for (out in outcomes_config) {
    ano_trat <- out$ano_trat
    col_dist <- paste0("dist_rail_real_", ano_trat)
    col_dummy <- paste0("dummy_atendida_real_", ano_trat)
    col_dens <- paste0("densidade_real_", ano_trat)
    
    if (!all(c(col_dist, col_dummy, col_dens) %in% names(base_mestre)) || !out$coluna %in% names(base_mestre)) next
    
    df_base <- base_mestre
    
    # 1. Filtro de distância (Amostra ≤ 200km)
    if (esp$filtro_200) {
      df_base <- df_base |> dplyr::filter(.data[[col_dist]] <= 200)
    }
    
    # 2. Exclusão das pontas via array extraído da sua lista
    if (esp$excl_pontas) {
      df_base <- df_base |> dplyr::filter(!(code_amc %in% codes_pontas_corr))
    }
    
    if (nrow(df_base) < 30) next
    
    vizinhos_loc <- poly2nb(df_base, queen = TRUE)
    pesos_loc    <- nb2listw(vizinhos_loc, style = "W", zero.policy = TRUE)
    df_base$dist_sintetica_vizinhos <- lag.listw(pesos_loc, df_base$dist_rail_sintetica_km, zero.policy = TRUE)
    
    cols_presentes <- intersect(c("code_amc", "state_abbr", col_dist, col_dummy, col_dens, "dist_rail_sintetica_km", "dummy_atendida_sintetica", "densidade_sintetica", out$coluna, cols_controles), names(df_base))
    df_out <- df_base |> sf::st_drop_geometry() |> dplyr::select(all_of(cols_presentes))
    
    tratamentos_loop <- list(
      list(nome="distancia", endogena=col_dist, instrumento="dist_rail_sintetica_km", rotulo=sprintf("Dist. real (%d)", ano_trat)),
      list(nome="dummy", endogena=col_dummy, instrumento="dummy_atendida_sintetica", rotulo=sprintf("Dummy ≤25km (%d)", ano_trat)),
      list(nome="densidade", endogena=col_dens, instrumento="densidade_sintetica", rotulo=sprintf("Densidade (%d)", ano_trat))
    )
    
    for (trat in tratamentos_loop) {
      contador <- contador + 1L
      cat(sprintf("  [%3d/%d] %-18s | %-12s ", contador, n_total, out$nome, trat$nome))
      
      res <- estimar_iv(df_out, trat$endogena, trat$instrumento, out$coluna, esp$fe_formula, esp$controles, out$transf, esp$rotulo, trat$rotulo, out$rotulo, out$escopo, ano_trat)
      resultados <- rbind(resultados, res)
      
      if (is.na(res$coef_ss)) {
        cat("❌ ERRO\n")
      } else {
        sig <- case_when(res$p_value < 0.01 ~ "***", res$p_value < 0.05 ~ "**", res$p_value < 0.10 ~ "*", TRUE ~ "")
        cat(sprintf("β=%+.4f%s  F=%5.1f  N=%d\n", res$coef_ss, sig, res$f_stat, res$n_obs))
      }
    }
  }
}

# ==============================================================================
# SEÇÃO 7: EXPORTAR RESULTADOS
# ==============================================================================
dir.create("03-resultados/csv", showWarnings = FALSE, recursive = TRUE)
arq_csv <- "03-resultados/csv/resultados_sensibilidade_pontas.csv"
write_csv(resultados, arq_csv)

cat("\n✓ CSV salvo em:", arq_csv, "\n")