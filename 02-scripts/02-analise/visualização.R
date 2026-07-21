# ==============================================================================
# VISUALIZAÇÃO DE RESULTADOS
#
# Gera gráficos de coeficientes (Marginal Effects) análogos à literatura,
# exibindo a persistência dos choques ferroviários (1880-1950) sobre o PIB 
# e a População ao longo das décadas (1970-2023).
# ==============================================================================

library(tidyverse)
library(ggplot2)

if (!exists("data.wd")) {
  data.wd <- normalizePath(file.path(getwd(), "..", ".."))
}
setwd(data.wd)

# 1. Garantir diretório de saída
dir.create("03-resultados/plots", showWarnings = FALSE, recursive = TRUE)

# 2. Carregar a base de resultados do 2º Estágio
df_resultados <- read_csv("03-resultados/csv/second_stage_persistencia_longo_prazo.csv", show_col_types = FALSE)

# 3. Manipulação de Dados para o Gráfico
df_plot <- df_resultados |>
  mutate(
    # Extrair o ano do outcome da string (ex: "log(pib_1970)" -> 1970)
    ano_outcome = as.numeric(str_extract(outcome_var, "\\d{4}")),
    
    # Classificar o painel (Fator para os facets do ggplot)
    tipo_outcome = case_when(
      str_detect(outcome_var, "pib") ~ "A. Efeito no PIB Local (log)",
      str_detect(outcome_var, "pop") ~ "B. Efeito na População (log)",
      TRUE ~ "Outros"
    ),
    
    # Calcular Intervalos de Confiança de 95% (Z-score = 1.96)
    ci_lower = coeficiente - (1.96 * erro_padrao),
    ci_upper = coeficiente + (1.96 * erro_padrao),
    
    # Transformar o ano de tratamento em fator discreto para agrupar as cores
    tratamento = as.factor(ano_tratamento)
  ) |>
  # Remover qualquer NA residual para não quebrar o plot
  filter(!is.na(ano_outcome))

# 4. Construção do Gráfico (Padrão Acadêmico)
# O position_dodge(width = 3) afasta as barras lateralmente em 3 anos no eixo X
pd <- position_dodge(width = 3)

plot_persistencia <- ggplot(df_plot, aes(x = ano_outcome, y = coeficiente, color = tratamento, shape = tratamento)) +
  
  # Linha do Zero (Efeito Nulo)
  geom_hline(yintercept = 0, color = "black", size = 0.5) +
  
  # Point estimates e Intervalos de Confiança
  geom_pointrange(aes(ymin = ci_lower, ymax = ci_upper), position = pd, size = 0.5, fatten = 3) +
  
  # Divisão em dois painéis: PIB e População
  facet_wrap(~ tipo_outcome, scales = "free_y", ncol = 2) +
  
  # Escalas e Cores (Escala Viridis é daltônico-amigável e tem alto contraste em impressão PB)
  scale_color_viridis_d(option = "cividis", end = 0.9) +
  scale_x_continuous(breaks = seq(1970, 2023, by = 10)) +
  
  # Rótulos
  labs(
    x = "Ano de Observação (Outcome)",
    y = "Efeito Marginal da Dens. Ferroviária",
    color = "Choque Ferroviário (Ano)",
    shape = "Choque Ferroviário (Ano)"
  ) +
  
  # Tema limpo e análogo à imagem de referência
  theme_bw(base_size = 12) +
  theme(
    panel.grid.major.x = element_blank(),                       # Remove grades verticais
    panel.grid.minor = element_blank(),                         # Remove todas as grades menores
    panel.grid.major.y = element_line(linetype = "dashed", color = "gray85"), # Grade horizontal tracejada
    strip.background = element_blank(),                         # Fundo transparente no título do facet
    strip.text = element_text(face = "bold", size = 13, hjust = 0), # Título alinhado à esquerda
    legend.position = "bottom",                                 # Legenda inferior
    legend.title = element_text(face = "bold"),
    plot.margin = margin(t = 10, r = 15, b = 10, l = 10)
  )

# Exibe o gráfico no visualizador do RStudio
print(plot_persistencia)

# 5. Exportar em Alta Resolução (300 DPI) para artigos
ggsave(
  filename = "03-resultados/plots/efeito_persistencia_longo_prazo.png",
  plot = plot_persistencia,
  width = 12, 
  height = 5, 
  dpi = 300,
  bg = "white"
)

cat("Gráfico gerado com sucesso e salvo em: 03-resultados/plots/efeito_persistencia_longo_prazo.png\n")