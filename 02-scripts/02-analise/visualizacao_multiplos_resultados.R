# ==============================================================================
# VISUALIZAÇÃO DE MÚLTIPLOS RESULTADOS
# Script adaptado para gerar gráficos a partir de vários arquivos de resultados
# ==============================================================================

library(tidyverse)
library(patchwork)

# -------------------------------------------------
# 0. Configuração de Diretório
# -------------------------------------------------
if (!exists("data.wd")) {
  data.wd <- normalizePath(file.path(getwd(), "..", ".."))
}
setwd(data.wd)

# Diretório onde os gráficos serão salvos
plot_dir <- file.path("03-resultados", "plots")
dir.create(plot_dir, showWarnings = FALSE, recursive = TRUE)

# -------------------------------------------------
# 1. Tema customizado (baseado no script original)
# -------------------------------------------------
tema_customizado <- function() {
  theme_minimal() +
    theme(
      panel.grid.major = element_line(linetype = "dashed", color = "gray90"),
      panel.grid.minor = element_line(linetype = "dashed", color = "gray95"),
      axis.line = element_line(color = "black", linewidth = 0.6),
      axis.ticks = element_line(color = "black", linewidth = 0.6),
      axis.text = element_text(color = "black", size = 10),
      axis.title = element_text(color = "black", size = 11),
      plot.title = element_text(size = 13, hjust = 0),
      legend.position = "right",
      legend.title = element_blank(),
      legend.background = element_blank(),
      legend.key = element_blank()
    )
}

# -------------------------------------------------
# 2. Função genérica de plotagem
# -------------------------------------------------
criar_grafico <- function(df, tipo, nome_arquivo) {
  # Padronizar nomes de colunas
  df <- df %>%
    rename(
      coeficiente = ifelse("coeficiente" %in% names(.), "coeficiente",
                           ifelse("coef" %in% names(.), "coef",
                                  ifelse("coef_2nd_estagio" %in% names(.), "coef_2nd_estagio",
                                         ifelse("coef_final_formatado" %in% names(.), NA, NA)))),
      erro_padrao = ifelse("erro_padrao" %in% names(.), "erro_padrao",
                           ifelse("se" %in% names(.), "se",
                                  ifelse("se_2nd_estagio" %in% names(.), "se_2nd_estagio",
                                         ifelse("se_2nd_estagio" %in% names(.), NA, NA))))
    ) %>%
    # Converte para numérico caso esteja como character
    mutate(
      coeficiente = as.numeric(coeficiente),
      erro_padrao = as.numeric(erro_padrao)
    ) %>%
    # Remove linhas onde coeficiente ou erro são NA
    filter(!is.na(coeficiente) & !is.na(erro_padrao))
  
  # Extrair ano do outcome se não existir coluna ano_outcome
  if (!"ano_outcome" %in% names(df)) {
    df <- df %>%
      mutate(ano_outcome = as.numeric(str_extract(outcome_var, "\\d{4}")))
  }
  
  # Determinar variável de agrupamento conforme tipo de arquivo
  grupo <- switch(tipo,
                  "modelo_especificacao" = "modelo_especificacao",
                  "tipo_inferencia" = "tipo_inferencia",
                  "subamostra" = "subamostra",
                  "grupo" = "grupo",
                  "escopo" = "escopo",
                  "modelo_especificacao") # default
  
  # Se a coluna de agrupamento não existir, usar outcome_var como fallback
  if (!(grupo %in% names(df))) {
    grupo <- "outcome_var"
  }
  
  df <- df %>%
    mutate(grupo = as.factor(.data[[grupo]]),
           ci_lower = coeficiente - 1.96 * erro_padrao,
           ci_upper = coeficiente + 1.96 * erro_padrao)
  
  # Position dodge para sobrepor pontos do mesmo ano
  pd <- position_dodge(width = 2.5)
  
  # Criar gráfico
  p <- ggplot(df, aes(x = ano_outcome, y = coeficiente, color = grupo)) +
    geom_hline(yintercept = 0, color = "gray30", linewidth = 0.8) +
    geom_errorbar(aes(ymin = ci_lower, ymax = ci_upper),
                  position = pd, width = 0, linewidth = 0.8) +
    geom_point(position = pd, shape = 21, fill = "white", size = 2.5, stroke = 1.2) +
    scale_color_brewer(palette = "Set2") +
    scale_x_continuous(breaks = seq(min(df$ano_outcome, na.rm = TRUE),
                                    max(df$ano_outcome, na.rm = TRUE),
                                    by = 10)) +
    labs(
      title = paste("Efeito por", switch(tipo,
                                         "modelo_especificacao" = "Modelo",
                                         "tipo_inferencia" = "Tipo de Inferência",
                                         "subamostra" = "Subamostra",
                                         "grupo" = "Grupo",
                                         "escopo" = "Escopo",
                                         "Modelo")),
      x = "Ano de Observação",
      y = "Coeficiente"
    ) +
    tema_customizado() +
    theme(legend.position = "right")
  
  # Se houver muitos níveis de agrupação, usar facet_wrap ao invés de cor
  n_levels <- nlevels(df$grupo)
  if (n_levels > 6) {
    p <- p +
      facet_wrap(~grupo, scales = "free_y") +
      theme(legend.position = "none")
  }
  
  return(p)
}

# -------------------------------------------------
# 3. Lista de arquivos a processar
# -------------------------------------------------
arquivos <- tribble(
  ~caminho,                                            ~tipo,          ~nome_saida,
  "03-resultados/csv/teste_stepwise_controles_multidimensional_1950.csv",      "modelo_especificacao",   "stepwise_controles_multidim",
  "03-resultados/csv/teste_stepwise_controles_1950.csv",                     "modelo_especificacao",   "stepwise_controles",
  "03-resultados/csv/resultados_inferencia_espacial_1950.csv",               "tipo_inferencia",        "inferencia_espacial",
  "03-resultados/csv/second_stage_spillover_vizinhos_multidimensional_1950.csv","subamostra",          "spillover_vizinhos",
  "03-resultados/csv/second_stage_multidimensional_1950_subamostras.csv",    "grupo",                "multidim_subamostras",
  "03-resultados/csv/second_stage_multidimensional_results_1950.csv",        "escopo",               "multidim_resultados"
)

# -------------------------------------------------
# 4. Loop para ler, plotar e salvar
# -------------------------------------------------
for (i in seq_len(nrow(arquivos))) {
  caminho <- arquivos$caminho[i]
  tipo    <- arquivos$tipo[i]
  nome    <- arquivos$nome_saida[i]
  
  cat("Processando:", caminho, "\n")
  
  # Leitura do CSV
  df <- read_csv(caminho, show_col_types = FALSE)
  
  # Cria o gráfico
  p <- tryCatch(
    criar_grafico(df, tipo, nome),
    error = function(e) {
      warning(paste("Erro ao processar", caminho, ":", e$message))
      NULL
    }
  )
  
  if (!is.null(p)) {
    # Define diretório de saída específico
    out_dir <- file.path(plot_dir, nome)
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    
    outfile <- file.path(out_dir, paste0(nome, "_grafico.png"))
    ggsave(
      filename = outfile,
      plot = p,
      width = 12,
      height = 6,
      dpi = 300,
      bg = "white"
    )
    cat("  Gráfico salvo em:", outfile, "\n")
  } else {
    cat("  Falha ao criar gráfico para", caminho, "\n")
  }
}

cat("\nProcessamento concluído.\n")