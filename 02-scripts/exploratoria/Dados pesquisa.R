library(tidyverse)

# 1. Definir os anos
anos_cols <- c("1872", "1890", "1910", "1920", "1940", "1950", 
               "1960", "1970", "1980", "1991", "1996", "2000", 
               "2007", "2010", "2022")

# 2. Processamento com correção de tipos (Join entre Characters)
df_final <- df_dist %>%
  # Converte a string em lista e "explode"
  mutate(list_code_muni_2010 = strsplit(as.character(list_code_muni_2010), ",")) %>%
  unnest(list_code_muni_2010) %>%
  
  # AQUI ESTÁ A MUDANÇA: Garantir que seja CHARACTER para bater com a base popula
  mutate(list_code_muni_2010 = as.character(list_code_muni_2010)) %>%
  
  # O JOIN: Agora os dois lados são character
  left_join(popula %>% mutate(Codigo = as.character(Codigo)) %>% select(Codigo, all_of(anos_cols)), 
            by = c("list_code_muni_2010" = "Codigo")) %>%
  
  # Agrupamento e Soma
  group_by(code_amc) %>%
  summarise(across(all_of(anos_cols), ~sum(as.numeric(.x), na.rm = TRUE)),
            municipios_na_amc = paste(list_code_muni_2010, collapse = ",")) %>%
  ungroup()