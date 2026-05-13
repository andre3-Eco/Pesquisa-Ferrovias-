# ==============================================================================
# SCRIPT: ATRIBUTOS DO ARQUIVO GPKG DAS FERROVIAS
# ==============================================================================

# Carregar pacotes
library(sf)
library(dplyr)

# 1. Carregar o arquivo de forma silenciosa
cat("Lendo o arquivo ferrovias_cronologicas.gpkg...\n")
ferrovias <- st_read("ferrovias_cronologicas.gpkg", quiet = TRUE)

# 2. Diagnóstico da Geometria (Crucial para o LCP)
cat("\n================ RESUMO DA GEOMETRIA ================\n")
cat("Tipo de geometria predominante: ", as.character(unique(st_geometry_type(ferrovias))), "\n")
cat("Total de linhas/segmentos desenhados no arquivo: ", nrow(ferrovias), "\n")


# 3. Diagnóstico das Colunas (Crucial para o Staggered DiD)
cat("\n================ COLUNAS DISPONÍVEIS ================\n")
print(names(ferrovias))

# 4. Amostra Real dos Dados (Sem poluir a tela com as coordenadas)
cat("\n================ AMOSTRA DOS DADOS (PRIMEIRAS 5 LINHAS) ================\n")
# st_drop_geometry tira o "peso" espacial apenas para visualizarmos a tabela
tabela_atributos <- st_drop_geometry(ferrovias)
print(head(tabela_atributos, 5))

# 5. Estrutura detalhada (Tipos de dados: numérico, texto, etc.)
cat("\n================ ESTRUTURA DOS DADOS ================\n")
glimpse(tabela_atributos)


# ==============================================================================
# SCRIPT: EXTRAÇÃO DE ORIGENS COSTEIRAS E ATRIBUIÇÃO DE HUBS EXÓGENOS
# ==============================================================================


library(sf)
library(tidyverse)
library(geobr)

# ------------------------------------------------------------------------------
# 1. LER E LIMPAR OS DADOS FRAGMENTADOS
# ------------------------------------------------------------------------------
cat("Lendo o arquivo ferrovias_cronologicas.gpkg...\n")
ferrovias <- st_read("ferrovias_cronologicas.gpkg", quiet = TRUE)

# Filtrar apenas o primeiro trecho construído de cada ferrovia (Marco Zero)
# Isso garante que só pegaremos os pontos que saem do litoral/origem primária
marcos_zero <- ferrovias %>% filter(cod_part == 1)

# ------------------------------------------------------------------------------
# 2. EXTRAIR A COORDENADA EXATA DA ORIGEM
# ------------------------------------------------------------------------------
cat("Extraindo as coordenadas de origem...\n")
# suppressWarnings esconde o aviso inofensivo do st_cast
origens_sf <- suppressWarnings(
  marcos_zero %>%
    st_cast("POINT") %>%
    group_by(id) %>%
    slice(1) %>%
    ungroup()
)

coords <- st_coordinates(origens_sf)
origens_sf <- origens_sf %>%
  mutate(
    lon_origem = coords[, 1],
    lat_origem = coords[, 2]
  )

# ------------------------------------------------------------------------------
# 3. IDENTIFICAR O ESTADO DE ORIGEM (Para saber pra onde a ferrovia vai)
# ------------------------------------------------------------------------------
cat("Cruzando origens com limites estaduais...\n")

estados_ne <- read_state(code_state = "all", year = 2010, showProgress = FALSE) %>%
  filter(abbrev_state %in% c("AL", "BA", "CE", "MA", "PB", "PE", "PI", "RN", "SE"))

# FIX CRÍTICO: Forçar o mapa do IBGE a ter a mesma projeção do seu arquivo GPKG
estados_ne <- st_transform(estados_ne, crs = st_crs(origens_sf))

# Agora o cruzamento espacial vai funcionar
origens_estado <- st_join(origens_sf, estados_ne, join = st_intersects)

# ------------------------------------------------------------------------------
# 4. GERAR AS ÂNCORAS EXÓGENAS (INLAND HUBS)
# ------------------------------------------------------------------------------
cat("Calculando centroides dos Inland Hubs Exógenos...\n")

# FIX CRÍTICO: Baixar apenas os estados específicos em vez de "NE"
muns_pe <- read_municipality(code_muni = "PE", year = 2010, showProgress = FALSE)
muns_ce <- read_municipality(code_muni = "CE", year = 2010, showProgress = FALSE)
muns_ba <- read_municipality(code_muni = "BA", year = 2010, showProgress = FALSE)

# HUB PE: Calha do Rio São Francisco (Cabrobó)
hub_pe <- muns_pe %>% filter(name_muni == "Cabrobó") %>% st_centroid()
coords_pe <- st_coordinates(hub_pe)

# HUB CE/RN: Epicentro da Seca de 1877 (Maciço Central Cearense)
hub_seca <- muns_ce %>% 
  filter(name_muni %in% c("Quixadá", "Quixeramobim", "Senador Pompeu")) %>% 
  st_union() %>% st_centroid()
coords_ce <- st_coordinates(hub_seca)

# HUB BA: Calha do Rio São Francisco (Juazeiro)
hub_ba <- muns_ba %>% filter(name_muni == "Juazeiro") %>% st_centroid()
coords_ba <- st_coordinates(hub_ba)

# ------------------------------------------------------------------------------
# 5. ASSOCIAÇÃO FINAL (A ENGENHARIA DA VARIÁVEL INSTRUMENTAL)
# ------------------------------------------------------------------------------
cat("Estruturando o dataframe final para exportação...\n")
df_final <- origens_estado %>%
  st_drop_geometry() %>% # Remove a geometria do QGIS para virar tabela pura
  mutate(
    hub_destino = case_when(
      abbrev_state %in% c("PE", "PB", "AL") ~ "Rio_SF_Cabrobo",
      abbrev_state %in% c("CE", "RN", "PI") ~ "Epicentro_Seca_1877",
      abbrev_state %in% c("BA", "SE") ~ "Rio_SF_Juazeiro",
      TRUE ~ "Nao_Identificado"
    ),
    lon_destino = case_when(
      abbrev_state %in% c("PE", "PB", "AL") ~ coords_pe[1, "X"],
      abbrev_state %in% c("CE", "RN", "PI") ~ coords_ce[1, "X"],
      abbrev_state %in% c("BA", "SE") ~ coords_ba[1, "X"]
    ),
    lat_destino = case_when(
      abbrev_state %in% c("PE", "PB", "AL") ~ coords_pe[1, "Y"],
      abbrev_state %in% c("CE", "RN", "PI") ~ coords_ce[1, "Y"],
      abbrev_state %in% c("BA", "SE") ~ coords_ba[1, "Y"]
    ),
    tipo_instrumento = case_when(
      abbrev_state %in% c("PE", "PB", "BA", "SE", "AL") ~ "Projeto_Imperial",
      abbrev_state %in% c("CE", "RN", "PI") ~ "Seca_Clima"
    )
  ) %>%
  # Seleciona só as colunas que importam para o LCP e Econometria
  select(id, Nome, ano_inaug, abbrev_state, lon_origem, lat_origem, 
         hub_destino, lon_destino, lat_destino, tipo_instrumento)

# 6. EXPORTAR PARA CSV
write_csv(df_final, "hubs_lcp_nordeste.csv")
cat("\nSUCESSO! Arquivo 'hubs_lcp_nordeste.csv' gerado.\n")