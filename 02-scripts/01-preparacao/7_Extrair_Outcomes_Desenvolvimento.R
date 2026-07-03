# =============================================================================
# Etapa 05
#
# Extrai e harmoniza outcomes de desenvolvimento para os 4 escopos do projeto:
#   1. PIB e renda agregada            (ipeadatar)
#   2. Dinâmica demográfica            (ipeadatar)
#   3. Transformação estrutural / PAM  (ipeadatar + SIDRA tabela 5457)
#   4. IDHM, Gini e pobreza            (ipeadatar – Atlas DH)
# =============================================================================

library(ipeadatar)
library(sidrar)
library(tidyverse)

# ── Diretórios ────────────────────────────────────────────────────────────────
DIR_BRUTOS <- "01-dados/brutos/outcomes"
DIR_PROC   <- "01-dados/processados/outcomes"
dir.create(DIR_BRUTOS, showWarnings = FALSE, recursive = TRUE)
dir.create(DIR_PROC,   showWarnings = FALSE, recursive = TRUE)

# =============================================================================
# 0.  MAPEAMENTO MUNICÍPIO → AMC 
# =============================================================================

amcs_geometria <- readRDS(paste0(data.wd, "/01-dados/processados/amcs_geometria.rds")) # gerado na etapa 04

amc_map <- amcs_geometria |>
  mutate(
    
    list_code_muni_2010 = str_split(list_code_muni_2010, ",\\s*") 
  ) |>
  unnest(list_code_muni_2010) |>
  mutate(
    code_muni = as.integer(list_code_muni_2010),
    code_amc  = as.integer(code_amc)
  ) |>
  select(code_muni, code_amc) |>
  filter(!is.na(code_muni)) 


ne_amcs  <- sort(unique(amc_map$code_amc))
ne_munis <- unique(amc_map$code_muni[amc_map$code_amc %in% ne_amcs])

cat("Municípios NE no mapeamento :", length(ne_munis), "\n")
cat("AMCs NE na base do projeto  :", length(ne_amcs), "\n\n")

# =============================================================================
# FUNÇÃO AUXILIAR – extração de série ipeadatar em nível municipal
# =============================================================================
extrai_ipea_mun <- function(codigo_serie) {
  cat("  Extraindo:", codigo_serie, "...")
  df <- ipeadata(codigo_serie, language = "br")
  out <- df |>
    filter(uname == "Municípios") |>
    transmute(
      serie     = codigo_serie,
      code_muni = as.integer(tcode),
      ano       = as.integer(format(date, "%Y")),
      value
    )
  cat(" OK (", nrow(out), "obs)\n")
  out
}

# =============================================================================
# ESCOPO 1 – PIB E RENDA AGREGADA
# PIB total: R$ mil, preços de mercado (preços de 2010), período 1920–2010
# VAB setorial: R$ mil, preços de 2010
# =============================================================================


series_pib <- c("PIB", "PIBAG", "PIBI", "PIBSE", "PIBG", "IMPPIB")

raw_pib <- map_dfr(series_pib, extrai_ipea_mun) |>
  filter(code_muni %in% ne_munis)

write_csv(raw_pib, file.path(DIR_BRUTOS, "pib_vab_municipal_ne.csv"))
cat("Salvo: pib_vab_municipal_ne.csv\n\n")

# =============================================================================
# ESCOPO 2 – DINÂMICA DEMOGRÁFICA
# Pop. urbana e rural dos Censos decenais (Ipeadata)
# =============================================================================


raw_pop <- map_dfr(c("POPUR", "POPRU"), extrai_ipea_mun) |>
  filter(code_muni %in% ne_munis)

write_csv(raw_pop, file.path(DIR_BRUTOS, "populacao_municipal_ne.csv"))
cat("Salvo: populacao_municipal_ne.csv\n\n")

# =============================================================================
# ESCOPO 3 – PAM: PESQUISA AGRÍCOLA MUNICIPAL  (SIDRA tabela 5457)
# Variáveis extraídas:
# 8331 – Área plantada ou destinada à colheita (ha)
# 214 – Quantidade produzida (t)
# 215 – Valor da produção (R$ mil)
# Categoria c782 = 0 → Total de lavouras
# Período: 1974–2023 (todos os anos disponíveis)
# =============================================================================


estados_ne <- c(21, 22, 23, 24, 25, 26, 27, 28, 29)

pam_raw_list <- lapply(estados_ne, function(uf) {
  cat("  Estado", uf, "... ")
  tryCatch({
    df <- get_sidra(
      x          = 5457,
      variable   = c(8331, 214, 215),
      period     = "all",
      geo        = "City",
      geo.filter = list("State" = uf),
      classific  = "c782",
      category   = list(c782 = 0),
      header     = FALSE,
      format     = 3
    )
    cat("OK (", nrow(df), "obs)\n")
    df
  }, error = function(e) {
    cat("ERRO:", conditionMessage(e), "\n")
    NULL
  })
})

raw_pam <- bind_rows(pam_raw_list)

# Formato de retorno do sidrar (format=3, header=FALSE):
#   D1C = código do município (7 dígitos)
#   D2N = ano
#   D3N = nome da variável
#   V   = valor numérico
#   MN  = unidade de medida

pam_var_map <- c(
  "Área plantada ou destinada à colheita" = "area_plantada_ha",
  "Quantidade produzida"                  = "qtd_produzida_t",
  "Valor da produção"                     = "valor_producao_mil_reais"
)

raw_pam_tidy <- raw_pam |>
  transmute(
    code_muni = as.integer(D1C),
    ano       = as.integer(D2N),
    serie     = recode(D3N, !!!pam_var_map),
    value     = suppressWarnings(as.numeric(V))
  ) |>
  filter(!is.na(value), code_muni %in% ne_munis)

write_csv(raw_pam,      file.path(DIR_BRUTOS, "pam_raw_ne.csv"))
write_csv(raw_pam_tidy, file.path(DIR_BRUTOS, "pam_tidy_ne.csv"))
cat("Salvo: pam_raw_ne.csv + pam_tidy_ne.csv\n\n")

# =============================================================================
# ESCOPO 4 – IDHM, GINI E POBREZA  (Atlas do Desenvolvimento Humano – Censo)
# Período: 1991, 2000, 2010 (anos censitários)
# =============================================================================


series_social <- c(
  "ADH_IDHM",   # IDHM total
  "ADH_IDHM_E", # IDHM Educação
  "ADH_IDHM_L", # IDHM Longevidade
  "ADH_IDHM_R", # IDHM Renda
  "ADH_GINI",   # Índice de Gini
  "ADH_PMPOB",  # % pobres (linha ~R$255/mês, preços ago 2010)
  "ADH_PIND",   # % extremamente pobres (~R$128/mês)
  "ADH_RDPC"    # Renda domiciliar per capita média (R$, preços ago 2010)
)

raw_social <- map_dfr(series_social, extrai_ipea_mun) |>
  filter(code_muni %in% ne_munis)

write_csv(raw_social, file.path(DIR_BRUTOS, "social_idhm_gini_pobreza_municipal_ne.csv"))
cat("Salvo: social_idhm_gini_pobreza_municipal_ne.csv\n\n")

# =============================================================================
# HARMONIZAÇÃO PARA AMC
# =============================================================================

# Pesos populacionais para médias ponderadas (pop total = POPUR + POPRU)
pop_pesos <- raw_pop |>
  pivot_wider(names_from = serie, values_from = value) |>
  mutate(pop_total = coalesce(POPUR, 0) + coalesce(POPRU, 0)) |>
  select(code_muni, ano, pop_total)

# Função genérica de harmonização
harmonizar <- function(df, metodo = c("soma", "media_pond")) {
  metodo <- match.arg(metodo)

  df_j <- df |>
    inner_join(amc_map, by = "code_muni") |>
    filter(code_amc %in% ne_amcs)

  if (metodo == "soma") {
    df_j |>
      group_by(serie, code_amc, ano) |>
      summarise(value = sum(value, na.rm = TRUE), .groups = "drop")
  } else {
    df_j |>
      left_join(pop_pesos, by = c("code_muni", "ano")) |>
      group_by(serie, code_amc, ano) |>
      summarise(
        value = weighted.mean(value, w = replace_na(pop_total, 1), na.rm = TRUE),
        .groups = "drop"
      )
  }
}

# Escopo 1: somar municípios do AMC
pib_amc    <- harmonizar(raw_pib,    metodo = "soma")
cat("PIB/VAB por AMC:", nrow(pib_amc), "obs\n")

# Escopo 2: somar municípios do AMC
pop_amc    <- harmonizar(raw_pop,    metodo = "soma")
cat("Pop por AMC    :", nrow(pop_amc), "obs\n")

# Escopo 3: somar municípios do AMC
pam_amc    <- harmonizar(raw_pam_tidy, metodo = "soma")
cat("PAM por AMC    :", nrow(pam_amc), "obs\n")

# Escopo 4: média ponderada por população
social_amc <- harmonizar(raw_social,  metodo = "media_pond")
cat("Social por AMC :", nrow(social_amc), "obs\n")

# =============================================================================
# VARIÁVEIS DERIVADAS
# =============================================================================

# Pop total, taxa de urbanização e densidade demográfica
pop_derivado <- pop_amc |>
  pivot_wider(names_from = serie, values_from = value) |>
  rename(pop_urbana = POPUR, pop_rural = POPRU) |>
  mutate(
    pop_total      = pop_urbana + pop_rural,
    tx_urbanizacao = pop_urbana / pop_total
  )

# PIB per capita (anos com dados de pop E de PIB: 1920, 1940, 1950, 1960, 1970, 1980, 1991, 2000, 2010)
pib_percapita <- pib_amc |>
  filter(serie == "PIB") |>
  select(code_amc, ano, pib_total = value) |>
  inner_join(pop_derivado |> select(code_amc, ano, pop_total), by = c("code_amc", "ano")) |>
  mutate(pib_percapita = pib_total / pop_total * 1000)  # R$ mil → R$/pessoa

# =============================================================================
# SALVAR DADOS PROCESSADOS (formato long por escopo)
# =============================================================================

write_csv(pib_amc,       file.path(DIR_PROC, "escopo1_pib_vab_amc.csv"))
write_csv(pop_derivado,  file.path(DIR_PROC, "escopo2_populacao_amc.csv"))
write_csv(pib_percapita, file.path(DIR_PROC, "escopo1_pib_percapita_amc.csv"))
write_csv(pam_amc,       file.path(DIR_PROC, "escopo3_pam_amc.csv"))
write_csv(social_amc,    file.path(DIR_PROC, "escopo4_social_amc.csv"))

# =============================================================================
# BASE CONSOLIDADA EM FORMATO LARGO (wide) – pronta para juntar com base IV
# =============================================================================


para_wide <- function(df, col_serie = "serie") {
  df |>
    mutate(col_name = paste0(tolower(.data[[col_serie]]), "_", ano)) |>
    select(code_amc, col_name, value) |>
    pivot_wider(names_from = col_name, values_from = value, values_fn = mean)
}

pib_wide    <- para_wide(pib_amc)
pop_long    <- pop_derivado |>
  pivot_longer(c(pop_urbana, pop_rural, pop_total, tx_urbanizacao),
               names_to = "serie", values_to = "value")
pop_wide    <- para_wide(pop_long)
pibpc_long  <- pib_percapita |> mutate(serie = "pib_percapita") |>
  rename(value = pib_percapita)
pibpc_wide  <- para_wide(pibpc_long)
pam_wide    <- para_wide(pam_amc)
social_wide <- para_wide(social_amc)

base_outcomes <- tibble(code_amc = ne_amcs) |>
  left_join(pib_wide,    by = "code_amc") |>
  left_join(pop_wide,    by = "code_amc") |>
  left_join(pibpc_wide,  by = "code_amc") |>
  left_join(pam_wide,    by = "code_amc") |>
  left_join(social_wide, by = "code_amc")

cat("Base final: ", nrow(base_outcomes), " AMCs × ", ncol(base_outcomes),
    " colunas\n", sep = "")

write_csv(base_outcomes, file.path(DIR_PROC, "outcomes_amc_wide.csv"))
saveRDS(base_outcomes,   file.path(DIR_PROC, "outcomes_amc_wide.rds"))
