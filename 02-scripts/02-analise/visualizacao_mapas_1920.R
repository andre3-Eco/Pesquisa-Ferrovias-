# ==============================================================================
# VISUALIZAÇÃO DOS DADOS DE 1920 - MAPAS DE CALOR (CHOROPLETH) POR AMC
# ==============================================================================

library(sf)
library(ggplot2)
library(dplyr)
library(tidyr)
library(readr)
library(stringr)

# Configurar Diretório (adaptado do projeto)
if (!exists("data.wd")) {
  data.wd <- getwd()
}
setwd(data.wd)

# 1. Configurar Diretórios e Carregar Dados
dir.create("03-resultados/mapas/1920", showWarnings = FALSE, recursive = TRUE)

crs_projeto <- 31984

# Carrega os dados de 1920
# read_csv preserva os nomes das colunas (mesmo com parênteses)
df_1920 <- read_csv("01-dados/dados_1920_final_completo.csv", show_col_types = FALSE)

# Renomear variáveis para remover caracteres especiais (parênteses)
df_1920 <- df_1920 %>%
  rename(
    sabem_7a14 = `sabem(7a14)`,
    nsabem_7a14 = `nsabem(7a14)`,
    sabem_15a = `sabem(15a)`,
    nsabem_15a = `nsabem(15a)`
  )

# Carrega a malha de AMCs
amcs_ne <- readRDS("01-dados/processados/amcs_geometria.rds") %>% 
  st_transform(crs_projeto)

# 2. Mapeamento Município -> AMC
# Cria uma tabela de equivalência expandindo os códigos separados por vírgula
amc_mapping <- amcs_ne %>%
  st_drop_geometry() %>%
  select(code_amc, list_code_muni_2010) %>%
  separate_rows(list_code_muni_2010, sep = ",") %>%
  mutate(code_muni = as.numeric(list_code_muni_2010))

# 3. Agregar Dados de 1920 ao nível de AMC
# Como as variáveis são contagens, usamos sum() para obter os totais por AMC
df_amc <- df_1920 %>%
  left_join(amc_mapping, by = "code_muni") %>%
  # Remove NAs em code_amc (municípios que não bateram, embora improvável se forem do NE)
  filter(!is.na(code_amc)) %>%
  group_by(code_amc) %>%
  summarise(
    sabem_7a14 = sum(sabem_7a14, na.rm = TRUE),
    nsabem_7a14 = sum(nsabem_7a14, na.rm = TRUE),
    sabem_15a = sum(sabem_15a, na.rm = TRUE),
    nsabem_15a = sum(nsabem_15a, na.rm = TRUE),
    numeroestabelecimento = sum(numeroestabelecimento, na.rm = TRUE),
    commaquinas = sum(commaquinas, na.rm = TRUE),
    cominstruagra = sum(cominstruagra, na.rm = TRUE)
  )

# Junta os dados agregados com a geometria das AMCs
amcs_plot <- amcs_ne %>%
  left_join(df_amc, by = "code_amc")

# Fronteira do Nordeste para estética
fronteira_ne <- st_union(amcs_ne)

# 4. Função para Plotar Mapa (Mapa de Calor / Choropleth)
plotar_mapa <- function(var_name, titulo, legenda) {
  p <- ggplot() +
    # Fundo do mapa com a variável
    geom_sf(data = amcs_plot, aes(fill = !!sym(var_name)), color = "white", linewidth = 0.1) +
    # Contorno geral
    geom_sf(data = fronteira_ne, fill = NA, color = "black", linewidth = 0.5) +
    # Escala de cores (viridis magma)
    scale_fill_viridis_c(option = "magma", direction = -1, name = legenda, na.value = "gray90", 
                         labels = scales::comma_format(big.mark = ".", decimal.mark = ",")) +
    theme_void() +
    labs(
      title = titulo,
      subtitle = "Agregado por AMC - Dados de 1920"
    ) +
    theme(
      legend.position = "bottom",
      plot.title = element_text(face = "bold", size = 14, hjust = 0.5),
      plot.subtitle = element_text(color = "grey40", size = 11, hjust = 0.5),
      legend.key.width = unit(2, "cm")
    )
  
  # Salvar
  arquivo <- paste0("03-resultados/mapas/1920/mapa_", var_name, ".png")
  ggsave(arquivo, plot = p, width = 8, height = 8, dpi = 300, bg = "white")
  cat(sprintf("✅ Mapa salvo: %s\n", arquivo))
}

# 5. Gerar todos os mapas
cat("Iniciando a geração dos mapas...\n")
plotar_mapa("sabem_7a14", "Sabe Ler e Escrever (7 a 14 anos)", "População")
plotar_mapa("nsabem_7a14", "Não Sabe Ler (7 a 14 anos)", "População")
plotar_mapa("sabem_15a", "Sabe Ler e Escrever (15+ anos)", "População")
plotar_mapa("nsabem_15a", "Não Sabe Ler (15+ anos)", "População")
plotar_mapa("numeroestabelecimento", "Número de Estabelecimentos", "Qtd")
plotar_mapa("commaquinas", "Estabelecimentos com Máquinas", "Qtd")
plotar_mapa("cominstruagra", "Com Instrução Agrícola", "Qtd")
cat("Todos os mapas foram gerados com sucesso!\n")
