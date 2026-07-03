# ==============================================================================
# FIRST‑STAGE IV (2SLS) – MÚLTIPLOS RAIOS DE BUFFER
# Para cada raio (5,10,20,50 km) e cada ano de tratamento:
#   Regressão: densidade_buffer_real_<raio>_<ano> ~ densidade_buffer_sintetica_<raio>_<ano> | state_abbr + controles
# Saída: CSV com coeficiente, erro padrão, F‑stat do primeiro estágio, etc.
# ==============================================================================

library(dplyr)
library(tidyverse)
library(fixest)
library(stringr)
library(readr)

if (!exists("data.wd")) {
  data.wd <- normalizePath(file.path(getwd(), "..", ".."))
}
setwd(data.wd)

cat("========================================================================\n")
cat("FIRST‑STAGE IV: MÚLTIPLOS RAIOS DE BUFFER\n")
cat("========================================================================\n\n")

# -------------------- PARÂMETROS DE RAIO --------------------
# Devem corresponder aos usados no script de geração de base
raios_km <- c(5, 10, 20, 50)   # km
raios_m  <- raios_km * 1000

# -------------------- 1. CARREGAR BASES --------------------
cat("1. Carregando bases de dados...\n")

# Base principal (controles, etc.)
base_main <- read_csv("01-dados/processados/base_completa_integrada.csv", show_col_types = FALSE)

# Base de densidade multiraio (gerada por base_buffer_multiraio.R)
base_densidade <- read_csv("01-dados/processados/base_densidade_buffer_multiraio.csv", show_col_types = FALSE)

# Painel de pontas (opcional)
painel_pontas <- read_csv("01-dados/processados/painel_amcs_pontas_ano_a_ano.csv", show_col_types = FALSE)

# Outcomes interpolados (se precisar de anos antigos não censitados)
outcomes_interp <- readRDS("01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.rds")

# Estados do Nordeste
ne_states <- c("MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA")

cat("   ✓ Base principal carregada\n")

# -------------------- 2. PREPARAR BASE --------------------
base <- base_main %>%
  filter(state_abbr %in% ne_states) %>%
  # Remove colunas de densidade do buffer padrão (para evitar conflito com nomes semelhantes)
  select(-starts_with("densidade_real_"), -starts_with("densidade_sintetica")) %>%
  left_join(base_densidade, by = "code_amc") %>%
  left_join(painel_pontas %>% select(code_amc, ano_corte) %>% distinct(), by = "code_amc") %>%
  left_join(outcomes_interp, by = "code_amc")

cat("   ✓ Densidade multiraio adicionada\n")

# -------------------- 3. CONTROLES AMBIENTAIS --------------------
cat("2. Carregando controles ambientais...\n")
ctrl_clima  <- readRDS("01-dados/processados/controles_clima_amcs_nordeste.rds")
ctrl_rios   <- readRDS("01-dados/processados/controles_rios_amcs_nordeste.rds")
ctrl_solo   <- readRDS("01-dados/processados/controles_solo_amcs_nordeste.rds")

base <- base %>%
  left_join(ctrl_clima  %>% select(code_amc, bio_1, bio_12, bio_15), by = "code_amc") %>%
  left_join(ctrl_rios   %>% select(code_amc, dist_rio_km, densidade_hidro_km_km2), by = "code_amc") %>%
  left_join(ctrl_solo   %>% select(code_amc, pct_solo_latossolos, pct_solo_neossolos), by = "code_amc")

cat("   ✓ Controles ambientais adicionados\n")

# -------------------- 4. MAPEAMENTO DE OUTCOMES (não usado no first stage, mas mantemos para consistência) --------------------
cat("3. Mapeando outcomes disponíveis por ano (informativo)...\n")
cols <- colnames(base)

extract_years_from_prefix <- function(prefix) {
  pattern <- paste0("^", prefix, "_([0-9]+)$")
  years_found <- sub(pattern, "\\1", grep(pattern, cols, value = TRUE))
  if (length(years_found) == 0) return(NULL)
  sort(as.integer(years_found))
}

prefixos <- c("pib", "pibag", "pibi", "pibse",
              "tx_urbanizacao", "pop_urbana",
              "adh_idhm", "adh_idhm_e", "adh_idhm_l", "adh_idhm_r")

outcomes_map <- tibble(
  prefixo = prefixos,
  anos_disponíveis = map(prefixos, extract_years_from_prefix),
  escopo = c(
    "PIB_Total", "PIB_Agropecuário", "PIB_Indústria", "PIB_Serviços",
    "Urbanização", "Urbanização",
    "IDH_Geral", "IDH_Educação", "IDH_Longevidade", "IDH_Renda"
  ),
  needs_log = c(
    TRUE, TRUE, TRUE, TRUE,
    FALSE, FALSE,
    FALSE, FALSE, FALSE, FALSE
  )
)

cat("   Outcomes mapeados:\n")
for (i in seq_len(nrow(outcomes_map))) {
  row <- outcomes_map[i, ]
  n_years <- length(row$anos_disponíveis[[1]])
  if (n_years > 0) {
    cat(sprintf("   • %s (%s): %d anos [%d-%d]\n",
                row$prefixo, row$escopo,
                n_years,
                min(row$anos_disponíveis[[1]]),
                max(row$anos_disponíveis[[1]])))
  }
}
cat("\n")

# -------------------- 5. ANOS DE TRATAMENTO DISPONÍVEIS --------------------
cat("4. Identificando anos de tratamento disponíveis...\n")
# Detectar todas as colunas de densidade real (qualquer raio)
prefix_real  <- "densidade_buffer_real_"
treatment_cols_real <- grep(paste0("^", prefix_real, "[0-9]+(km_)?[0-9]+$"), cols, value = TRUE)
# Extrair anos únicos (assumindo padrão *_<raio>km_<ano> ou *_<raio>_<ano>? nosso padrão: densidade_buffer_real_5km_1900)
anos_trat <- unique(
  as.integer(
    sub(".*_", "", sub(".*_", "", treatment_cols_real))  # hack: we'll do regex properly
  )
)
# Better: use regex to capture year after last _
get_year <- function(x) as.integer(sub(".*_", "", x))
anos_trat <- sort(unique(get_year(treatment_cols_real)))

cat(sprintf("   ✓ %d anos de tratamento: %d–%d\n\n",
            length(anos_trat), min(anos_trat), max(anos_trat)))

# -------------------- 6. CONTROLES FIXOS --------------------
fixed_controls <- paste(
  "bio_1", "bio_12", "bio_15",
  "dist_rio_km", "densidade_hidro_km_km2",
  "pct_solo_latossolos", "pct_solo_neossolos",
  sep = " + "
)

# -------------------- 7. FUNÇÃO FIRST STAGE --------------------
cat("5. Definindo função de primeiro estágio...\n")
rodar_first_stage <- function(df, endo_var, inst_var, ano_trat) {
  if (!(endo_var %in% names(df)) || !(inst_var %in% names(df))) return(NULL)
  
  # Verificar variação do instrumento
  if (sum(!is.na(df[[inst_var]]) & df[[inst_var]] > 0, na.rm = TRUE) < 5) return(NULL)
  
  formula_str <- sprintf(
    "%s ~ %s | state_abbr | %s",
    endo_var, fixed_controls, inst_var
  )
  
  tryCatch({
    mod <- feols(as.formula(formula_str), data = df, se = "hetero")
    ct  <- summary(mod)$coeftable
    # Nome do instrumento no fixest (geralmente aparece como é)
    nome_inst <- inst_var
    if (!(nome_inst %in% rownames(ct))) return(NULL)
    
    coef  <- ct[nome_inst, 1]
    se    <- ct[nome_inst, 2]
    t_stat<- ct[nome_inst, 3]
    p_val <- ct[nome_inst, 4]
    
    # F‑stat do primeiro estágio (ivf)
    f_stat <- tryCatch({ fitstat(mod, "ivf")[[1]]$stat }, error = function(e) NA_real_)
    r2     <- tryCatch({ summary(mod)$r.squared }, error = function(e) NA_real_)
    
    tibble(
      ano_tratamento = ano_trat,
      variavel_endogena = endo_var,
      variavel_instrumento = inst_var,
      coeficiente = coef,
      erro_padrao = se,
      t_estatistica = t_stat,
      p_valor = p_val,
      F_stat_1estagio = f_stat,
      R2_1estagio = r2,
      n_observacoes = nrow(df)
    )
  }, error = function(e) {
    return(NULL)
  })
}

# -------------------- 8. LOOP PRINCIPAL --------------------
cat("6. Rodando regressões de primeiro estágio...\n")
cat("   (Este processo pode levar alguns minutos)\n\n")
resultados_lista <- list()
contador_total <- 0

for (ano_trat in anos_trat) {
  for (r in raios_km) {
    endo_var <- paste0("densidade_buffer_real_", r, "km_", ano_trat)
    inst_var <- paste0("densidade_buffer_sintetica_", r, "km_", ano_trat)
    
    if (!all(c(endo_var, inst_var) %in% cols)) next
    
    # Excluir pontas deste ano de tratamento (opcional)
    codes_pontas <- painel_pontas %>%
      filter(ano_corte == ano_trat) %>%
      pull(code_amc) %>%
      unique()
    
    df_work <- base %>%
      filter(!(code_amc %in% codes_pontas)) %>%
      filter(
        is.finite(.data[[endo_var]]),
        is.finite(.data[[inst_var]]),
        !is.na(state_abbr)
      )
    
    if (nrow(df_work) < 20) next
    
    res <- rodar_first_stage(df_work, endo_var, inst_var, ano_trat)
    
    if (!is.null(res)) {
      contador_total <- contador_total + 1
      resultados_lista[[contador_total]] <- res
    }
  }
  
  if (which(anos_trat == ano_trat) %% 10 == 0) {
    cat(sprintf("   → Ano %d processado\n", ano_trat))
  }
}

cat("\n")

# -------------------- 9. COMPILAR E SALVAR --------------------
cat("7. Compilando resultados...\n\n")
if (length(resultados_lista) == 0) {
  stop("❌ Nenhuma regressão bem-sucedida. Verifique os dados.")
}
resultados_df <- bind_rows(resultados_lista) %>%
  arrange(variavel_endogena, ano_tratamento)

output_file <- "03-resultados/csv/first_stage_multiraio.csv"
write_csv(resultados_df, output_file)

# -------------------- 10. RESUMO --------------------
cat("========================================================================\n")
cat("RESUMO DA EXECUÇÃO\n")
cat("========================================================================\n\n")
cat(sprintf("✅ Total de regressões rodadas: %d\n", nrow(resultados_df)))
cat(sprintf("✅ Arquivo gerado: %s\n\n", output_file))

# Resumo por raio
resumo_raio <- resultados_df %>%
  group_by(variavel_endogena) %>%
  summarise(
    n_regressoes = n(),
    n_sig_001 = sum(p_valor < 0.01, na.rm = TRUE),
    n_sig_005 = sum(p_valor < 0.05, na.rm = TRUE),
    n_sig_010 = sum(p_valor < 0.10, na.rm = TRUE),
    coef_medio = mean(coeficiente, na.rm = TRUE),
    f_medio = mean(F_stat_1estagio, na.rm = TRUE),
    .groups = "drop"
  )

cat("Resumo por raio (variável endógena):\n")
cat("─────────────────────────────────────────────────────────────────────\n")
print(resumo_raio)

cat("\nResultados Significativos (p < 0.05):\n")
cat("─────────────────────────────────────────────────────────────────────\n")
sig_results <- resultados_df %>%
  filter(p_valor < 0.05) %>%
  select(variavel_endogena, variavel_instrumento, ano_tratamento, coeficiente, p_valor, F_stat_1estagio)

if (nrow(sig_results) > 0) {
  print(sig_results, n = 20)
} else {
  cat("(Nenhum resultado significativo encontrado)\n")
}

cat("\n========================================================================\n")
cat("✅ PROCESSO CONCLUÍDO COM SUCESSO!\n")
cat("========================================================================\n")