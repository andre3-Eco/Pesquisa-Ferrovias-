# ==============================================================================
# VISUALIZAÇÃO: RESULTADOS MULTIDIMENSIONAIS
# Cria gráficos e tabelas resumidas dos resultados da análise 2SLS
# ==============================================================================

library(dplyr)
library(tidyverse)
library(readr)
library(ggplot2)
library(patchwork)

if (!exists("data.wd")) {
  data.wd <- normalizePath(file.path(getwd(), "..", ".."))
}
setwd(data.wd)

cat("========================================================================\n")
cat("VISUALIZAÇÃO: RESULTADOS MULTIDIMENSIONAIS\n")
cat("========================================================================\n\n")

# ==============================================================================
# 1. CARREGAR RESULTADOS
# ==============================================================================
cat("1. Carregando resultados da análise...\n\n")

resultados <- read_csv(
  "03-resultados/csv/second_stage_multidimensional_results.csv",
  show_col_types = FALSE
)

cat(sprintf("   ✓ Carregados %d resultados\n\n", nrow(resultados)))

# ==============================================================================
# 2. ANÁLISE EXPLORATÓRIA
# ==============================================================================
cat("2. Análise exploratória dos resultados\n\n")

# Escopos
cat("   Escopos testados:\n")
escopos_summary <- resultados |>
  group_by(escopo) |>
  summarise(n = n(), .groups = "drop") |>
  arrange(desc(n))
print(escopos_summary)

cat("\n   Anos de tratamento:\n")
cat(sprintf("   %s\n", 
            paste(sort(unique(resultados$ano_tratamento)), collapse = ", ")))

cat("\n")

# ==============================================================================
# 3. GRÁFICO 1: COEFICIENTES POR ESCOPO (BOX PLOT)
# ==============================================================================
cat("3. Gerando visualizações...\n")

p1 <- resultados |>
  mutate(escopo = fct_reorder(escopo, coeficiente, .fun = median)) |>
  ggplot(aes(x = escopo, y = coeficiente, fill = escopo)) +
  geom_boxplot(alpha = 0.6, show.legend = FALSE) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "red", size = 0.8) +
  coord_flip() +
  labs(
    title = "Distribuição de Coeficientes por Escopo",
    subtitle = "Segundo Estágio: Densidade Buffer Real → Outcomes",
    x = "Escopo",
    y = "Coeficiente Estimado"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 12),
    panel.grid.major.x = element_line(color = "gray90")
  )

ggsave("03-resultados/graficos/01_boxplot_coeficientes_por_escopo.png",
       p1, width = 10, height = 6, dpi = 300)
cat("   ✓ Gráfico 1 salvo\n")

# ==============================================================================
# 4. GRÁFICO 2: SIGNIFICÂNCIA POR ESCOPO
# ==============================================================================

p2 <- resultados |>
  mutate(
    sig_grupo = case_when(
      p_valor < 0.01 ~ "p < 0.01",
      p_valor < 0.05 ~ "p < 0.05",
      p_valor < 0.10 ~ "p < 0.10",
      TRUE ~ "ns"
    ),
    sig_grupo = factor(sig_grupo, levels = c("p < 0.01", "p < 0.05", "p < 0.10", "ns"))
  ) |>
  group_by(escopo, sig_grupo) |>
  summarise(n = n(), .groups = "drop") |>
  ggplot(aes(x = escopo, y = n, fill = sig_grupo)) +
  geom_col(position = "dodge") +
  scale_fill_manual(
    values = c("p < 0.01" = "#d7191c", "p < 0.05" = "#fdae61", 
               "p < 0.10" = "#ffffbf", "ns" = "#e0f3f8")
  ) +
  coord_flip() +
  labs(
    title = "Número de Regressões por Nível de Significância",
    x = "Escopo",
    y = "Contagem",
    fill = "p-value"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 12),
    panel.grid.major.x = element_line(color = "gray90")
  )

ggsave("03-resultados/graficos/02_significancia_por_escopo.png",
       p2, width = 10, height = 6, dpi = 300)
cat("   ✓ Gráfico 2 salvo\n")

# ==============================================================================
# 5. GRÁFICO 3: F-STATISTIC (FORÇA DO INSTRUMENTO)
# ==============================================================================

p3 <- resultados |>
  filter(!is.na(F_stat_1estagio), F_stat_1estagio > 0) |>
  mutate(escopo = fct_reorder(escopo, F_stat_1estagio, .fun = median)) |>
  ggplot(aes(x = escopo, y = F_stat_1estagio, fill = escopo)) +
  geom_boxplot(alpha = 0.6, show.legend = FALSE) +
  geom_hline(yintercept = 10, linetype = "dashed", color = "green", size = 0.8) +
  geom_hline(yintercept = 5, linetype = "dashed", color = "orange", size = 0.8) +
  annotate("text", x = Inf, y = 10, label = "Forte (>10)", 
           hjust = 1.1, vjust = -0.5, size = 3, color = "green") +
  annotate("text", x = Inf, y = 5, label = "Moderado (5-10)", 
           hjust = 1.1, vjust = -0.5, size = 3, color = "orange") +
  coord_flip() +
  scale_y_log10() +
  labs(
    title = "Força do Instrumento (F-statistic) por Escopo",
    subtitle = "Nota: Escala logarítmica. Valores > 10 indicam instrumento forte",
    x = "Escopo",
    y = "F-statistic (escala log)"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 12),
    panel.grid.major.x = element_line(color = "gray90")
  )

ggsave("03-resultados/graficos/03_f_statistic_por_escopo.png",
       p3, width = 10, height = 6, dpi = 300)
cat("   ✓ Gráfico 3 salvo\n")

# ==============================================================================
# 6. GRÁFICO 4: SÉRIE TEMPORAL DE COEFICIENTES
# ==============================================================================
# Selecionar alguns outcomes principais para visualizar a série

principais <- resultados |>
  filter(str_detect(escopo, "PIB|IDH_Geral|Urbanização")) |>
  group_by(outcome_var) |>
  summarise(n = n(), coef_medio = mean(coeficiente, na.rm = TRUE), .groups = "drop") |>
  slice_max(n, n = 6) |>
  pull(outcome_var)

p4 <- resultados |>
  filter(outcome_var %in% principais) |>
  filter(!is.na(coeficiente)) |>
  ggplot(aes(x = ano_tratamento, y = coeficiente, color = outcome_var, group = outcome_var)) +
  geom_line(alpha = 0.6, size = 0.8) +
  geom_point(aes(shape = significancia), size = 2) +
  facet_wrap(~outcome_var, scales = "free_y", ncol = 3) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "red", alpha = 0.5) +
  scale_shape_manual(values = c("***" = 16, "**" = 17, "*" = 15, "" = 1)) +
  labs(
    title = "Série Temporal de Coeficientes Estimados",
    subtitle = "Seleção dos 6 principais outcomes (PIB, IDH, Urbanização)",
    x = "Ano de Tratamento",
    y = "Coeficiente",
    color = "Outcome",
    shape = "Significância"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 12),
    legend.position = "bottom",
    panel.grid.major = element_line(color = "gray90", size = 0.3)
  )

ggsave("03-resultados/graficos/04_serie_temporal_coeficientes.png",
       p4, width = 14, height = 8, dpi = 300)
cat("   ✓ Gráfico 4 salvo\n")

# ==============================================================================
# 7. TABELA 1: RESULTADOS SIGNIFICATIVOS (p < 0.05)
# ==============================================================================
cat("   Compilando tabelas...\n")

sig_results <- resultados |>
  filter(p_valor < 0.05) |>
  select(
    escopo,
    outcome_var,
    ano_tratamento,
    coeficiente,
    erro_padrao,
    t_estatistica,
    p_valor,
    F_stat_1estagio,
    n_observacoes
  ) |>
  mutate(
    coeficiente = round(coeficiente, 4),
    erro_padrao = round(erro_padrao, 4),
    t_estatistica = round(t_estatistica, 4),
    p_valor = round(p_valor, 6),
    F_stat_1estagio = round(F_stat_1estagio, 2)
  ) |>
  arrange(escopo, p_valor)

write_csv(sig_results, "03-resultados/csv/resultados_significativos_p05.csv")
cat("   ✓ Tabela de resultados significativos salva\n")

# ==============================================================================
# 8. TABELA 2: RESUMO POR ESCOPO
# ==============================================================================

resumo_escopo_detalhado <- resultados |>
  group_by(escopo) |>
  summarise(
    n_regressoes = n(),
    n_sig_001 = sum(p_valor < 0.01, na.rm = TRUE),
    n_sig_005 = sum(p_valor < 0.05, na.rm = TRUE),
    n_sig_010 = sum(p_valor < 0.10, na.rm = TRUE),
    pct_sig_005 = round(100 * sum(p_valor < 0.05, na.rm = TRUE) / n(), 1),
    coef_medio = round(mean(coeficiente, na.rm = TRUE), 4),
    coef_mediano = round(median(coeficiente, na.rm = TRUE), 4),
    f_stat_medio = round(mean(F_stat_1estagio, na.rm = TRUE), 2),
    r2_medio = round(mean(R2_2estagio, na.rm = TRUE), 4),
    .groups = "drop"
  ) |>
  arrange(desc(pct_sig_005))

write_csv(resumo_escopo_detalhado, "03-resultados/csv/resumo_por_escopo.csv")
cat("   ✓ Resumo por escopo salvo\n")

# ==============================================================================
# 9. TABELA 3: TOP 10 EFEITOS MAIS FORTES
# ==============================================================================

top_efeitos <- resultados |>
  mutate(abs_coef = abs(coeficiente)) |>
  slice_max(abs_coef, n = 15) |>
  select(
    escopo,
    outcome_var,
    ano_tratamento,
    coeficiente,
    p_valor,
    F_stat_1estagio,
    n_observacoes,
    significancia
  ) |>
  mutate(
    coeficiente = round(coeficiente, 4),
    p_valor = round(p_valor, 6),
    F_stat_1estagio = round(F_stat_1estagio, 2)
  )

write_csv(top_efeitos, "03-resultados/csv/top_efeitos_mais_fortes.csv")
cat("   ✓ Top 10 efeitos salvo\n")

# ==============================================================================
# 10. TABELA 4: RESULTADOS POR ESCOPO E ANO
# ==============================================================================

resultados_por_escopo_ano <- resultados |>
  filter(!is.na(coeficiente)) |>
  group_by(escopo, ano_tratamento) |>
  summarise(
    n_outcomes = n_distinct(outcome_var),
    coef_medio = mean(coeficiente, na.rm = TRUE),
    n_sig_005 = sum(p_valor < 0.05, na.rm = TRUE),
    f_stat_medio = mean(F_stat_1estagio, na.rm = TRUE),
    .groups = "drop"
  )

write_csv(resultados_por_escopo_ano, "03-resultados/csv/resultados_por_escopo_ano.csv")
cat("   ✓ Resultados por escopo e ano salvo\n")

# ==============================================================================
# 11. GRÁFICO 5: HEATMAP COEFICIENTES POR ESCOPO E ANO
# ==============================================================================

heatmap_data <- resultados |>
  group_by(escopo, ano_tratamento) |>
  summarise(coef_medio = mean(coeficiente, na.rm = TRUE), .groups = "drop")

p5 <- heatmap_data |>
  ggplot(aes(x = ano_tratamento, y = escopo, fill = coef_medio)) +
  geom_tile(color = "white") +
  scale_fill_gradient2(low = "#d7191c", mid = "white", high = "#1a9850", 
                       midpoint = 0, na.value = "gray90") +
  labs(
    title = "Heatmap de Coeficientes Médios",
    subtitle = "Média de coeficientes por Escopo e Ano de Tratamento",
    x = "Ano de Tratamento",
    y = "Escopo",
    fill = "Coeficiente Médio"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 12),
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

ggsave("03-resultados/graficos/05_heatmap_coeficientes.png",
       p5, width = 12, height = 6, dpi = 300)
cat("   ✓ Gráfico 5 (heatmap) salvo\n")

# ==============================================================================
# 12. RESUMO FINAL
# ==============================================================================
cat("\n")
cat("========================================================================\n")
cat("RESUMO DA VISUALIZAÇÃO\n")
cat("========================================================================\n\n")

cat("Gráficos gerados:\n")
cat("  • 01_boxplot_coeficientes_por_escopo.png\n")
cat("  • 02_significancia_por_escopo.png\n")
cat("  • 03_f_statistic_por_escopo.png\n")
cat("  • 04_serie_temporal_coeficientes.png\n")
cat("  • 05_heatmap_coeficientes.png\n\n")

cat("Tabelas geradas:\n")
cat("  • resultados_significativos_p05.csv\n")
cat("  • resumo_por_escopo.csv\n")
cat("  • top_efeitos_mais_fortes.csv\n")
cat("  • resultados_por_escopo_ano.csv\n\n")

cat("Estatísticas Gerais:\n")
print(resumo_escopo_detalhado)

cat("\n========================================================================\n")
cat("✅ VISUALIZAÇÃO CONCLUÍDA!\n")
cat("Todos os arquivos foram salvos em 03-resultados/\n")
cat("========================================================================\n")
