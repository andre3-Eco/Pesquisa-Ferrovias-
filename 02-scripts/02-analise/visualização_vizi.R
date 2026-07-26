# ==============================================================================
# VISUALIZAÇÃO DE RESULTADOS: Atendidos vs Não Atendidos (Spillovers - 1950)
# ==============================================================================

library(tidyverse)
library(patchwork)

# 1. Configuração de Diretório e Carregamento
if (!exists("data.wd")) {
  data.wd <- normalizePath(file.path(getwd(), "..", ".."))
}
setwd(data.wd)

dir.create("03-resultados/plots", showWarnings = FALSE, recursive = TRUE)

df_resultados <- read_csv("03-resultados/csv/second_stage_spillover_vizinhos_multidimensional_1950.csv", show_col_types = FALSE)

# 2. Manipulação de Dados (Filtragem e Renomeação)
df_plot <- df_resultados |>
  # Filtrar apenas os municípios da linha férrea e os vizinhos (excluindo "Geral")
  filter(subamostra %in% c("Atendidos_Dummy1", "Nao_Atendidos_Dummy0")) |> 
  mutate(
    ano_outcome = as.numeric(str_extract(outcome_var, "\\d{4}")),
    
    # Isolar estritamente o PIB Total e População Total
    tipo_outcome = case_when(
      str_detect(outcome_var, "^pib \\(") ~ "GDP",
      str_detect(outcome_var, "^pop_total \\(") ~ "Population",
      TRUE ~ "Drop"
    ),
    
    ci_lower = coeficiente - (1.96 * erro_padrao),
    ci_upper = coeficiente + (1.96 * erro_padrao),
    
    # Criar variável em inglês para a legenda
    Sample = case_when(
      subamostra == "Atendidos_Dummy1" ~ "Served",
      subamostra == "Nao_Atendidos_Dummy0" ~ "Not Served"
    )
  ) |>
  filter(tipo_outcome != "Drop") |>
  filter(!is.na(ano_outcome)) |>
  # ADIÇÃO CRÍTICA: Incluídos 2021 (PIB) e 2022 (Censo População) no vetor
  filter(ano_outcome %in% c(1970, 1980, 1991, 2000, 2010, 2021, 2022))

# Estruturando os fatores para garantir a ordem lógica na legenda
df_plot <- df_plot |> mutate(Sample = factor(Sample, levels = c("Served", "Not Served")))

# Separar os dados para plotagem independente
df_gdp <- df_plot |> filter(tipo_outcome == "GDP")
df_pop <- df_plot |> filter(tipo_outcome == "Population")

# 3. Definição de Cores (Roxo para o Tratado, Verde para o Controle/Vizinho)
cores <- c("Served"     = "#5c4163", 
           "Not Served" = "#80c47d") 

# 4. Tema Customizado Clássico
tema_customizado <- theme_minimal() +
  theme(
    panel.grid.major = element_line(linetype = "dashed", color = "gray90"),
    panel.grid.minor = element_line(linetype = "dashed", color = "gray95"),
    axis.line = element_line(color = "black", linewidth = 0.6),
    axis.ticks = element_line(color = "black", linewidth = 0.6),
    axis.text = element_text(color = "black", size = 10),
    axis.title = element_text(color = "black", size = 11),
    plot.title = element_text(size = 13, face = "bold", hjust = 0),
    legend.title = element_text(face = "bold"),
    legend.background = element_blank(),
    legend.key = element_blank()
  )

pd <- position_dodge(width = 0.6) 

# 5. Construir o Gráfico A (GDP)
plot_gdp <- ggplot(df_gdp, aes(x = as.factor(ano_outcome), y = coeficiente, color = Sample)) +
  geom_hline(yintercept = 0, color = "gray30", linewidth = 0.8) +
  geom_errorbar(aes(ymin = ci_lower, ymax = ci_upper),
                position = pd, width = 0, linewidth = 0.8) +
  geom_point(position = pd, shape = 21, fill = "white", size = 2.5, stroke = 1.2) +
  scale_color_manual(values = cores) +
  scale_y_continuous(expand = expansion(mult = c(0.2, 0.2))) +
  labs(title = "A. Local GDP (log)", x = "Year", y = "Marginal Effect") +
  tema_customizado

# 6. Construir o Gráfico B (Population)
plot_pop <- ggplot(df_pop, aes(x = as.factor(ano_outcome), y = coeficiente, color = Sample)) +
  geom_hline(yintercept = 0, color = "gray30", linewidth = 0.8) +
  geom_errorbar(aes(ymin = ci_lower, ymax = ci_upper),
                position = pd, width = 0, linewidth = 0.8) +
  geom_point(position = pd, shape = 21, fill = "white", size = 2.5, stroke = 1.2) +
  scale_color_manual(values = cores) +
  scale_y_continuous(expand = expansion(mult = c(0.2, 0.2))) +
  labs(title = "B. Population (log)", x = "Year", y = "") +
  tema_customizado

# 7. Combinar os gráficos e coletar a legenda (Rodapé unificado)
grafico_final <- (plot_gdp + plot_pop) + 
  plot_layout(guides = "collect") & 
  theme(
    legend.position = "bottom",
    legend.direction = "horizontal",
    legend.box.margin = margin(t = 10) 
  )

# Exibir o resultado
print(grafico_final)

# 8. Exportar
ggsave(
  filename = "03-resultados/plots/spillover_effects_1950.png",
  plot = grafico_final,
  width = 12, 
  height = 5.5, 
  dpi = 300,
  bg = "white"
)

cat("Gráfico exportado: 03-resultados/plots/spillover_effects_1950.png\n")