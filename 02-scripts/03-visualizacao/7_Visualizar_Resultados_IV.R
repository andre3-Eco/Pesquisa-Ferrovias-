# ==============================================================================
# VISUALIZAÇÃO E INTERPRETAÇÃO DOS RESULTADOS DA BATERIA IV
# ==============================================================================
# Este script cria tabelas, gráficos e relatórios a partir dos resultados
# da bateria de testes executada em 6_Bateria_Testes_Etapas_I_II.R
# ==============================================================================

library(tidyverse)
library(ggplot2)
library(knitr)
library(kableExtra)

if (!exists("data.wd")) data.wd <- getwd()

cat("\n", strrep("=", 80), "\n")
cat("VISUALIZAÇÃO E ANÁLISE DOS RESULTADOS IV\n")
cat(strrep("=", 80), "\n\n")

# ==============================================================================
# SEÇÃO 1: CARREGAMENTO DOS RESULTADOS
# ==============================================================================

cat("Carregando resultados da bateria...\n")

resultados <- read_csv(
  paste0(data.wd, "/resultados_bateria_iv.csv"),
  show_col_types = FALSE
)

cat(sprintf("✓ %d resultados carregados\n\n", nrow(resultados)))

# ==============================================================================
# SEÇÃO 2: TABELAS DE RESUMO
# ==============================================================================

cat(strrep("=", 80), "\n")
cat("TABELAS DE RESUMO\n")
cat(strrep("=", 80), "\n\n")

# TABELA 1: Resultados por especificação e outcome
cat("TABELA 1: Resultados por Especificação e Outcome\n")
cat("(Coeficiente do segundo estágio, com p-value)\n\n")

tabela_1 <- resultados |>
  filter(!is.na(coef_ss)) |>
  select(especificacao, outcome, coef_ss, p_value, f_stat) |>
  arrange(especificacao, outcome) |>
  mutate(
    coef_ss = round(coef_ss, 4),
    p_value = round(p_value, 4),
    f_stat = round(f_stat, 2),
    significancia = case_when(
      p_value < 0.01 ~ "***",
      p_value < 0.05 ~ "**",
      p_value < 0.10 ~ "*",
      TRUE ~ ""
    )
  ) |>
  select(especificacao, outcome, coef_ss, significancia, p_value, f_stat)

print(tabela_1)

# TABELA 2: Resultados por tipo de tratamento
cat("\n\nTABELA 2: Resultados por Tipo de Tratamento\n")
cat("(Estatísticas resumidas do segundo estágio)\n\n")

tabela_2 <- resultados |>
  filter(!is.na(coef_ss)) |>
  group_by(tratamento) |>
  summarise(
    n_testes = n(),
    coef_medio = mean(coef_ss),
    coef_min = min(coef_ss),
    coef_max = max(coef_ss),
    f_stat_medio = mean(f_stat, na.rm = TRUE),
    p_value_median = median(p_value),
    significancia_5pct = sum(p_value < 0.05),
    .groups = "drop"
  ) |>
  mutate(across(where(is.numeric) & !c(n_testes, significancia_5pct), round, 4))

print(tabela_2)

# TABELA 3: Detalhamento de especificações
cat("\n\nTABELA 3: Força do Instrumento (F-statístico) por Especificação\n\n")

tabela_3 <- resultados |>
  filter(!is.na(f_stat)) |>
  group_by(especificacao, tratamento) |>
  summarise(
    f_medio = mean(f_stat),
    f_min = min(f_stat),
    f_max = max(f_stat),
    n_fraco = sum(f_stat < 10),
    .groups = "drop"
  ) |>
  arrange(desc(f_medio)) |>
  mutate(across(starts_with("f_"), round, 2))

print(tabela_3)

# ==============================================================================
# SEÇÃO 3: GRÁFICOS
# ==============================================================================

cat("\n\n", strrep("=", 80), "\n")
cat("GRÁFICOS\n")
cat(strrep("=", 80), "\n\n")

# GRÁFICO 1: Coeficientes do segundo estágio por tratamento
g1 <- resultados |>
  filter(!is.na(coef_ss)) |>
  ggplot(aes(x = tratamento, y = coef_ss, fill = outcome)) +
  geom_boxplot(alpha = 0.7) +
  facet_wrap(~especificacao, scales = "free_y") +
  theme_minimal() +
  labs(
    title = "Distribuição de Coeficientes (Segundo Estágio)",
    x = "Tipo de Tratamento",
    y = "Coeficiente",
    fill = "Outcome"
  ) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

print(g1)
ggsave(
  paste0(data.wd, "/grafico_coeficientes_ss.png"),
  plot = g1,
  width = 12,
  height = 8,
  dpi = 300
)
cat("✓ Gráfico salvo: grafico_coeficientes_ss.png\n")

# GRÁFICO 2: F-statístico por especificação
g2 <- resultados |>
  filter(!is.na(f_stat)) |>
  ggplot(aes(x = tratamento, y = f_stat, color = outcome)) +
  geom_point(size = 3, alpha = 0.6) +
  geom_hline(yintercept = 10, linetype = "dashed", color = "red", size = 1) +
  facet_wrap(~especificacao) +
  theme_minimal() +
  labs(
    title = "F-statístico do Primeiro Estágio por Especificação",
    subtitle = "Linha vermelha: limite de 10 (instrumento fraco)",
    x = "Tipo de Tratamento",
    y = "F-statístico",
    color = "Outcome"
  ) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

print(g2)
ggsave(
  paste0(data.wd, "/grafico_f_stat.png"),
  plot = g2,
  width = 12,
  height = 8,
  dpi = 300
)
cat("✓ Gráfico salvo: grafico_f_stat.png\n")

# GRÁFICO 3: P-values e significância
g3 <- resultados |>
  filter(!is.na(p_value)) |>
  mutate(
    sig = factor(
      case_when(
        p_value < 0.01 ~ "p < 0.01",
        p_value < 0.05 ~ "0.01 ≤ p < 0.05",
        p_value < 0.10 ~ "0.05 ≤ p < 0.10",
        TRUE ~ "p ≥ 0.10"
      ),
      levels = c("p < 0.01", "0.01 ≤ p < 0.05", "0.05 ≤ p < 0.10", "p ≥ 0.10")
    )
  ) |>
  ggplot(aes(x = sig, fill = sig)) +
  geom_bar() +
  facet_wrap(~outcome) +
  theme_minimal() +
  scale_fill_brewer(palette = "Set2") +
  labs(
    title = "Distribuição de P-values do Segundo Estágio",
    x = "Nível de Significância",
    y = "Número de testes",
    fill = "P-value"
  ) +
  theme(legend.position = "bottom")

print(g3)
ggsave(
  paste0(data.wd, "/grafico_p_values.png"),
  plot = g3,
  width = 10,
  height = 6,
  dpi = 300
)
cat("✓ Gráfico salvo: grafico_p_values.png\n")

# GRÁFICO 4: Coeficiente vs F-statístico (qualidade do instrumento)
g4 <- resultados |>
  filter(!is.na(coef_ss) & !is.na(f_stat)) |>
  ggplot(aes(x = f_stat, y = coef_ss, color = outcome)) +
  geom_point(size = 3, alpha = 0.6) +
  geom_vline(xintercept = 10, linetype = "dashed", color = "gray") +
  facet_wrap(~tratamento, scales = "free") +
  theme_minimal() +
  labs(
    title = "Relação entre Força do Instrumento e Coeficiente",
    x = "F-statístico (força do instrumento)",
    y = "Coeficiente do segundo estágio",
    color = "Outcome"
  )

print(g4)
ggsave(
  paste0(data.wd, "/grafico_f_vs_coef.png"),
  plot = g4,
  width = 12,
  height = 8,
  dpi = 300
)
cat("✓ Gráfico salvo: grafico_f_vs_coef.png\n")

# ==============================================================================
# SEÇÃO 4: ANÁLISE DE ROBUSTEZ
# ==============================================================================

cat("\n\n", strrep("=", 80), "\n")
cat("ANÁLISE DE ROBUSTEZ\n")
cat(strrep("=", 80), "\n\n")

# Comparar primeira e segunda especificação (com e sem FE Estado)
cat("ROBUSTEZ 1: Impacto de Efeitos Fixos de Estado\n\n")

esp1 <- resultados |>
  filter(grepl("Amostra completa$", especificacao)) |>
  select(tratamento, outcome, coef_ss, p_value) |>
  rename(coef_ss_sem_fe = coef_ss, p_value_sem_fe = p_value)

esp2 <- resultados |>
  filter(grepl("Amostra completa com FE Estado", especificacao)) |>
  select(tratamento, outcome, coef_ss, p_value) |>
  rename(coef_ss_com_fe = coef_ss, p_value_com_fe = p_value)

robustez_fe <- esp1 |>
  inner_join(esp2, by = c("tratamento", "outcome")) |>
  mutate(
    mudanca_coef = (coef_ss_com_fe - coef_ss_sem_fe) / abs(coef_ss_sem_fe) * 100,
    mudanca_sig = case_when(
      (p_value_sem_fe < 0.05) & (p_value_com_fe >= 0.05) ~ "Perdeu significância",
      (p_value_sem_fe >= 0.05) & (p_value_com_fe < 0.05) ~ "Ganhou significância",
      TRUE ~ "Mantém padrão"
    )
  ) |>
  select(tratamento, outcome, coef_ss_sem_fe, coef_ss_com_fe, mudanca_coef, mudanca_sig)

print(robustez_fe)

# Comparar amostras com e sem exclusão de pontas
cat("\n\nROBUSTEZ 2: Impacto de Excluir Extremidades das Ferrovias\n\n")

amostra_200 <- resultados |>
  filter(grepl("Distância ≤ 200km", especificacao)) |>
  filter(!grepl("Excluindo pontas", especificacao)) |>
  select(tratamento, outcome, coef_ss, p_value) |>
  rename(coef_ss_com_pontas = coef_ss, p_value_com_pontas = p_value)

amostra_200_sem_pontas <- resultados |>
  filter(grepl("Distância ≤ 200km", especificacao)) |>
  filter(grepl("Excluindo pontas", especificacao)) |>
  select(tratamento, outcome, coef_ss, p_value) |>
  rename(coef_ss_sem_pontas = coef_ss, p_value_sem_pontas = p_value)

robustez_pontas <- amostra_200 |>
  inner_join(amostra_200_sem_pontas, by = c("tratamento", "outcome")) |>
  mutate(
    mudanca_coef = (coef_ss_sem_pontas - coef_ss_com_pontas) / abs(coef_ss_com_pontas) * 100,
    mudanca_sig = case_when(
      (p_value_com_pontas < 0.05) & (p_value_sem_pontas >= 0.05) ~ "Perdeu significância",
      (p_value_com_pontas >= 0.05) & (p_value_sem_pontas < 0.05) ~ "Ganhou significância",
      TRUE ~ "Mantém padrão"
    )
  ) |>
  select(tratamento, outcome, coef_ss_com_pontas, coef_ss_sem_pontas, mudanca_coef, mudanca_sig)

print(robustez_pontas)

# ==============================================================================
# SEÇÃO 5: RECOMENDAÇÕES E CONCLUSÕES
# ==============================================================================

cat("\n\n", strrep("=", 80), "\n")
cat("RECOMENDAÇÕES E CONCLUSÕES\n")
cat(strrep("=", 80), "\n\n")

cat("RECOMENDAÇÕES:\n\n")

# 1. Instrumentos fracos
fraco_count <- sum(resultados$f_stat < 10, na.rm = TRUE)
fraco_pct <- (fraco_count / sum(!is.na(resultados$f_stat))) * 100

if (fraco_pct > 20) {
  cat(sprintf("⚠️ ATENÇÃO: %.1f%% dos testes têm instrumento fraco (F < 10)\n", fraco_pct))
  cat("   Considere: (1) Revisar o instrumento (rede sintética)\n")
  cat("              (2) Testar alternativas de tratamento\n")
  cat("              (3) Usar métodos robustos a instrumentos fracos (Anderson-Rubin)\n\n")
} else {
  cat(sprintf("✓ Instrumentos adequados: %.1f%% têm F ≥ 10\n\n", 100 - fraco_pct))
}

# 2. Heterogeneidade por treatment
cat("HETEROGENEIDADE POR TIPO DE TRATAMENTO:\n")
het_trat <- resultados |>
  filter(!is.na(coef_ss)) |>
  group_by(tratamento) |>
  summarise(
    sd_coef = sd(coef_ss),
    cv = sd_coef / mean(coef_ss),
    .groups = "drop"
  ) |>
  arrange(desc(cv))

for (i in 1:nrow(het_trat)) {
  cat(sprintf("  %s: CV = %.2f\n", het_trat$tratamento[i], het_trat$cv[i]))
}

cat("\n")

# 3. Significância dos resultados
sig_005 <- sum(resultados$p_value < 0.05, na.rm = TRUE)
total <- sum(!is.na(resultados$p_value))
sig_pct <- (sig_005 / total) * 100

cat(sprintf("SIGNIFICÂNCIA: %.1f%% dos coeficientes são significativos a 5%%\n", sig_pct))

# ==============================================================================
# SEÇÃO 6: EXPORTAR RELATÓRIO HTML
# ==============================================================================

cat("\n\n", strrep("=", 80), "\n")
cat("EXPORTANDO RELATÓRIOS\n")
cat(strrep("=", 80), "\n\n")

# Salvar tabelas como HTML
write_html_tables <- function(
    tabela, 
    filename, 
    caption = "Resultados",
    data_wd = data.wd) {
  
  html_content <- kable(
    tabela,
    format = "html",
    caption = caption,
    digits = 4
  ) |>
    kable_styling(
      bootstrap_options = c("striped", "hover"),
      full_width = FALSE
    )
  
  writeLines(
    as.character(html_content),
    paste0(data_wd, "/", filename)
  )
}

write_html_tables(tabela_1, "tabela_resultados_por_outcome.html", 
                  "Resultados por Especificação e Outcome")
cat("✓ Tabela 1 salva como HTML\n")

write_html_tables(tabela_2, "tabela_resultados_por_tratamento.html",
                  "Resultados por Tipo de Tratamento")
cat("✓ Tabela 2 salva como HTML\n")

write_html_tables(tabela_3, "tabela_f_estatistico.html",
                  "Força do Instrumento (F-statístico)")
cat("✓ Tabela 3 salva como HTML\n")

# ==============================================================================
# FIM DO SCRIPT
# ==============================================================================

cat("\n", strrep("=", 80), "\n")
cat("🎉 VISUALIZAÇÃO E ANÁLISE CONCLUÍDA!\n")
cat(strrep("=", 80), "\n")
cat("Finalizado em:", format(Sys.time(), "%d/%m/%Y %H:%M:%S"), "\n\n")
