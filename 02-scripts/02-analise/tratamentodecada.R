# ==============================================================================
# BATERIA IV — HETEROGENEIDADE POR DÉCADA DE TRATAMENTO (SEM PONTAS VIA LISTA)
# ==============================================================================

library(sf)
library(dplyr)
library(spdep)
library(fixest)
library(tidyr)
library(readr)
library(ggplot2)
library(stringr)

sf_use_s2(FALSE)

if (!exists("data.wd")) data.wd <- getwd()

cat("\n", strrep("=", 80), "\n")
cat("BATERIA IV — HETEROGENEIDADE POR DÉCADA DE TRATAMENTO (SEM PONTAS)\n")
cat("Data:", format(Sys.time(), "%d/%m/%Y %H:%M:%S"), "\n")
cat(strrep("=", 80), "\n\n")

# ==============================================================================
# SEÇÃO 1: CONSTRUIR BASE MESTRE
# ==============================================================================
cat("SEÇÃO 1: Carregando e integrando bases...\n")

if (!exists("base_iv_sf")) stop("'base_iv_sf' não encontrado. Execute o pipeline de preparação primeiro.")

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

if (!exists("lista_amcs_pontas")) {
  stop("ERRO: 'lista_amcs_pontas' não encontrado no Environment. Rode o script de mapeamento primeiro.")
}

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
  list(escopo = "1_PIB", nome = "pib_2000", coluna = "pib_2000", rotulo = "PIB Total (2000)", ano_outcome = 2000, transf = "log"),
  list(escopo = "1_PIB", nome = "pib_2010", coluna = "pib_2010", rotulo = "PIB Total (2010)", ano_outcome = 2010, transf = "log"),
  list(escopo = "1_PIB", nome = "pib_percapita_2000", coluna = "pib_percapita_2000", rotulo = "PIB p.c. (2000)", ano_outcome = 2000, transf = "log"),
  list(escopo = "1_PIB", nome = "pib_percapita_2010", coluna = "pib_percapita_2010", rotulo = "PIB p.c. (2010)", ano_outcome = 2010, transf = "log"),
  list(escopo = "2_Pop", nome = "pop_total_1991", coluna = "pop_total_1991", rotulo = "Pop. Total (1991)", ano_outcome = 1991, transf = "log"),
  list(escopo = "2_Pop", nome = "pop_total_2000", coluna = "pop_total_2000", rotulo = "Pop. Total (2000)", ano_outcome = 2000, transf = "log"),
  list(escopo = "2_Pop", nome = "pop_total_2010", coluna = "pop_total_2010", rotulo = "Pop. Total (2010)", ano_outcome = 2010, transf = "log"),
  list(escopo = "2_Pop", nome = "tx_urban_2010", coluna = "tx_urbanizacao_2010", rotulo = "Tx. Urbanização (2010)", ano_outcome = 2010, transf = "nivel"),
  list(escopo = "3_PAM", nome = "valproducao_2000", coluna = "valor_producao_mil_reais_2000", rotulo = "Val. Prod. (2000)", ano_outcome = 2000, transf = "log"),
  list(escopo = "3_PAM", nome = "valproducao_2010", coluna = "valor_producao_mil_reais_2010", rotulo = "Val. Prod. (2010)", ano_outcome = 2010, transf = "log"),
  list(escopo = "4_Social", nome = "idhm_2000", coluna = "adh_idhm_2000", rotulo = "IDHM (2000)", ano_outcome = 2000, transf = "nivel"),
  list(escopo = "4_Social", nome = "idhm_2010", coluna = "adh_idhm_2010", rotulo = "IDHM (2010)", ano_outcome = 2010, transf = "nivel"),
  list(escopo = "4_Social", nome = "rdpc_2000", coluna = "adh_rdpc_2000", rotulo = "Renda p.c. (2000)", ano_outcome = 2000, transf = "log"),
  list(escopo = "4_Social", nome = "rdpc_2010", coluna = "adh_rdpc_2010", rotulo = "Renda p.c. (2010)", ano_outcome = 2010, transf = "log"),
  list(escopo = "4_Social", nome = "pmpob_2010", coluna = "adh_pmpob_2010", rotulo = "% Pobres (2010)", ano_outcome = 2010, transf = "nivel")
)

n_outcomes <- length(outcomes_config)
cat(sprintf("  %d outcomes em 4 escopos\n\n", n_outcomes))


# ==============================================================================
# SEÇÃO 4: DEFINIR DÉCADAS DE TRATAMENTO
# ==============================================================================
cat("SEÇÃO 4: Configurando décadas e especificação única...\n")

decadas_trat <- seq(1860, 2000, by = 10)

esp <- list(
  nome        = "SemPontas_200km_FE_Completo",
  rotulo      = "Dist ≤200km + Excl.Pontas + FE Estado | Completo",
  filtro_200  = TRUE, excl_pontas = TRUE, fe_formula  = "state_abbr",
  controles   = "dist_sintetica_vizinhos + bio_1 + bio_12 + bio_15 + dist_rio_km + pct_solo_latossolos"
)


# ==============================================================================
# SEÇÃO 5: FUNÇÃO DE ESTIMAÇÃO IV (COM INTERVALOS DE CONFIANÇA)
# ==============================================================================
estimar_iv <- function(df, endogena, instrumento, outcome_col, fe_formula, controles, transf, nome_esp, nome_trat, nome_out, nome_escopo, decada) {
  tryCatch({
    df <- df |> dplyr::rename(Y = all_of(outcome_col))
    df <- df |> dplyr::filter(!is.na(.data[[endogena]]), !is.na(.data[[instrumento]]), !is.na(Y))
    if (transf == "log") df <- df |> dplyr::filter(Y > 0)
    
    n_obs <- nrow(df)
    if (n_obs < 30) stop("Amostra insuficiente (N < 30)")
    
    lhs        <- if (transf == "log") "log(Y)" else "Y"
    parte_ctrl <- if (is.null(controles) || nchar(trimws(controles)) == 0) "1" else controles
    
    formula_iv <- if (fe_formula == "1") {
      as.formula(sprintf("%s ~ %s | %s ~ %s", lhs, parte_ctrl, endogena, instrumento))
    } else {
      as.formula(sprintf("%s ~ %s | %s | %s ~ %s", lhs, parte_ctrl, fe_formula, endogena, instrumento))
    }
    
    modelo <- feols(formula_iv, data = df, se = "hetero")
    
    nome_coef <- paste0("fit_", endogena)
    coefs <- coef(modelo)
    ses   <- se(modelo)
    
    coef_ss <- coefs[nome_coef]
    se_ss   <- ses[nome_coef]
    t_ss    <- coef_ss / se_ss
    p_ss    <- 2 * (1 - pnorm(abs(t_ss)))
    
    ci_low  <- coef_ss - 1.96 * se_ss
    ci_high <- coef_ss + 1.96 * se_ss
    
    fstat_obj <- fitstat(modelo, "ivf")[[1]]
    f_stat    <- if (is.list(fstat_obj)) fstat_obj$stat else as.numeric(fstat_obj)
    
    data.frame(
      escopo        = nome_escopo, especificacao = nome_esp, decada_trat   = decada,
      tratamento    = nome_trat, outcome       = nome_out, transf        = transf,
      n_obs         = n_obs, coef_ss       = coef_ss, se_ss         = se_ss,
      ci_lower      = ci_low, ci_upper      = ci_high,
      t_stat        = t_ss, p_value       = p_ss, f_stat        = f_stat,
      erro          = NA_character_, stringsAsFactors = FALSE
    )
  }, error = function(e) {
    data.frame(
      escopo = nome_escopo, especificacao = nome_esp, decada_trat = decada, tratamento = nome_trat, outcome = nome_out, transf = transf,
      n_obs = NA_integer_, coef_ss = NA_real_, se_ss = NA_real_, ci_lower = NA_real_, ci_upper = NA_real_,
      t_stat = NA_real_, p_value = NA_real_, f_stat = NA_real_, erro = e$message, stringsAsFactors = FALSE
    )
  })
}


# ==============================================================================
# SEÇÃO 6: EXECUTAR BATERIA
# ==============================================================================
cat("\nEXECUTANDO BATERIA...\n")

cols_controles <- c("dist_sintetica_vizinhos", "bio_1", "bio_12", "bio_15", "dist_rio_km", "densidade_hidro_km_km2", "pct_solo_latossolos", "pct_solo_neossolos")
resultados <- data.frame()

for (out in outcomes_config) {
  if (!out$coluna %in% names(base_mestre)) next
  
  for (decada in decadas_trat) {
    if (decada >= out$ano_outcome) next
    
    col_dist  <- paste0("dist_rail_real_",     decada)
    col_dummy <- paste0("dummy_atendida_real_", decada)
    col_dens  <- paste0("densidade_real_",      decada)
    
    if (!all(c(col_dist, col_dummy, col_dens) %in% names(base_mestre))) next
    
    # FILTRO: Aplica exclusão das pontas listadas + Critério de ≤200km
    df_base <- base_mestre |> 
      dplyr::filter(.data[[col_dist]] <= 200) |>
      dplyr::filter(!(code_amc %in% codes_pontas_corr))
    
    if (nrow(df_base) < 30) next
    
    vizinhos_loc <- poly2nb(df_base, queen = TRUE)
    pesos_loc    <- nb2listw(vizinhos_loc, style = "W", zero.policy = TRUE)
    df_base$dist_sintetica_vizinhos <- lag.listw(pesos_loc, df_base$dist_rail_sintetica_km, zero.policy = TRUE)
    
    cols_presentes <- intersect(c("code_amc", "state_abbr", col_dist, col_dummy, col_dens, "dist_rail_sintetica_km", "dummy_atendida_sintetica", "densidade_sintetica", out$coluna, cols_controles), names(df_base))
    df_out <- df_base |> sf::st_drop_geometry() |> dplyr::select(all_of(cols_presentes))
    
    tratamentos_loop <- list(
      list(nome = "distancia", endogena = col_dist, instrumento = "dist_rail_sintetica_km", rotulo = "Dist. real"),
      list(nome = "dummy", endogena = col_dummy, instrumento = "dummy_atendida_sintetica", rotulo = "Dummy Atendimento"),
      list(nome = "densidade", endogena = col_dens, instrumento = "densidade_sintetica", rotulo = "Densidade")
    )
    
    for (trat in tratamentos_loop) {
      res <- estimar_iv(df_out, trat$endogena, trat$instrumento, out$coluna, esp$fe_formula, esp$controles, out$transf, esp$rotulo, trat$rotulo, out$rotulo, out$escopo, decada)
      resultados <- rbind(resultados, res)
    }
  }
}


# ==============================================================================
# SEÇÃO 7 & 8: EXPORTAÇÃO CSV
# ==============================================================================
dir.create("03-resultados/csv", showWarnings = FALSE, recursive = TRUE)
write_csv(resultados, "03-resultados/csv/resultados_bateria10_decadas_sempontas.csv")


# ==============================================================================
# SEÇÃO 9: PLOTAGEM DO EFEITO POR DÉCADA (UM GRÁFICO POR OUTCOME)
# ==============================================================================
cat("\nGERANDO GRÁFICOS DE COEFICIENTES (Individuais por Outcome)...\n")

dir.create("03-resultados/graficos/decadas", showWarnings = FALSE, recursive = TRUE)

# Focamos no tratamento Dummy para os resultados de longo prazo (2010)
dados_grafico <- resultados |>
  filter(tratamento == "Dummy Atendimento") |>
  filter(!is.na(coef_ss)) |>
  filter(grepl("2010", outcome))

# Lista única de outcomes disponíveis em 2010
outcomes_unicos <- unique(dados_grafico$outcome)

for (out_name in outcomes_unicos) {
  
  df_plot <- dados_grafico |> filter(outcome == out_name)
  
  # Limpa o nome do outcome para criar um nome de arquivo seguro
  nome_arquivo <- gsub("[^A-Za-z0-9_]", "_", out_name)
  nome_arquivo <- gsub("_+", "_", nome_arquivo)
  
  p <- ggplot(df_plot, aes(x = decada_trat, y = coef_ss)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "#c0392b", linewidth = 1) +
    geom_pointrange(aes(ymin = ci_lower, ymax = ci_upper), 
                    color = "#2c3e50", size = 0.8, fatten = 3) +
    geom_line(color = "#2c3e50", alpha = 0.6, linewidth = 1.2) +
    scale_x_continuous(breaks = seq(1860, 2000, by = 10)) + # Marcas a cada 10 anos
    theme_minimal(base_size = 14) +
    theme(
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_line(color = "gray90"),
      plot.title = element_text(face = "bold", size = 16),
      plot.subtitle = element_text(color = "gray30", size = 11)
    ) +
    labs(
      title = sprintf("Efeito da Conexão Ferroviária: %s", out_name),
      subtitle = "Coeficiente da regressão IV (2SLS) por década de recebimento da ferrovia.\nBarras representam o Intervalo de Confiança de 95%.",
      x = "Década em que a AMC foi conectada à ferrovia",
      y = "Efeito Estimado (Coeficiente da Dummy)"
    )
  
  # Salva individualmente num tamanho robusto
  caminho_img <- sprintf("03-resultados/graficos/decadas/Trajetoria_%s.png", nome_arquivo)
  ggsave(caminho_img, plot = p, width = 9, height = 6, dpi = 300)
  cat(sprintf("  ✓ Gráfico salvo: %s\n", caminho_img))
}

cat("\n✓ BATERIA 10 CONCLUÍDA — Todos os gráficos gerados com sucesso.\n")





# ==============================================================================
# SEÇÃO 9: PLOTAGEM DO EFEITO POR DÉCADA (COM ZOOM INTELIGENTE NO EIXO Y)
# ==============================================================================
cat("\nGERANDO GRÁFICOS DE COEFICIENTES (Zoom aproximado por Outcome)...\n")

dir.create("03-resultados/graficos/decadas", showWarnings = FALSE, recursive = TRUE)

# Focamos no tratamento Dummy para os resultados de longo prazo (2010)
dados_grafico <- resultados |>
  filter(tratamento == "Dummy Atendimento") |>
  filter(!is.na(coef_ss)) |>
  filter(grepl("2010", outcome))

# Lista única de outcomes disponíveis em 2010
outcomes_unicos <- unique(dados_grafico$outcome)

for (out_name in outcomes_unicos) {
  
  df_plot <- dados_grafico |> filter(outcome == out_name)
  
  # Limpa o nome do outcome para criar um nome de arquivo seguro
  nome_arquivo <- gsub("[^A-Za-z0-9_]", "_", out_name)
  nome_arquivo <- gsub("_+", "_", nome_arquivo)
  
  # ----------------------------------------------------------------------------
  # LÓGICA DE ZOOM CRÍTICO:
  # Baseia os limites do eixo Y na variação dos COEFICIENTES, ignorando a 
  # explosão de erros padrões causados por décadas com instrumentos fracos.
  # ----------------------------------------------------------------------------
  max_coef <- max(df_plot$coef_ss, na.rm = TRUE)
  min_coef <- min(df_plot$coef_ss, na.rm = TRUE)
  amplitude <- max_coef - min_coef
  
  # Se o efeito for bizarramente constante, define uma margem mínima
  if(is.na(amplitude) || amplitude == 0) amplitude <- 0.5 
  
  # Limites apertados: pega o valor máx/min do coeficiente e dá uma margem
  lim_sup <- max_coef + (amplitude * 1.0)
  lim_inf <- min_coef - (amplitude * 1.0)
  
  # Garante que a linha vermelha do Zero (0) nunca fique de fora do gráfico
  lim_sup <- max(lim_sup, 0.1)
  lim_inf <- min(lim_inf, -0.1)
  
  p <- ggplot(df_plot, aes(x = decada_trat, y = coef_ss)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "#c0392b", linewidth = 1) +
    
    # Desenha os pontos e os intervalos de confiança
    geom_pointrange(aes(ymin = ci_lower, ymax = ci_upper), 
                    color = "#2c3e50", size = 0.8, fatten = 3) +
    geom_line(color = "#2c3e50", alpha = 0.6, linewidth = 1.2) +
    
    scale_x_continuous(breaks = seq(1860, 2000, by = 10)) + 
    
    # O SEGREDO DO ZOOM: coord_cartesian corta a janela visual sem apagar os dados
    coord_cartesian(ylim = c(lim_inf, lim_sup)) + 
    
    theme_minimal(base_size = 14) +
    theme(
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_line(color = "gray90"),
      plot.title = element_text(face = "bold", size = 16),
      plot.subtitle = element_text(color = "gray30", size = 11)
    ) +
    labs(
      title = sprintf("Efeito da Conexão Ferroviária: %s", out_name),
      subtitle = "Coeficiente IV por década. O eixo Y tem zoom aproximado para evidenciar a tendência.\nBarras indicam IC de 95% (podem estar cortadas se o erro padrão for extremo).",
      x = "Década em que a AMC foi conectada à ferrovia",
      y = "Efeito Estimado (Zoom no Coeficiente)"
    )
  
  caminho_img <- sprintf("03-resultados/graficos/decadas/Trajetoria_Zoom_%s.png", nome_arquivo)
  ggsave(caminho_img, plot = p, width = 9, height = 6, dpi = 300)
  cat(sprintf("  ✓ Gráfico salvo (com zoom): %s\n", caminho_img))
}

cat("\n✓ BATERIA DE GRÁFICOS CONCLUÍDA!\n")