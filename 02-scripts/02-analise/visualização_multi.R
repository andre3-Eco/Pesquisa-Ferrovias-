# ==============================================================================
# VISUALIZAÇÃO DE RESULTADOS: EFEITOS MULTIDIMENSIONAIS (Tratamento 1950)
# ==============================================================================

library(tidyverse)
library(patchwork)

# 1. Configuração de Diretório e Carregamento
if (!exists("data.wd")) {
  data.wd <- normalizePath(file.path(getwd(), "..", ".."))
}
setwd(data.wd)

dir.create("03-resultados/plots", showWarnings = FALSE, recursive = TRUE)

df_resultados <- read_csv("03-resultados/csv/second_stage_multidimensional_results_1950.csv", show_col_types = FALSE)

# 2. Manipulação de Dados (Extração de Categorias)
df_plot <- df_resultados |>
  mutate(
    ano_outcome = as.numeric(str_extract(outcome_var, "\\d{4}")),
    
    categoria = case_when(
      str_detect(outcome_var, "^pibag") ~ "Agriculture",
      str_detect(outcome_var, "^pibi") ~ "Industry",
      str_detect(outcome_var, "^pibse") ~ "Services",
      str_detect(outcome_var, "^adh_idhm \\(") ~ "General HDI", 
      str_detect(outcome_var, "^adh_idhm_r") ~ "Income HDI",
      str_detect(outcome_var, "^tx_urbanizacao") ~ "Urbanization Rate",
      TRUE ~ "Drop"
    ),
    
    painel = case_when(
      categoria %in% c("Agriculture", "Industry", "Services") ~ "Panel A",
      categoria %in% c("General HDI", "Income HDI", "Urbanization Rate") ~ "Panel B",
      TRUE ~ "Drop"
    ),
    
    ci_lower = coeficiente - (1.96 * erro_padrao),
    ci_upper = coeficiente + (1.96 * erro_padrao)
  ) |>
  filter(painel != "Drop") |>
  filter(!is.na(ano_outcome))

# 3. Filtragens Específicas por Painel
# Painel A: Décadas de 1970 a 2020
df_panel_a <- df_plot |> 
  filter(painel == "Panel A") |>
  filter(ano_outcome %in% c(1970, 1980, 1990, 2000, 2010, 2020)) |>
  mutate(categoria = factor(categoria, levels = c("Agriculture", "Industry", "Services")))

# Painel B: Anos Censitários do IDH e Tx Urbanização (1991, 2000, 2010)
df_panel_b <- df_plot |> 
  filter(painel == "Panel B") |>
  filter(ano_outcome %in% c(1991, 2000, 2010)) |>
  mutate(categoria = factor(categoria, levels = c("General HDI", "Income HDI", "Urbanization Rate")))

# 4. Definição de Cores 
cores_a <- c("Agriculture" = "#5c4163", 
             "Industry"    = "#80c47d", 
             "Services"    = "#d4a373") 

cores_b <- c("General HDI"       = "#5c4163", 
             "Income HDI"        = "#80c47d", 
             "Urbanization Rate" = "#d4a373") 

# 5. Tema Customizado (Sem rotação no eixo X)
tema_customizado <- theme_minimal() +
  theme(
    panel.grid.major = element_line(linetype = "dashed", color = "gray90"),
    panel.grid.minor = element_line(linetype = "dashed", color = "gray95"),
    axis.line = element_line(color = "black", linewidth = 0.6),
    axis.ticks = element_line(color = "black", linewidth = 0.6),
    axis.text.y = element_text(color = "black", size = 10),
    # Como filtramos os anos, o eixo X fica mais limpo, logo angle = 0
    axis.text.x = element_text(color = "black", size = 10, angle = 0, hjust = 0.5), 
    axis.title = element_text(color = "black", size = 11),
    plot.title = element_text(size = 13, hjust = 0),
    legend.title = element_text(face = "bold"),
    legend.background = element_blank(),
    legend.key = element_blank(),
    legend.position = "bottom" 
  )

pd <- position_dodge(width = 0.6) 

# 6. Construir o Gráfico A (PIB Setorial)
plot_a <- ggplot(df_panel_a, aes(x = as.factor(ano_outcome), y = coeficiente, color = categoria)) +
  geom_hline(yintercept = 0, color = "gray30", linewidth = 0.8) +
  geom_errorbar(aes(ymin = ci_lower, ymax = ci_upper),
                position = pd, width = 0, linewidth = 0.8) +
  geom_point(position = pd, shape = 21, fill = "white", size = 2.5, stroke = 1.2) +
  scale_color_manual(values = cores_a) +
  scale_y_continuous(expand = expansion(mult = c(0.2, 0.2))) +
  labs(title = "A. Sectoral GDP", x = "Year", y = "Marginal Effect", color = "Sector:") +
  tema_customizado

# 7. Construir o Gráfico B (Indicadores Sociais)
plot_b <- ggplot(df_panel_b, aes(x = as.factor(ano_outcome), y = coeficiente, color = categoria)) +
  geom_hline(yintercept = 0, color = "gray30", linewidth = 0.8) +
  geom_errorbar(aes(ymin = ci_lower, ymax = ci_upper),
                position = pd, width = 0, linewidth = 0.8) +
  geom_point(position = pd, shape = 21, fill = "white", size = 2.5, stroke = 1.2) +
  scale_color_manual(values = cores_b) +
  scale_y_continuous(expand = expansion(mult = c(0.2, 0.2))) +
  labs(title = "B. HDI and Urbanization", x = "Year", y = "", color = "Indicator:") +
  tema_customizado

# 8. Combinar os gráficos lado a lado
grafico_final <- plot_a + plot_b

print(grafico_final)

# 9. Exportar
ggsave(
  filename = "03-resultados/plots/multidimensional_effects_1950.png",
  plot = grafico_final,
  width = 12, # A largura pode voltar para 12 sem problemas de sobreposição
  height = 6.5, 
  dpi = 300,
  bg = "white"
)

cat("Gráfico exportado: 03-resultados/plots/multidimensional_effects_1950.png\n")