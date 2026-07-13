# ==============================================================================
# Etapa 18
# SECOND-STAGE IV (2SLS) – PLACEBO IN-SPACE (TESTE DE FALSIFICAÇÃO)
# Variável endógena: densidade do buffer REAL (multiraio wide)
# Instrumento: densidade do buffer PLACEBO CONTINENTAL (multiraio long)
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

# -------------------- PARÂMETROS DE RAIO --------------------
raios_km <- c(5, 10, 20, 50)   # km
raios_m  <- raios_km * 1000

# -------------------- 1. CARREGAR BASES --------------------

base_main <- read_csv("01-dados/processados/base_completa_integrada.csv", show_col_types = FALSE)

base_densidade_real <- read_csv("01-dados/processados/base_densidade_buffer_multiraio.csv", show_col_types = FALSE) %>% 
  select(code_amc, starts_with("densidade_buffer_real_"))

# ATENÇÃO: Agora lê o painel longo gerado na Etapa 17 atualizada
base_densidade_placebo <- read_csv("01-dados/processados/painel_densidade_placebo_long.csv", show_col_types = FALSE)

painel_pontas <- read_csv("01-dados/processados/painel_amcs_pontas_ano_a_ano.csv", show_col_types = FALSE)
outcomes_interp <- readRDS("01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.rds")

ne_states <- c("MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA")

# -------------------- 2. PREPARAR BASE (CORRIGIDA) --------------------
# O join do placebo foi removido daqui para evitar Produto Cartesiano
base <- base_main %>%
  filter(state_abbr %in% ne_states) %>%
  select(-starts_with("densidade_")) %>% 
  left_join(base_densidade_real, by = "code_amc") %>%
  left_join(outcomes_interp, by = "code_amc")

# -------------------- 3. CONTROLES AMBIENTAIS --------------------
ctrl_clima  <- readRDS("01-dados/processados/controles_clima_amcs_nordeste.rds")
ctrl_rios   <- readRDS("01-dados/processados/controles_rios_amcs_nordeste.rds")
ctrl_solo   <- readRDS("01-dados/processados/controles_solo_amcs_nordeste.rds")

base <- base %>%
  left_join(ctrl_clima  %>% select(code_amc, bio_1, bio_12, bio_15), by = "code_amc") %>%
  left_join(ctrl_rios   %>% select(code_amc, dist_rio_km, densidade_hidro_km_km2), by = "code_amc") %>%
  left_join(ctrl_solo   %>% select(code_amc, pct_solo_latossolos, pct_solo_neossolos), by = "code_amc")

cols <- colnames(base)

# -------------------- 4. MAPEAMENTO DE OUTCOMES --------------------
extract_years_from_prefix <- function(prefix) {
  pattern <- paste0("^", prefix, "_([0-9]+)$")
  years_found <- sub(pattern, "\\1", grep(pattern, cols, value = TRUE))
  if (length(years_found) == 0) return(NULL)
  sort(as.integer(years_found))
}

prefixos <- c("pib", "pibag", "pibi", "pibse", "tx_urbanizacao", "pop_urbana", 
              "adh_idhm", "adh_idhm_e", "adh_idhm_l", "adh_idhm_r")

outcomes_map <- tibble(
  prefixo = prefixos,
  anos_disponíveis = map(prefixos, extract_years_from_prefix),
  escopo = c("PIB_Total", "PIB_Agropecuário", "PIB_Indústria", "PIB_Serviços",
             "Urbanização", "Urbanização",
             "IDH_Geral", "IDH_Educação", "IDH_Longevidade", "IDH_Renda"),
  needs_log = c(TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE)
)

# -------------------- 5. ANOS DE TRATAMENTO DISPONÍVEIS --------------------
# A extração por Regex foi substituída pela leitura direta da coluna 'ano'
if ("ano" %in% names(base_densidade_placebo)) {
  anos_trat <- sort(unique(na.omit(base_densidade_placebo$ano)))
} else {
  stop("A base placebo não contém a coluna 'ano'. Verifique os dados.")
}

cat(sprintf("\n   ✓ %d anos de tratamento identificados no placebo: %d–%d\n\n",
            length(anos_trat), min(anos_trat), max(anos_trat)))

# -------------------- 6. CONTROLES FIXOS --------------------
fixed_controls <- paste("bio_1", "bio_12", "bio_15", "dist_rio_km", 
                        "densidade_hidro_km_km2", "pct_solo_latossolos", "pct_solo_neossolos", sep = " + ")

# -------------------- 7. FUNÇÃO 2SLS (SUPER-ROBUSTA) --------------------
rodar_2sls <- function(df, endo_var, inst_var, outcome_col, outcome_nome, outcome_escopo, needs_log, ano_trat) {
  if (!(outcome_col %in% names(df))) return(NULL)
  
  vals <- df[[outcome_col]]
  n_valid <- sum(!is.na(vals) & vals > 0, na.rm = TRUE)
  if (n_valid < 15) return(NULL)
  
  formula_str <- ifelse(needs_log,
                        sprintf("log(%s) ~ %s | state_abbr | %s ~ %s", outcome_col, fixed_controls, endo_var, inst_var),
                        sprintf("%s ~ %s | state_abbr | %s ~ %s", outcome_col, fixed_controls, endo_var, inst_var))
  
  mod <- tryCatch({ feols(as.formula(formula_str), data = df, se = "hetero", warn = FALSE) }, error = function(e) return(NULL))
  if (is.null(mod)) return(NULL)
  
  ct <- tryCatch({ as.data.frame(summary(mod)$coeftable) }, error = function(e) return(NULL))
  if (is.null(ct) || nrow(ct) == 0) return(NULL)
  
  nome_coef <- grep(endo_var, rownames(ct), value = TRUE)
  if (length(nome_coef) == 0) return(NULL) 
  
  nome_coef <- nome_coef[1] 
  coef <- ct[nome_coef, 1]; se <- ct[nome_coef, 2]; t_stat <- ct[nome_coef, 3]; p_val <- ct[nome_coef, 4]
  
  f_stat <- NA_real_
  try({
    fs_obj <- fitstat(mod, "ivf")
    if (!is.null(fs_obj) && length(fs_obj) > 0) f_stat <- as.numeric(fs_obj[[1]]$stat)
  }, silent = TRUE)
  
  r2_val <- NA_real_
  try({
    r2_obj <- fitstat(mod, "r2")
    if (!is.null(r2_obj) && length(r2_obj) > 0) r2_val <- as.numeric(r2_obj[[1]])
  }, silent = TRUE)
  if (is.na(r2_val) && !is.null(mod$r.squared)) r2_val <- mod$r.squared
  
  tibble(
    ano_tratamento = ano_trat, ano_outcome = as.integer(str_extract(outcome_col, "[0-9]+$")),
    escopo = outcome_escopo, outcome_var = outcome_nome, outcome_coluna = outcome_col,
    variavel_endogena = endo_var, variavel_instrumento = inst_var,
    coeficiente = coef, erro_padrao = se, t_estatistica = t_stat, p_valor = p_val,
    F_stat_1estagio = f_stat, R2_2estagio = r2_val, n_observacoes = mod$nobs,
    significancia = case_when(is.na(p_val) ~ "", p_val < 0.01 ~ "***", p_val < 0.05 ~ "**", p_val < 0.10 ~ "*", TRUE ~ "")
  )
}

# -------------------- 8. LOOP PRINCIPAL --------------------

resultados_lista <- list()
contador_total <- 0
contador_anos  <- 0

for (ano_trat in anos_trat) {
  contador_anos <- contador_anos + 1
  
  # NOVIDADE: Filtra o placebo apenas para o ano da iteração e acopla na base principal
  placebo_slice <- base_densidade_placebo %>%
    filter(ano == ano_trat) %>%
    select(code_amc, starts_with("dens_placebo_"))
  
  base_ano <- base %>%
    left_join(placebo_slice, by = "code_amc")
  
  codes_pontas <- painel_pontas %>% filter(ano_corte == ano_trat) %>% pull(code_amc) %>% unique()
  
  for (r in raios_km) {
    endo_var <- paste0("densidade_buffer_real_", r, "km_", ano_trat)
    inst_var <- paste0("dens_placebo_", r, "km") # Chama o nome padronizado do painel longo
    
    if (!all(c(endo_var, inst_var) %in% colnames(base_ano))) next
    if (sum(base_ano[[inst_var]], na.rm = TRUE) == 0) next
    
    # Agora filtra em cima do dataframe 'base_ano' que já contém as variáveis corretas
    df_work <- base_ano %>% filter(!(code_amc %in% codes_pontas), is.finite(.data[[endo_var]]), is.finite(.data[[inst_var]]), !is.na(state_abbr))
    if (nrow(df_work) < 20) next
    
    for (i in seq_len(nrow(outcomes_map))) {
      row <- outcomes_map[i, ]
      anos_outcome <- row$anos_disponíveis[[1]]
      if (is.null(anos_outcome) || length(anos_outcome) == 0) next
      
      for (ano_out in anos_outcome) {
        outcome_col <- paste0(row$prefixo, "_", ano_out)
        
        res <- rodar_2sls(df = df_work, endo_var = endo_var, inst_var = inst_var, 
                          outcome_col = outcome_col, outcome_nome = paste0(row$prefixo, " (", ano_out, ")"), 
                          outcome_escopo = row$escopo, needs_log = row$needs_log, ano_trat = ano_trat)
        
        if (!is.null(res)) {
          contador_total <- contador_total + 1
          resultados_lista[[contador_total]] <- res
        }
      }
    }
  }
  
  if (contador_anos %% 5 == 0) {
    cat(sprintf("   → Ano %d (%d/%d) | regressões acumuladas: %d\n", ano_trat, contador_anos, length(anos_trat), contador_total))
  }
}

# -------------------- 9. COMPILAR E SALVAR --------------------
if (length(resultados_lista) == 0) {
  stop("❌ Nenhuma regressão bem-sucedida. Verifique os dados.")
}

resultados_df <- bind_rows(resultados_lista) %>% arrange(escopo, ano_tratamento, ano_outcome)

output_dir <- "03-resultados/csv"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

output_file <- paste0(output_dir, "/second_stage_placebo_multiraio.csv")
write_csv(resultados_df, output_file)