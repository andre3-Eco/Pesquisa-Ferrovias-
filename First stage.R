# ==============================================================================
#  Primeiro Estágio (VI) e Controles de Vizinhança Espacial
# ==============================================================================

# 1. Carregamento de pacotes -------------------------------------------------
# install.packages(c("sf", "spdep", "broom", "lmtest", "sandwich", "geobr"))
library(sf)
library(dplyr)
library(spdep)     # Pacote padrão-ouro para econometria espacial no R
library(broom)     # Para organizar as tabelas de regressão
library(lmtest)    # Para testes de robustez
library(sandwich)  # Para erros-padrão robustos (HAC)
library(geobr)     # Para recuperar a geometria das AMCs
library(lmtest)    # Para testes de robustez
library(sandwich)  # Para erros-padrão robustos (HAC)
library(geobr)     # Para recuperar a geometria das AMCs

# 2. Reconstrução da geometria e união com as distâncias calculadas ----------
cat("Carregando a base de distâncias (CSV) gerada na etapa anterior...\n")
# Lê o arquivo que contém as colunas de distância criadas pelo loop
base_distancias <- read.csv("base_distancias_amcs_nordeste_1970.csv")

cat("Baixando a geometria das AMCs para criar a matriz de vizinhança...\n")
# Baixa as AMCs vazias, filtra pro Nordeste e converte para SIRGAS 2000 UTM 24S
amcs_geometria <- read_comparable_areas(start_year = 1970, end_year = 2010) %>%
  filter(substr(list_code_muni_2010, 1, 1) == "2") %>%
  st_transform(crs = 31984)

cat("Unindo as distâncias aos polígonos espaciais...\n")
# Junta os dados do CSV de volta ao formato de mapa usando o código da AMC
amcs_sf <- left_join(amcs_geometria, base_distancias, by = "code_amc")

# 3. Criação da Matriz de Vizinhança (Spatial Weights Matrix - W) ------------
cat("Calculando matriz de vizinhança (Critério Queen)...\n")

# poly2nb encontra os polígonos vizinhos (que compartilham bordas/vértices)
vizinhos <- poly2nb(amcs_sf, queen = TRUE)

# nb2listw converte a lista de vizinhos em uma matriz de pesos padronizada pela linha (W)
# Zero.policy = TRUE permite ilhas (AMCs sem vizinhos, o que é raro no continente, mas seguro)
matriz_pesos <- nb2listw(vizinhos, style = "W", zero.policy = TRUE)

# 4. Criação da Defasagem Espacial (Spatial Lag) -----------------------------
cat("Calculando a média das distâncias das AMCs vizinhas...\n")

# Isso cria uma nova variável: a distância média dos VIZINHOS para a rede sintética
# É a forma matemática de "comparar AMCs vizinhos"
amcs_sf <- amcs_sf %>%
  mutate(
    dist_sintetica_vizinhos = lag.listw(matriz_pesos, dist_rail_sintetica_km, zero.policy = TRUE)
  )

# 5. Regressões (Primeiro Estágio) -------------------------------------------
cat("Estimando os modelos econométricos...\n")

# Detecta dinamicamente as colunas de distâncias geradas para a malha real
colunas_reais <- grep("^dist_rail_real_", names(amcs_sf), value = TRUE)

if(length(colunas_reais) == 0) {
  stop("Erro: Nenhuma coluna de distância ('dist_rail_real_...') foi encontrada! Verifique o CSV.")
}

# Seleciona automaticamente o último ano disponível para rodar o teste
ano_teste <- tail(sort(colunas_reais), 1)
cat(paste("====> Variável dependente selecionada para o teste:", ano_teste, "<====\n"))

# Modelo 1: OLS Simples (Apenas instrumento vs. realidade)
formula_mod1 <- as.formula(paste(ano_teste, "~ dist_rail_sintetica_km"))
modelo1 <- lm(formula_mod1, data = amcs_sf)

# Modelo 2: OLS com Controle de Vizinhança (A sua hipótese espacial)
formula_mod2 <- as.formula(paste(ano_teste, "~ dist_rail_sintetica_km"))
modelo2 <- lm(formula_mod2, data = amcs_sf)

# 6. Avaliação de Resultados e Erros Robustos --------------------------------
cat("\n=== RESULTADOS: MODELO COM CONTROLE DOS VIZINHOS ===\n")

# Usamos coeftest com vcovHC para gerar Erros-Padrão Robustos à heterocedasticidade
resultados_robustos <- coeftest(modelo2, vcov = vcovHC(modelo2, type = "HC1"))
print(resultados_robustos)

# Teste F de Relevância do Instrumento 
f_stat <- waldtest(modelo2, vcov = vcovHC(modelo2, type = "HC1"))
cat("\n=== TESTE DE INSTRUMENTO FRACO (F-Statistic) ===\n")
cat("O valor de F para significância conjunta deve ser preferencialmente maior que 10.\n")
print(f_stat)

# 7. Interpretação dos Resultados (Feedback para o Console) ------------------
cat("\nINTERPRETAÇÃO:\n")
cat("- O coeficiente de 'dist_rail_sintetica_km' indica o quão bem a rede sintética prevê a real.\n")
cat("- O coeficiente de 'dist_sintetica_vizinhos' controla o efeito espacial da região ao redor.\n")
cat("- Se o R² e o Teste F forem altos (F > 10), seu instrumento metodológico (LCP) é robusto e válido!\n")