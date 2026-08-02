# ==============================================================================
# VISUALIZAÇÃO DE RESULTADOS: Efeitos Diretos (Subamostras - Maquinário 1920)
# ==============================================================================

library(tidyverse)
library(patchwork)

if (!exists("data.wd")) {
  data.wd <- "C:/Users/André Elias/Documents/Pesquisa (Ferrovias)"
}
setwd(data.wd)

dir.create("03-resultados/plots", showWarnings = FALSE, recursive = TRUE)

df_resultados <- read_csv("03-resultados/csv/second_stage_1920_semiarido_maquinario.csv", show_col_types = FALSE)

# 2. Manipulação de Dados (Filtragem e Renomeação)
df_plot <- df_resultados |>
  # Manter apenas as duas subamostras de interesse (ignorando o grupo "Geral")
  filter(subamostra %in% c("Semiarido_Dummy1", "Nao_Semiarido_Dummy0")) |> 
  mutate(
    ano_outcome = ano_tratamento,
    
    # Isolar os outcomes de maquinário e instrumentos agrícolas
    tipo_outcome = case_when(
      outcome_var == "pct_commaquinas" ~ "Machinery per Estab.",
      outcome_var == "pct_cominstruagra" ~ "Agri. Instruments per Estab.",
      TRUE ~ "Drop"
    ),
    
    ci_lower = coeficiente - (1.96 * erro_padrao),
    ci_upper = coeficiente + (1.96 * erro_padrao),
    
    # Criar variável em inglês para a legenda
    Sample = case_when(
      subamostra == "Semiarido_Dummy1" ~ "Semi-arid",
      subamostra == "Nao_Semiarido_Dummy0" ~ "Non Semi-arid"
    )
  ) |>
  filter(tipo_outcome != "Drop") |>
  filter(!is.na(ano_outcome))

# Filtrar para décadas para o gráfico ficar limpo
anos_destaque <- c(min(df_plot$ano_outcome), seq(1870, 1920, by = 10), max(df_plot$ano_outcome))
anos_selecionados <- unique(df_plot$ano_outcome)[
  map_int(anos_destaque, ~ which.min(abs(unique(df_plot$ano_outcome) - .x)))
] |> unique() |> sort()

df_plot <- df_plot |> filter(ano_outcome %in% anos_selecionados)

# Estruturando os fatores para garantir a ordem lógica na legenda
df_plot <- df_plot |> mutate(Sample = factor(Sample, levels = c("Semi-arid", "Non Semi-arid")))

# Separar os dados para plotagem independente
df_maq <- df_plot |> filter(tipo_outcome == "Machinery per Estab.")
df_instru <- df_plot |> filter(tipo_outcome == "Agri. Instruments per Estab.")

# 3. Definição de Cores (Replicando o verde e roxo originais)
cores <- c("Semi-arid"     = "#5c4163", # Roxo escuro
           "Non Semi-arid" = "#80c47d") # Verde claro

# 4. Tema Customizado Clássico
tema_customizado <- theme_minimal() +
  theme(
    panel.grid.major = element_line(linetype = "dashed", color = "gray90"),
    panel.grid.minor = element_line(linetype = "dashed", color = "gray95"),
    axis.line = element_line(color = "black", linewidth = 0.6),
    axis.ticks = element_line(color = "black", linewidth = 0.6),
    axis.text = element_text(color = "black", size = 10),
    axis.text.x = element_text(angle = 45, hjust = 1),
    axis.title = element_text(color = "black", size = 11),
    plot.title = element_text(size = 13, face = "bold", hjust = 0),
    legend.title = element_text(face = "bold"),
    legend.background = element_blank(),
    legend.key = element_blank()
  )

pd <- position_dodge(width = 0.6) 

# 5. Construir o Gráfico A (Maquinário)
plot_maq <- ggplot(df_maq, aes(x = as.factor(ano_outcome), y = coeficiente, color = Sample)) +
  geom_hline(yintercept = 0, color = "gray30", linewidth = 0.8) +
  geom_errorbar(aes(ymin = ci_lower, ymax = ci_upper),
                position = pd, width = 0, linewidth = 0.8) +
  geom_point(position = pd, shape = 21, fill = "white", size = 2.5, stroke = 1.2) +
  scale_color_manual(values = cores) +
  scale_y_continuous(expand = expansion(mult = c(0.2, 0.2))) +
  labs(title = "A. Machinery per Estab.", x = "Year", y = "Marginal Effect") +
  tema_customizado

# 6. Construir o Gráfico B (Instrumentos Agrícolas)
plot_instru <- ggplot(df_instru, aes(x = as.factor(ano_outcome), y = coeficiente, color = Sample)) +
  geom_hline(yintercept = 0, color = "gray30", linewidth = 0.8) +
  geom_errorbar(aes(ymin = ci_lower, ymax = ci_upper),
                position = pd, width = 0, linewidth = 0.8) +
  geom_point(position = pd, shape = 21, fill = "white", size = 2.5, stroke = 1.2) +
  scale_color_manual(values = cores) +
  scale_y_continuous(expand = expansion(mult = c(0.2, 0.2))) +
  labs(title = "B. Agri. Instruments per Estab.", x = "Year", y = "") +
  tema_customizado

# 7. Combinar os gráficos e coletar a legenda (Rodapé unificado)
grafico_final <- (plot_maq + plot_instru) + 
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
  filename = "03-resultados/plots/direct_effects_maquinario_subsamples_1920.png",
  plot = grafico_final,
  width = 12, 
  height = 5.5, 
  dpi = 300,
  bg = "white"
)

cat("Gráfico exportado: 03-resultados/plots/direct_effects_maquinario_subsamples_1920.png\n")
