# ==============================================================================
# FIRST & SECOND-STAGE IV (2SLS): TESTE DE INCLUSÃO DE CONTROLES (STEPWISE)
# Instrumento: densidade_buffer_sintetica_1950 → densidade_buffer_real_1950
# Tratamento EXCLUSIVO: 1950
# Outcomes: Multidimensional (Agregados, Setoriais e Sociais)
# ==============================================================================

library(tidyverse)
library(fixest)
library(stringr)

if (!exists("data.wd")) {
  data.wd <- normalizePath(file.path(getwd(), "..", ".."))
}
setwd(data.wd)

# ------------------------------------------------------------------------------
# 1. CARREGAMENTO DA BASE UNIFICADA (COM DADOS RECENTES E CONTROLES)
# ------------------------------------------------------------------------------
arquivo_principal <- "01-dados/processados/base_completa_integrada_buffer_com_pib_recente.csv"
base <- read_csv(arquivo_principal, show_col_types = FALSE)

ne_states <- c("MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA")
base <- base |> filter(state_abbr %in% ne_states)

painel_pontas <- read_csv(
  "01-dados/processados/painel_amcs_pontas_ano_a_ano.csv",
  show_col_types = FALSE
)
pontas_por_ano <- painel_pontas |> select(code_amc, ano_corte) |> distinct()

cat(sprintf("   ✓ Base Carregada: %d AMCs no Nordeste\n\n", nrow(base)))

# ------------------------------------------------------------------------------
# 2. DEFINIÇÃO DA ESTRUTURA STEPWISE DE CONTROLES E OUTCOMES
# ------------------------------------------------------------------------------
# Blocos cumulativos de covariáveis
blocos_controles <- list(
  "1_Baseline"    = "1", 
  "2_Hidrografia" = "dist_rio_km + densidade_hidro_km_km2",
  "3_Clima"       = "dist_rio_km + densidade_hidro_km_km2 + bio_1 + bio_12 + bio_15",
  "4_Full_Soil"   = "dist_rio_km + densidade_hidro_km_km2 + bio_1 + bio_12 + bio_15 + pct_solo_latossolos + pct_solo_neossolos"
)

ano_tratamento <- 1950

# LÓGICA CRÍTICA: Bateria expandida de Outcomes (com e sem log, conforme a natureza da variável)
outcomes_teste <- c(
  "log(pib_2021)", 
  "log(pop_total_2022)",
  "log(pibag_2010)",      # Setor Agropecuário
  "log(pibi_2010)",       # Setor Industrial
  "log(pibse_2010)",      # Setor de Serviços
  "tx_urbanizacao_2010",  # Taxa em nível (não vai log)
  "adh_idhm_2010"         # Índice em nível (não vai log)
)

# ------------------------------------------------------------------------------
# 3. PREPARAÇÃO DA BASE (REMOÇÃO DE PONTAS DE 1950)
# ------------------------------------------------------------------------------
endo_var <- paste0("densidade_buffer_real_", ano_tratamento)
inst_var <- paste0("densidade_buffer_sintetica_", ano_tratamento)

codes_pontas <- pontas_por_ano |>
  filter(ano_corte == ano_tratamento) |>
  pull(code_amc) |>
  unique()

df_work <- base |>
  filter(!(code_amc %in% codes_pontas)) |>
  filter(
    is.finite(.data[[endo_var]]),
    is.finite(.data[[inst_var]]),
    !is.na(state_abbr)
  )

# ------------------------------------------------------------------------------
# 4. FUNÇÃO DE ESTIMAÇÃO COMBINADA (1º E 2º ESTÁGIO)
# ------------------------------------------------------------------------------
rodar_stepwise <- function(df, endo, inst, outcome, nome_modelo, controles_str) {
  
  # Limpa o "log()" para verificar se a coluna base existe
  outcome_col <- gsub("log\\(|\\)", "", outcome)
  if (!(outcome_col %in% names(df))) return(NULL)
  
  vals <- df[[outcome_col]]
  if (sum(!is.na(vals) & vals > 0, na.rm = TRUE) < 15) return(NULL)
  
  # === PRIMEIRO ESTÁGIO (OLS) ===
  form_1st <- sprintf("%s ~ %s + %s | state_abbr", endo, inst, controles_str)
  
  mod_1st <- tryCatch(feols(as.formula(form_1st), data = df, se = "hetero"), error = function(e) NULL)
  
  if (is.null(mod_1st)) return(NULL)
  
  t_inst <- tryCatch(summary(mod_1st)$coeftable[inst, 3], error = function(e) NA)
  f_stat_1st <- if(!is.na(t_inst)) t_inst^2 else NA
  coef_1st   <- tryCatch(summary(mod_1st)$coeftable[inst, 1], error = function(e) NA)
  
  # === SEGUNDO ESTÁGIO (IV) ===
  form_2nd <- sprintf("%s ~ %s | state_abbr | %s ~ %s", outcome, controles_str, endo, inst)
  
  mod_2nd <- tryCatch(feols(as.formula(form_2nd), data = df, se = "hetero"), error = function(e) NULL)
  
  if (is.null(mod_2nd)) return(NULL)
  
  ct_2nd <- summary(mod_2nd)$coeftable
  nome_coef_endo <- paste0("fit_", endo)
  if (!(nome_coef_endo %in% rownames(ct_2nd))) {
    if (endo %in% rownames(ct_2nd)) nome_coef_endo <- endo else return(NULL)
  }
  
  tibble(
    outcome_var          = outcome,
    modelo_especificacao = nome_modelo,
    controles_adicionados= controles_str,
    coef_1st_estagio     = coef_1st,
    F_stat_1st_estagio   = f_stat_1st,
    coef_2nd_estagio     = ct_2nd[nome_coef_endo, 1],
    se_2nd_estagio       = ct_2nd[nome_coef_endo, 2],
    p_val_2nd_estagio    = ct_2nd[nome_coef_endo, 4],
    n_obs                = nrow(df)
  )
}

# ------------------------------------------------------------------------------
# 5. LOOP DE EXECUÇÃO STEPWISE
# ------------------------------------------------------------------------------
cat(sprintf("Iniciando Teste Stepwise Multidimensional (Tratamento: %d)...\n", ano_tratamento))
resultados_lista <- list()

for (oc in outcomes_teste) {
  cat(sprintf("\nProcessando Outcome: %s\n", oc))
  
  for (nome_mod in names(blocos_controles)) {
    controles <- blocos_controles[[nome_mod]]
    
    res <- rodar_stepwise(
      df = df_work, 
      endo = endo_var, 
      inst = inst_var, 
      outcome = oc, 
      nome_modelo = nome_mod, 
      controles_str = controles
    )
    
    if (!is.null(res)) {
      resultados_lista[[paste(oc, nome_mod, sep="_")]] <- res
      cat(sprintf("   → %s: F-Stat = %.1f | Coef(2nd) = %.4f (p = %.3f)\n", 
                  nome_mod, res$F_stat_1st_estagio, res$coef_2nd_estagio, res$p_val_2nd_estagio))
    }
  }
}

# ------------------------------------------------------------------------------
# 6. COMPILAR E SALVAR
# ------------------------------------------------------------------------------
if (length(resultados_lista) == 0) stop("Nenhuma regressão concluída com sucesso.")

resultados_df <- bind_rows(resultados_lista) |>
  mutate(
    sig_2nd_estagio = case_when(
      p_val_2nd_estagio < 0.01 ~ "***",
      p_val_2nd_estagio < 0.05 ~ "**",
      p_val_2nd_estagio < 0.10 ~ "*",
      TRUE ~ ""
    ),
    coef_final_formatado = sprintf("%.4f%s", coef_2nd_estagio, sig_2nd_estagio)
  ) |>
  arrange(outcome_var, modelo_especificacao)

dir.create("03-resultados/csv", showWarnings = FALSE, recursive = TRUE)
output_file <- "03-resultados/csv/teste_stepwise_controles_multidimensional_1950.csv"
write_csv(resultados_df, output_file)

cat(sprintf("\n✅ PROCESSO CONCLUÍDO. %d modelos salvos em: %s\n", nrow(resultados_df), output_file))