# ==============================================================================
# SECOND-STAGE IV (2SLS): EFEITOS DE SPILLOVER (VIZINHOS) MULTIDIMENSIONAL
# Instrumento: vizinhos_dens_sint_1950 → vizinhos_dens_real_1950
# Subamostras: Geral, Atendidos (dummy=1) e Não Atendidos (dummy=0)
# Outcomes: PIB Total/Setoriais (até 2023), População Total (até 2022), etc.
# Tratamento EXCLUSIVO: 1950
# ==============================================================================

library(tidyverse)
library(fixest)
library(stringr)

if (!exists("data.wd")) {
  data.wd <- normalizePath(file.path(getwd(), "..", ".."))
}
setwd(data.wd)

# ------------------------------------------------------------------------------
# 1. CARREGAMENTO DA BASE INTEGRADA E VIZINHOS (CORRIGIDO)
# ------------------------------------------------------------------------------
# Puxando a base que já possui o pib_2021, pop_total_2022 e os controles embutidos.
arquivo_principal <- "01-dados/processados/base_completa_integrada_buffer_com_pib_recente.csv"
base_principal <- read_csv(arquivo_principal, show_col_types = FALSE)

base_vizinhos <- readRDS("01-dados/processados/base_densidade_buffer_vizinhos.rds")

# Removemos qualquer sobreposição com a base de vizinhos para evitar sufixos .x/.y
colunas_sobrepostas_vizinhos <- setdiff(intersect(names(base_principal), names(base_vizinhos)), "code_amc")

base <- base_principal |>
  select(-all_of(colunas_sobrepostas_vizinhos)) |>
  left_join(base_vizinhos, by = "code_amc")

ne_states <- c("MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA")
base <- base |> filter(state_abbr %in% ne_states)

painel_pontas <- read_csv(
  "01-dados/processados/painel_amcs_pontas_ano_a_ano.csv",
  show_col_types = FALSE
)
pontas_por_ano <- painel_pontas |> select(code_amc, ano_corte) |> distinct()

# ------------------------------------------------------------------------------
# 2. CARREGAR E UNIR OUTCOMES INTERPOLADOS
# ------------------------------------------------------------------------------
outcomes_interp <- readRDS("01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.rds")

colunas_sobrepostas <- setdiff(intersect(names(base), names(outcomes_interp)), "code_amc")
base <- base |> 
  select(-all_of(colunas_sobrepostas)) |>
  left_join(outcomes_interp, by = "code_amc")

cat(sprintf("   AMCs Nordeste na base pronta para regressão: %d\n\n", nrow(base)))

# ------------------------------------------------------------------------------
# 3. MAPEAMENTO DE OUTCOMES POR ANO E ESCOPO 
# ------------------------------------------------------------------------------
cols <- colnames(base)

extract_years_from_prefix <- function(prefix) {
  pattern <- paste0("^", prefix, "_([0-9]+)$")
  years_found <- sub(pattern, "\\1", grep(pattern, cols, value = TRUE))
  if (length(years_found) == 0) return(NULL)
  sort(as.integer(years_found))
}

prefixos <- c(
  "pib", "pibag", "pibi", "pibse",
  "tx_urbanizacao", "pop_urbana", "pop_total",
  "adh_idhm", "adh_idhm_e", "adh_idhm_l", "adh_idhm_r"
)

outcomes_map <- tibble(
  prefixo = prefixos,
  anos_disponíveis = map(prefixos, extract_years_from_prefix),
  escopo = c(
    "PIB_Total", "PIB_Agropecuário", "PIB_Indústria", "PIB_Serviços",
    "Urbanização", "População_Urbana", "População_Total",
    "IDH_Geral", "IDH_Educação", "IDH_Longevidade", "IDH_Renda"
  ),
  needs_log = c(
    TRUE, TRUE, TRUE, TRUE,      
    FALSE, TRUE, TRUE,                 
    FALSE, FALSE, FALSE, FALSE    
  )
)

# ------------------------------------------------------------------------------
# 4. TRATAMENTO EXCLUSIVO: 1950 E CONTROLES
# ------------------------------------------------------------------------------
treatment_years <- c(1950)
cat(sprintf("   ✓ Tratamento de Spillover fixado no ano: %d\n\n", treatment_years))

fixed_controls <- paste(
  "bio_1", "bio_12", "bio_15",
  "dist_rio_km", "densidade_hidro_km_km2",
  "pct_solo_latossolos", "pct_solo_neossolos",
  sep = " + "
)

# ------------------------------------------------------------------------------
# 5. FUNÇÃO DE ESTIMAÇÃO (2SLS) COM IDENTIFICADOR DE SUBAMOSTRA
# ------------------------------------------------------------------------------
rodar_2sls <- function(df, endo_var, inst_var, outcome_col, outcome_nome, 
                       outcome_escopo, needs_log, ano_trat, subamostra) {
  
  if (!(outcome_col %in% names(df))) return(NULL)
  
  vals <- df[[outcome_col]]
  if (sum(!is.na(vals) & vals > 0, na.rm = TRUE) < 15) return(NULL)
  
  formula_str <- if (needs_log) {
    sprintf("log(%s) ~ %s | state_abbr | %s ~ %s", outcome_col, fixed_controls, endo_var, inst_var)
  } else {
    sprintf("%s ~ %s | state_abbr | %s ~ %s", outcome_col, fixed_controls, endo_var, inst_var)
  }
  
  tryCatch({
    mod <- feols(as.formula(formula_str), data = df, se = "hetero")
    ct <- summary(mod)$coeftable
    
    nome_coef <- paste0("fit_", endo_var)
    if (!(nome_coef %in% rownames(ct))) {
      if (endo_var %in% rownames(ct)) {
        nome_coef <- endo_var
      } else {
        return(NULL)
      }
    }
    
    f_stat <- tryCatch({ fitstat(mod, "ivf")[[1]]$stat }, error = function(e) NA_real_)
    r2 <- tryCatch({ summary(mod)$r.squared }, error = function(e) NA_real_)
    
    tibble(
      subamostra = subamostra,
      ano_tratamento = ano_trat,
      ano_outcome = as.integer(str_extract(outcome_col, "[0-9]+$")),
      escopo = outcome_escopo,
      outcome_var = outcome_nome,
      outcome_coluna = outcome_col,
      variavel_endogena = endo_var,
      variavel_instrumento = inst_var,
      coeficiente = ct[nome_coef, 1],
      erro_padrao = ct[nome_coef, 2],
      t_estatistica = ct[nome_coef, 3],
      p_valor = ct[nome_coef, 4],
      F_stat_1estagio = f_stat,
      R2_2estagio = r2,
      n_observacoes = nrow(df),
      significancia = case_when(
        ct[nome_coef, 4] < 0.01 ~ "***",
        ct[nome_coef, 4] < 0.05 ~ "**",
        ct[nome_coef, 4] < 0.10 ~ "*",
        TRUE ~ ""
      )
    )
  }, error = function(e) { 
    cat(sprintf("  ⚠ Falha [Ano: %d | Sub: %s | Var: %s] -> %s\n", ano_trat, subamostra, outcome_col, e$message))
    NULL 
  })
}

# ------------------------------------------------------------------------------
# 6. LOOP PRINCIPAL: SEGUNDO ESTÁGIO COM SUBAMOSTRAS (SPILLOVER)
# ------------------------------------------------------------------------------
resultados_lista <- list()
contador_total <- 0

# Estrutura de subamostras baseada na dummy de tratamento direto
filtros_subamostra <- list(
  "Geral" = function(df, d_var) df,
  "Atendidos_Dummy1" = function(df, d_var) df |> filter(.data[[d_var]] == 1),
  "Nao_Atendidos_Dummy0" = function(df, d_var) df |> filter(.data[[d_var]] == 0)
)

for (ano_trat in treatment_years) {
  
  endo_var <- paste0("vizinhos_dens_real_", ano_trat)
  inst_var <- paste0("vizinhos_dens_sint_", ano_trat)
  dummy_var <- paste0("dummy_real_", ano_trat)
  
  if (!all(c(endo_var, inst_var, dummy_var) %in% cols)) next
  
  codes_pontas <- pontas_por_ano |> filter(ano_corte == ano_trat) |> pull(code_amc) |> unique()
  
  df_ano <- base |>
    filter(!(code_amc %in% codes_pontas)) |>
    filter(
      is.finite(.data[[endo_var]]),
      is.finite(.data[[inst_var]]),
      !is.na(state_abbr)
    )
  
  for (nome_sub in names(filtros_subamostra)) {
    
    df_fatiada <- filtros_subamostra[[nome_sub]](df_ano, dummy_var)
    
    if (nrow(df_fatiada) < 20) {
      cat(sprintf("  ⚠ Subamostra '%s': n=%d — pulando.\n", nome_sub, nrow(df_fatiada)))
      next 
    }
    
    for (i in seq_len(nrow(outcomes_map))) {
      row <- outcomes_map[i, ]
      prefixo <- row$prefixo; escopo <- row$escopo; needs_log_val <- row$needs_log
      
      anos_outcome <- row$anos_disponíveis[[1]]
      if (is.null(anos_outcome) || length(anos_outcome) == 0) next
      anos_outcome <- anos_outcome[anos_outcome >= 1950]
      if (length(anos_outcome) == 0) next
      
      for (ano_out in anos_outcome) {
        outcome_col <- paste0(prefixo, "_", ano_out)
        outcome_nome <- paste0(prefixo, " (", ano_out, ")")
        
        res <- rodar_2sls(
          df = df_fatiada, endo_var = endo_var, inst_var = inst_var, 
          outcome_col = outcome_col, outcome_nome = outcome_nome, 
          outcome_escopo = escopo, needs_log = needs_log_val, 
          ano_trat = ano_trat, subamostra = nome_sub
        )
        
        if (!is.null(res)) {
          contador_total <- contador_total + 1
          resultados_lista[[contador_total]] <- res
        }
      }
    }
    cat(sprintf("   → Subamostra %s (1950) | N: %d | Regressões Executadas...\n", nome_sub, nrow(df_fatiada)))
  }
}

# ------------------------------------------------------------------------------
# 7. COMPILAR E SALVAR RESULTADOS
# ------------------------------------------------------------------------------
if (length(resultados_lista) == 0) stop("❌ Nenhuma regressão bem-sucedida.")

resultados_df <- bind_rows(resultados_lista) |>
  arrange(escopo, subamostra, ano_outcome)

dir.create("03-resultados/csv", showWarnings = FALSE, recursive = TRUE)
output_file <- "03-resultados/csv/second_stage_spillover_vizinhos_multidimensional_1950.csv"
write_csv(resultados_df, output_file)

cat(sprintf("\n✅ PROCESSO CONCLUÍDO. %d Regressões salvas em: %s\n", contador_total, output_file))