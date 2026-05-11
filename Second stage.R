# ==============================================================================
# Segundo Estágio (IV/2SLS) - Impacto das Ferrovias na População
# ==============================================================================

# 1. Carregamento de pacotes -------------------------------------------------
install.packages(c("tidyverse", "sf", "geobr", "AER", "fixest", "spdep"))
library(tidyverse)
library(sf)
library(geobr)
library(AER)    # Para regressão IV clássica (ivreg)
library(fixest) # Para modelos IV de alta performance e efeitos fixos (feols)
library(spdep)

# 2. Carregamento e Limpeza dos Dados de População ---------------------------
cat("Lendo dados de população municipal...\n")
pop_raw <- população

sf_use_s2(FALSE)

pop_clean <- pop_raw %>%
  rename(code_muni = `Cód.`) %>%
  mutate(code_muni = as.character(code_muni))

# 3. Obtenção do Dicionário AMC (1970-2010) via geobr ------------------------
cat("Obtendo mapeamento de Municípios para AMCs...\n")
amc_lookup <- read_comparable_areas(start_year = 1970, end_year = 2010) %>%
  st_drop_geometry() %>% # CORREÇÃO 2: Remove a geometria para não bugar o join de dados!
  select(code_muni = list_code_muni_2010, code_amc) %>%
  mutate(code_muni = as.character(code_muni))

# 4. Agregação: Município -> AMC ---------------------------------------------
cat("Agregando população municipal para o nível de AMC...\n")
pop_amc <- pop_clean %>%
  inner_join(amc_lookup, by = "code_muni") %>%
  group_by(code_amc) %>%
  summarise(across(starts_with("20"), sum, na.rm = TRUE)) %>%
  ungroup()

# 5. Cruzamento com os dados de Distância ------------------------------------
cat("Cruzando a população agregada com as distâncias ferroviárias...\n")
base_distancias <- read_csv("base_distancias_amcs_nordeste_1970.csv")

base_iv <- pop_amc %>%
  inner_join(base_distancias, by = "code_amc")

# 6. Preparação para a Regressão Espacial (Vizinhos) -------------------------
cat("Recuperando a geometria espacial corrigida para controle de vizinhança...\n")
amcs_geometria <- read_comparable_areas(start_year = 1970, end_year = 2010) %>%
  filter(substr(list_code_muni_2010, 1, 1) == "2") %>%
  distinct(code_amc, .keep_all = TRUE) %>%
  st_make_valid() %>% # CORREÇÃO 3: Força o R a consertar polígonos autoinserseccionados
  st_transform(31984)

# Une os polígonos consertados com a nossa base final
base_iv_sf <- amcs_geometria %>%
  inner_join(base_iv, by = "code_amc")

# Cria a Matriz de Vizinhança
vizinhos <- poly2nb(base_iv_sf, queen = TRUE)
pesos <- nb2listw(vizinhos, style = "W", zero.policy = TRUE)

# Cria a Defasagem (Média da distância sintética dos vizinhos)
base_iv_sf$dist_sintetica_vizinhos <- lag.listw(pesos, base_iv_sf$dist_rail_sintetica_km, zero.policy = TRUE)

# 7. Estimativa do Segundo Estágio (IV-2SLS) ---------------------------------
cat("\n=== ESTIMANDO O SEGUNDO ESTÁGIO (IV) ===\n")

# Extraindo dinamicamente o último ano da malha real para o modelo
colunas_reais <- grep("^dist_rail_real_", names(base_iv_sf), value = TRUE)
ano_teste_real <- tail(sort(colunas_reais), 1)

# Montando a fórmula do modelo de Variável Instrumental
# log(População 2021) ~ Controle_Vizinho | Endógena(Real) ~ Instrumento(Sintética)
formula_iv <- as.formula(
  paste("log(`2003`) ~ dist_sintetica_vizinhos |", ano_teste_real, "~ dist_rail_sintetica_km")
)

modelo_iv <- feols(formula_iv, data = base_iv_sf)

print(summary(modelo_iv))

# 8. Exportação dos Resultados -----------------------------------------------
cat("\nSalvando base final de AMCs para análise (formato rds puro, mais estável)...\n")
saveRDS(base_iv_sf, "base_final_amcs_iv_populacao.rds")