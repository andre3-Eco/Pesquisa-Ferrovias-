# ==============================================================================
# TABELA DE RESULTADOS — BATERIA 9 (NOVOS OUTCOMES)
# ==============================================================================
# Script : 9b_Tabela_Resultados_Bateria9.R
# Depende: resultados_bateria9_novos_outcomes.csv (gerado por 9_Bateria_Novos_Outcomes_4Escopos.R)
#
# Saídas:
#   tabela_bateria9_novos_outcomes.xlsx  → planilha com abas por escopo
#   tabela_bateria9_novos_outcomes.html  → tabela HTML completa (knitr)
#   tabela_bateria9_markdown.md          → tabela Markdown (para documentos)
# ==============================================================================

library(dplyr)
library(tidyr)
library(readr)

# Carregar resultados
arq <- "03-resultados/csv/resultados_bateria9_novos_outcomes.csv"
if (!file.exists(arq)) stop(sprintf("Arquivo não encontrado: %s\nExecute 9_Bateria_Novos_Outcomes_4Escopos.R primeiro.", arq))

res <- read_csv(arq, show_col_types = FALSE)
cat(sprintf("Carregados %d resultados de %d regressões.\n\n", nrow(res), nrow(res)))


# ==============================================================================
# SEÇÃO 1: TABELA LONGA FORMATADA (base para todas as saídas)
# ==============================================================================

# Função de estrelas de significância
stars <- function(p) {
  dplyr::case_when(
    p < 0.01 ~ "***",
    p < 0.05 ~ "**",
    p < 0.10 ~ "*",
    TRUE     ~ ""
  )
}

# Flags de qualidade do instrumento
flag_f <- function(f) {
  dplyr::case_when(
    is.na(f)  ~ "—",
    f >= 10   ~ "✓ forte",
    f >= 5    ~ "⚠ mod.",
    TRUE      ~ "✗ fraco"
  )
}

tabela_longa <- res |>
  dplyr::mutate(
    sig       = stars(p_value),
    coef_fmt  = dplyr::if_else(is.na(coef_ss), "—",
                               sprintf("%+.4f%s", coef_ss, sig)),
    se_fmt    = dplyr::if_else(is.na(se_ss),   "—",
                               sprintf("(%.4f)", se_ss)),
    f_fmt     = dplyr::if_else(is.na(f_stat),   "—",
                               sprintf("%.1f",   f_stat)),
    p_fmt     = dplyr::if_else(is.na(p_value),  "—",
                               sprintf("%.3f",   p_value)),
    instr_ok  = flag_f(f_stat),
    transf_label = dplyr::if_else(transf == "log", "log(Y)", "Y (nível)")
  ) |>
  dplyr::select(
    Escopo        = escopo,
    Especificacao = especificacao,
    Tratamento    = tratamento,
    `Ano trat.`   = ano_trat,
    Outcome       = outcome,
    Transf        = transf_label,
    N             = n_obs,
    `β (2S)`      = coef_fmt,
    SE            = se_fmt,
    `F (1S)`      = f_fmt,
    `F qualidade` = instr_ok,
    `p-valor`     = p_fmt,
    Erro          = erro
  )


# ==============================================================================
# SEÇÃO 2: TABELA PIVOT — Coeficientes por Especificação (formato publicação)
# ==============================================================================
# Uma linha por (outcome, tratamento); colunas = especificações

tabela_pivot <- res |>
  dplyr::filter(!is.na(coef_ss)) |>
  dplyr::mutate(
    sig      = stars(p_value),
    cel      = sprintf("%+.4f%s\n(%.4f)\nF=%.1f", coef_ss, sig, se_ss, f_stat),
    # Abreviar nome da especificação para caber na tabela
    esp_abrev = dplyr::case_when(
      grepl("LagEsp",    especificacao) ~ "(1) Lag esp.",
      grepl("Clima",     especificacao) ~ "(2) Clima",
      grepl("RiosSolo",  especificacao) ~ "(3) Rios+Solo",
      grepl("Completo",  especificacao) ~ "(4) Completo",
      TRUE                              ~ especificacao
    )
  ) |>
  dplyr::select(Escopo = escopo, Outcome = outcome, Tratamento = tratamento,
                esp_abrev, cel) |>
  tidyr::pivot_wider(names_from = esp_abrev, values_from = cel)

cat("TABELA PIVOT (coeficiente / SE / F por especificação):\n\n")
print(tabela_pivot, n = Inf, width = 200)


# ==============================================================================
# SEÇÃO 3: RESUMO POR ESCOPO
# ==============================================================================

cat("\n\nRESUMO DIAGNÓSTICO POR ESCOPO:\n\n")

resumo_escopo <- res |>
  dplyr::group_by(Escopo = escopo) |>
  dplyr::summarise(
    N_regressoes  = dplyr::n(),
    N_sucesso     = sum(!is.na(coef_ss)),
    N_sig_05      = sum(p_value < 0.05, na.rm = TRUE),
    N_sig_10      = sum(p_value < 0.10, na.rm = TRUE),
    F_medio       = round(mean(f_stat, na.rm = TRUE), 1),
    F_min         = round(min(f_stat,  na.rm = TRUE), 1),
    N_fraco       = sum(f_stat < 10,   na.rm = TRUE),
    coef_medio    = round(mean(coef_ss, na.rm = TRUE), 4),
    .groups = "drop"
  )
print(resumo_escopo, n = Inf)

cat("\nRESUMO POR TIPO DE TRATAMENTO:\n\n")
resumo_trat <- res |>
  dplyr::group_by(Tratamento = tratamento) |>
  dplyr::summarise(
    F_medio    = round(mean(f_stat, na.rm = TRUE), 1),
    F_min      = round(min(f_stat,  na.rm = TRUE), 1),
    N_sig_05   = sum(p_value < 0.05, na.rm = TRUE),
    coef_medio = round(mean(coef_ss, na.rm = TRUE), 4),
    .groups    = "drop"
  )
print(resumo_trat, n = Inf)

cat("\nRESUMO POR TIPO DE CONTROLES (ESPECIFICAÇÃO):\n\n")
resumo_ctrl <- res |>
  dplyr::mutate(
    ctrl = dplyr::case_when(
      grepl("LagEsp",   especificacao) ~ "Lag espacial",
      grepl("Clima",    especificacao) ~ "Clima",
      grepl("RiosSolo", especificacao) ~ "Rios+Solo",
      grepl("Completo", especificacao) ~ "Completo",
      TRUE                             ~ especificacao
    )
  ) |>
  dplyr::group_by(`Controles` = ctrl) |>
  dplyr::summarise(
    F_medio  = round(mean(f_stat,  na.rm = TRUE), 1),
    N_sig_05 = sum(p_value < 0.05, na.rm = TRUE),
    N_total  = dplyr::n(),
    .groups  = "drop"
  )
print(resumo_ctrl, n = Inf)


# ==============================================================================
# SEÇÃO 4: EXPORTAR TABELAS
# ==============================================================================

dir.create("03-resultados/tabelas", showWarnings = FALSE, recursive = TRUE)

# ── HTML (knitr) ────────────────────────────────────────────────────────────
if (requireNamespace("knitr", quietly = TRUE)) {
  html_longa <- knitr::kable(tabela_longa, format = "html", escape = FALSE,
                              caption = "Bateria 9 — Resultados IV: Novos Outcomes (4 Escopos)")
  arq_html <- "03-resultados/tabelas/tabela_bateria9_novos_outcomes.html"
  writeLines(as.character(html_longa), arq_html)
  cat(sprintf("\n  ✓ HTML: %s\n", arq_html))
} else {
  cat("  ℹ knitr não disponível — instale com install.packages('knitr')\n")
}

# ── Excel (openxlsx) ────────────────────────────────────────────────────────
if (requireNamespace("openxlsx", quietly = TRUE)) {
  wb <- openxlsx::createWorkbook()

  # Aba 1: Resultados completos
  openxlsx::addWorksheet(wb, "Todos os resultados")
  openxlsx::writeData(wb, "Todos os resultados", tabela_longa)

  # Aba 2: Pivot por especificação
  openxlsx::addWorksheet(wb, "Pivot por especificação")
  openxlsx::writeData(wb, "Pivot por especificação", tabela_pivot)

  # Abas por escopo
  for (esc in unique(res$escopo)) {
    df_esc <- tabela_longa |> dplyr::filter(Escopo == esc)
    nome_aba <- substring(esc, 3)  # remove "1_", "2_", etc.
    openxlsx::addWorksheet(wb, nome_aba)
    openxlsx::writeData(wb, nome_aba, df_esc)
  }

  # Aba de resumo diagnóstico
  openxlsx::addWorksheet(wb, "Diagnóstico")
  openxlsx::writeData(wb, "Diagnóstico", resumo_escopo)

  arq_xlsx <- "03-resultados/tabelas/tabela_bateria9_novos_outcomes.xlsx"
  openxlsx::saveWorkbook(wb, arq_xlsx, overwrite = TRUE)
  cat(sprintf("  ✓ Excel: %s\n", arq_xlsx))
} else {
  cat("  ℹ openxlsx não disponível — instale com install.packages('openxlsx')\n")
}

# ── Markdown ────────────────────────────────────────────────────────────────
if (requireNamespace("knitr", quietly = TRUE)) {
  md_longa <- knitr::kable(tabela_longa, format = "markdown")
  arq_md   <- "03-resultados/tabelas/tabela_bateria9_markdown.md"
  writeLines(
    c("# Tabela de Resultados — Bateria 9 (Novos Outcomes)", "",
      paste0("_Gerada em: ", format(Sys.time(), "%d/%m/%Y %H:%M"), "_"), "",
      as.character(md_longa)),
    arq_md
  )
  cat(sprintf("  ✓ Markdown: %s\n", arq_md))
}

cat("\n✓ Tabelas exportadas com sucesso.\n")


# ==============================================================================
# SEÇÃO 5: GRÁFICO DE COEFICIENTES (FOREST PLOT)
# ==============================================================================

if (requireNamespace("ggplot2", quietly = TRUE)) {
  library(ggplot2)

  df_plot <- res |>
    dplyr::filter(!is.na(coef_ss)) |>
    dplyr::mutate(
      sig_label = dplyr::case_when(
        p_value < 0.01 ~ "p < 0.01",
        p_value < 0.05 ~ "p < 0.05",
        p_value < 0.10 ~ "p < 0.10",
        TRUE           ~ "n.s."
      ),
      esp_abrev = dplyr::case_when(
        grepl("LagEsp",   especificacao) ~ "(1)",
        grepl("Clima",    especificacao) ~ "(2)",
        grepl("RiosSolo", especificacao) ~ "(3)",
        grepl("Completo", especificacao) ~ "(4)",
        TRUE                             ~ "?"
      ),
      outcome_abrev = stringr::str_replace(outcome, " \\(.*\\)", ""),
      ci_lo = coef_ss - 1.96 * se_ss,
      ci_hi = coef_ss + 1.96 * se_ss
    ) |>
    dplyr::filter(tratamento == tratamento[1])  # plotar apenas o 1º tipo de tratamento

  # Forest plot por escopo
  ggplot(df_plot, aes(x = coef_ss, y = reorder(outcome_abrev, coef_ss),
                       color = sig_label)) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey50") +
    geom_errorbarh(aes(xmin = ci_lo, xmax = ci_hi), height = 0.2, linewidth = 0.6) +
    geom_point(size = 2.5) +
    facet_grid(escopo ~ esp_abrev, scales = "free_y", space = "free_y") +
    scale_color_manual(
      values = c("p < 0.01" = "#1a4e8f", "p < 0.05" = "#4292c6",
                 "p < 0.10" = "#9ecae1", "n.s."     = "#bdbdbd"),
      name = "Significância"
    ) +
    labs(
      title    = "Bateria 9 — Coeficientes IV por Outcome e Especificação",
      subtitle = paste0("Apenas tratamento: ", unique(df_plot$tratamento)[1],
                        " | IC 95%"),
      x = "Coeficiente do 2º estágio (β)",
      y = NULL,
      caption = "Especificações: (1) Lag espacial | (2) Clima | (3) Rios+Solo | (4) Completo"
    ) +
    theme_bw(base_size = 9) +
    theme(
      strip.text    = element_text(size = 7),
      legend.position = "bottom"
    )

  arq_forest <- "03-resultados/graficos/forest_bateria9_distancia.png"
  dir.create("03-resultados/graficos", showWarnings = FALSE, recursive = TRUE)
  ggsave(arq_forest, width = 14, height = 9, dpi = 150)
  cat(sprintf("  ✓ Forest plot: %s\n", arq_forest))
}

cat("\n✓ Script 9b concluído.\n")
