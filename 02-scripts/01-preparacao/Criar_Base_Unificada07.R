# =============================================================================
# Etapa 07
#
# Script mestre para criar a base de dados unificada com foco em 
# tratamento de densidade de buffer para análise IV de ferrovias no Nordeste
#
# Este script integra:
# 1. Base de tratamento: densidade de buffer (de base_buffer.R)
# 2. Controles climáticos (de 8_controles_clima.R)
# 3. Controles de solo (de 9_controles_solo.R)
# 4. Controles hidrológicos (de 10_controles_rios.R)
# 5. Abreviaturas de estado (de 5_Adicionar_State_Abbr.R)
# 6. Outcomes de desenvolvimento (de 7_Extrair_Outcomes_Desenvolvimento.R)
#
# Saída: base_completa_integrada_buffer.csv (ou .rds)
# =============================================================================

# 0. CONFIGURAÇÕES INICIAIS ---------------------------------------------------

if (!exists("data.wd")) data.wd <- getwd()

library(tidyverse)
library(sf)
library(geobr)

# =============================================================================
# 1. CRIAR MAPEAMENTO MUNICÍPIO → AMC 
# =============================================================================

# Carregar AMCs do Nordeste via geobr (mesmo método usado nos scripts de controle)
amcs_nordeste <- read_comparable_areas(start_year = 1970, end_year = 2010) |>
  filter(substr(list_code_muni_2010, 1, 1) == "2") |>
  distinct(code_amc, .keep_all = TRUE) |>
  st_make_valid()

# Criar amc_lookup no formato esperado pelo script de outcomes
amc_lookup <- amcs_nordeste |>
  st_drop_geometry() |>
  select(code_amc, list_code_muni_2010) |>
  distinct(code_amc, .keep_all = TRUE)

cat(sprintf("  ✓ Mapeamento criado: %d AMCs com municípios associados\n", 
            nrow(amc_lookup)))

# Definir AMCs do Nordeste (estados 21-29 do IBGE)
ne_amcs <- sort(unique(amc_lookup$code_amc))
ne_munis <- amc_lookup |>
  separate_longer_delim(list_code_muni_2010, delim = ",") |>
  mutate(
    list_code_muni_2010 = as.integer(trimws(list_code_muni_2010)),
    code_amc            = as.integer(code_amc)
  ) |>
  filter(code_amc %in% ne_amcs) |>
  pull(list_code_muni_2010) |>
  unique()

cat(sprintf("  ✓ Municípios NE no mapeamento: %d\n", length(ne_munis)))
cat(sprintf("  ✓ AMCs NE no projeto: %d\n\n", length(ne_amcs)))

# =============================================================================
# 2. CRIAR BASE DE TRATAMENTO: DENSIDADE DE BUFFER
# =============================================================================

# Definir diretório de trabalho 
data.wd_buffer <- data.wd
# A base_buffer.R cria: base_densidade_buffer_unificada.csv
source("02-scripts/01-preparacao/base_buffer.R")

# =============================================================================
# 3. CRIAR CONTROLES CLIMÁTICOS
# =============================================================================

# O script cria: controles_clima_amcs_nordeste.csv e .rds
source("02-scripts/01-preparacao/8_controles_clima.R")

# =============================================================================
# 4. CRIAR CONTROLES DE SOLO
# =============================================================================

# O script cria: controles_solo_amcs_nordeste.csv e .rds
source("02-scripts/01-preparacao/9_controles_solo.R")

# =============================================================================
# 5. CRIAR CONTROLES HIDROLÓGICOS
# =============================================================================

# O script cria: controles_rios_amcs_nordeste.csv e .rds
source("02-scripts/01-preparacao/10_controles_rios.R")

# =============================================================================
# 6. ADICIONAR ABREVIATURAS DE ESTADO
# =============================================================================

# Para este script, precisamos de uma base para modificar
# Vamos usar nossa base de tratamento como base e adicionar state_abbr
# Primeiro, carregamos a base de tratamento
base_tratamento <- read_csv(
  paste0(data.wd, "/01-dados/processados/base_densidade_buffer_unificada.csv"),
  show_col_types = FALSE
)

# Mapeamento IBGE: código de estado → UF
# Códigos corretos: 15 = PA (Pará), 16 = AP (Amapá)
estado_map <- data.frame(
  codigo_estado = c(11, 12, 13, 14, 15, 16, 17, 21, 22, 23, 24, 25, 26, 27, 28, 29,
                    31, 32, 33, 35, 41, 42, 43, 50, 51, 52, 53),
  state_abbr    = c("RO", "AC", "AM", "RR", "PA", "AP", "TO", "MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA",
                    "MG", "ES", "RJ", "SP", "PR", "SC", "RS", "MS", "MT", "GO", "DF"),
  stringsAsFactors = FALSE
)

# Reutilizar amcs_nordeste já carregado na ETAPA 1 
amcs_info <- amcs_nordeste |>
  st_drop_geometry() |>
  select(code_amc, list_code_muni_2010) |>
  distinct(code_amc, .keep_all = TRUE) |>
  mutate(
    # Extrair código de estado (2 primeiros dígitos do código de município)
    codigo_estado = as.integer(substr(list_code_muni_2010, 1, 2))
  ) |>
  left_join(estado_map, by = "codigo_estado") |>
  select(code_amc, state_abbr)

# Mesclar com nossa base de tratamento
base_com_temp <- base_tratamento |>
  left_join(amcs_info, by = "code_amc")

# Verificar se há NA
na_state <- sum(is.na(base_com_temp$state_abbr))
if (na_state > 0) {
  cat(sprintf("  ⚠️  Atenção: %d valores NA em state_abbr\n", na_state))
} else {
  cat("  ✓ Coluna state_abbr adicionada sem valores ausentes\n")
}

# Contar estados
cat("\n  Distribuição de AMCs por estado:\n")
states_count <- base_com_temp |>
  count(state_abbr) |>
  arrange(state_abbr)

for (i in 1:nrow(states_count)) {
  cat(sprintf("    %s: %d AMCs\n", states_count$state_abbr[i], states_count$n[i]))
}

cat("\n")
base_tratamento <- base_com_temp  # Atualizar nossa base de tratamento

# =============================================================================
# 7. EXTRAIR OUTCOMES DE DESENVOLVIMENTO
# =============================================================================

# O script cria outcomes_amc_wide.csv/rds
source("02-scripts/01-preparacao/7_Extrair_Outcomes_Desenvolvimento.R")

# =============================================================================
# 8. INTEGRAR TODAS AS BASES
# =============================================================================

# 8.2 Controles climáticos
cat("  • Carregando controles climáticos...\n")
controles_clima <- read_csv(
  paste0(data.wd, "/01-dados/processados/controles_clima_amcs_nordeste.csv"),
  show_col_types = FALSE
)

# 8.3 Controles de solo
cat("  • Carregando controles de solo...\n")
controles_solo <- read_csv(
  paste0(data.wd, "/01-dados/processados/controles_solo_amcs_nordeste.csv"),
  show_col_types = FALSE
)

# 8.4 Controles hidrológicos
cat("  • Carregando controles hidrológicos...\n")
controles_rios <- read_csv(
  paste0(data.wd, "/01-dados/processados/controles_rios_amcs_nordeste.csv"),
  show_col_types = FALSE
)

# 8.5 Outcomes
cat("  • Carregando outcomes de desenvolvimento...\n")
outcomes <- read_csv(
  paste0(data.wd, "/01-dados/processados/outcomes/outcomes_amc_wide.csv"),
  show_col_types = FALSE
)

# Iniciar a integração com a base de tratamento
cat("  • Iniciando integração...\n")
base_final <- base_tratamento

# Fazer merge com cada componente
base_final <- base_final |>
  left_join(controles_clima, by = "code_amc")
cat(sprintf("    → Após controles climáticos:   %d colunas\n", ncol(base_final)))

base_final <- base_final |>
  left_join(controles_solo, by = "code_amc")
cat(sprintf("    → Após controles de solo:      %d colunas\n", ncol(base_final)))

base_final <- base_final |>
  left_join(controles_rios, by = "code_amc")
cat(sprintf("    → Após controles hidrológicos: %d colunas\n", ncol(base_final)))

base_final <- base_final |>
  left_join(outcomes, by = "code_amc")
cat(sprintf("    → Após outcomes:               %d colunas\n", ncol(base_final)))

# Verificar o resultado
cat(sprintf("\n  Base final: %d linhas × %d colunas\n\n", 
            nrow(base_final), ncol(base_final)))

# =============================================================================
# 9. LIMPAR E REORDENAR COLUNAS
# =============================================================================

cat("ETAPA 9: Limpando e reordenando colunas...\n\n")

# Remover duplicatas de colunas (se houver)
colunas_duplicadas <- colnames(base_final)[duplicated(colnames(base_final))]
if (length(colunas_duplicadas) > 0) {
  cat(sprintf("  ⚠️  Removendo %d colunas duplicadas\n", length(colunas_duplicadas)))
  base_final <- base_final[, !duplicated(colnames(base_final))]
}

# Reordenar colunas: primeiro code_amc e área, depois em grupos temáticos
ordem_preferida <- c(
  "code_amc",
  "state_abbr", 
  "area_amc_km2", # Do base_buffer.R
  # Variáveis de tratamento (densidade de buffer)
  grep("^densidade_buffer_real_|^densidade_buffer_sintetica_", 
       colnames(base_final), value = TRUE),
  # Controles climáticos
  grep("^bio_|^prec_|^tmean_", 
       colnames(base_final), value = TRUE),
  # Controles de solo
  grep("^pct_solo_|^solo_dominante|^pct_dominante|^area_mapeada_km2", 
       colnames(base_final), value = TRUE),
  # Controles hidrológicos (area_amc_km2 excluída aqui — já listada acima)
  grep("^dist_rio_|^comp_total_rios_|^comp_rios_principais_|^pct_comp_principal|^comp_maior_rio_|^densidade_hidro_|^n_rios_|^n_segmentos_|^otto_", 
       colnames(base_final), value = TRUE),
  # Outcomes (vêm do outcomes_amc_wide.csv)
  setdiff(colnames(base_final), 
          c("code_amc", "state_abbr", "area_amc_km2",
            grep("^densidade_buffer_real_|^densidade_buffer_sintetica_", 
                 colnames(base_final), value = TRUE),
            grep("^bio_|^prec_|^tmean_", 
                 colnames(base_final), value = TRUE),
            grep("^pct_solo_|^solo_dominante|^pct_dominante|^area_mapeada_km2", 
                 colnames(base_final), value = TRUE),
            grep("^dist_rio_|^comp_total_rios_|^comp_rios_principais_|^pct_comp_principal|^comp_maior_rio_|^densidade_hidro_|^n_rios_|^n_segmentos_|^otto_", 
                 colnames(base_final), value = TRUE)
          )
  )
)

# Garantir que todas as colunas estão na ordem preferida (unique() previne duplicatas)
colunas_extras <- setdiff(colnames(base_final), ordem_preferida)
ordem_final <- c(unique(ordem_preferida[ordem_preferida %in% colnames(base_final)]),
                 colunas_extras)

base_final <- base_final |>
  select(all_of(ordem_final))

cat(sprintf("  ✓ Colunas reordenadas: %d total\n", ncol(base_final)))

# =============================================================================
# 10. VALIDAÇÕES FINAIS
# =============================================================================

# Verificar se há NA na base final
na_final <- sum(is.na(base_final))
if (na_final == 0) {
  cat("  ✓ Base final sem valores ausentes (NA)\n")
} else {
  cat(sprintf("  ⚠️  Atenção: %d valores NA na base final\n", na_final))
}

# Verificar estatísticas básicas da variável de tratamento (exemplo)
if ("densidade_buffer_real_2003" %in% colnames(base_final)) {
  dens_buffer_2003 <- base_final$densidade_buffer_real_2003
  cat(sprintf("  Densidade de Buffer Real 2003:\n"))
  cat(sprintf("    Média: %.4f, Mediana: %.4f, Min: %.4f, Max: %.4f\n",
              mean(dens_buffer_2003, na.rm = TRUE),
              median(dens_buffer_2003, na.rm = TRUE),
              min(dens_buffer_2003, na.rm = TRUE),
              max(dens_buffer_2003, na.rm = TRUE)))
}



# =============================================================================
# 11. EXPORTAÇÃO
# =============================================================================

# Salvar em CSV
arquivo_csv <- paste0(data.wd, "/01-dados/processados/base_completa_integrada_buffer.csv")
write_csv(base_final, arquivo_csv)
cat(sprintf("  ✓ CSV salvo: %s\n", arquivo_csv))

# Salvar em RDS (mais eficiente para R)
arquivo_rds <- paste0(data.wd, "/01-dados/processados/base_completa_integrada_buffer.rds")
saveRDS(base_final, arquivo_rds)
cat(sprintf("  ✓ RDS salvo: %s\n", arquivo_rds))

