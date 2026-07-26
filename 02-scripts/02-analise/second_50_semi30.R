# ==============================================================================
# SECOND-STAGE IV (2SLS): MULTIDIMENSIONAL + HETEROGENEIDADE ESPACIAL
# Escopos: PIBs Setoriais, Urbanização e IDH (Decomposto)
# Tratamento EXCLUSIVO: 1950 (Densidade Buffer Real)
# Subamostras: Nordeste (Full), Semiárido, Não-Semiárido
# ==============================================================================

library(tidyverse)
library(fixest)
library(stringr)

if (!exists("data.wd")) {
  data.wd <- normalizePath(file.path(getwd(), "..", ".."))
}
setwd(data.wd)

# ==============================================================================
# 1. CARREGAR BASE UNIFICADA E PAINEL DE PONTAS
# ==============================================================================
base1 <- read_csv("01-dados/processados/base_completa_integrada_buffer.csv")

ne_states <- c("MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA")
base <- base |> filter(state_abbr %in% ne_states)

# Verificação crítica da coluna de subamostra requerida pelo desenho
if (!"semiarido" %in% names(base)) {
  stop("Coluna 'semiarido' não encontrada! Rode criar_dummy_semiarido.R primeiro.")
}
cat(sprintf("  semiárido=1: %d | semiárido=0: %d\n",
            sum(base$semiarido == 1), sum(base$semiarido == 0)))

painel_pontas <- read_csv(
  "01-dados/processados/painel_amcs_pontas_ano_a_ano.csv", 
  show_col_types = FALSE
)
pontas_por_ano <- painel_pontas |> select(code_amc, ano_corte) |> distinct()

# ==============================================================================
# 2. INTEGRAR OUTCOMES INTERPOLADOS
# ==============================================================================
outcomes_interp <- readRDS("01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.rds")

colunas_sobrepostas <- setdiff(intersect(names(base), names(outcomes_interp)), "code_amc")
base <- base |> 
  select(-all_of(colunas_sobrepostas)) |>
  left_join(outcomes_interp, by = "code_amc")

cat(sprintf("\n   ✓ Base final pronta: %d AMCs × %d colunas\n\n", nrow(base), ncol(base)))

# ==============================================================================
# 3. MAPEAMENTO DE OUTCOMES POR ANO
# ==============================================================================
cols <- colnames(base)

extract_years_from_prefix <- function(prefix) {
  pattern <- paste0("^", prefix, "_([0-9]+)$")
  years_found <- sub(pattern, "\\1", grep(pattern, cols, value = TRUE))
  if (length(years_found) == 0) return(NULL)
  sort(as.integer(years_found))
}

prefixos <- c(
  "pib", "pibag", "pibi", "pibse",
  "tx_urbanizacao", "pop_urbana",
  "adh_idhm", "adh_idhm_e", "adh_idhm_l", "adh_idhm_r"
)

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

# ==============================================================================
# 4. DEFINIÇÃO DE TRATAMENTO E CONTROLES
# ==============================================================================
treatment_years <- c(1950) 
cat(sprintf("   ✓ Tratamento fixado no ano: %d\n\n", treatment_years))

fixed_controls <- paste(
  "bio_1", "bio_12", "bio_15",
  "dist_rio_km", "densidade_hidro_km_km2",
  "pct_solo_latossolos", "pct_solo_neossolos",
  sep = " + "
)

# ==============================================================================
# 5. FUNÇÃO DE ESTIMAÇÃO (2SLS) COM IDENTIFICADOR DE GRUPO
# ==============================================================================
rodar_2sls <- function(df, endo_var, inst_var, outcome_col, outcome_nome, 
                       outcome_escopo, needs_log, ano_trat, grupo_nome) {
  
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
      if (endo_var %in% rownames(ct)) nome_coef <- endo_var else return(NULL)
    }
    
    f_stat <- tryCatch({ fitstat(mod, "ivf")[[1]]$stat }, error = function(e) NA_real_)
    r2 <- tryCatch({ summary(mod)$r.squared }, error = function(e) NA_real_)
    
    tibble(
      grupo = grupo_nome,
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
  }, error = function(e) { return(NULL) })
}

# ==============================================================================
# 6. LOOP PRINCIPAL: SEGUNDO ESTÁGIO POR SUBAMOSTRA
# ==============================================================================
resultados_lista <- list()
contador_total <- 0

# Vetor com os nomes dos grupos de análise baseados na variável indicadora
grupos_analise <- c("Nordeste", "Semiarido", "Nao_Semiarido")

for (ano_trat in treatment_years) {
  
  endo_var <- paste0("densidade_buffer_real_", ano_trat)
  inst_var <- paste0("densidade_buffer_sintetica_", ano_trat)
  
  codes_pontas <- pontas_por_ano |> filter(ano_corte == ano_trat) |> pull(code_amc) |> unique()
  
  df_ano <- base |>
    filter(!(code_amc %in% codes_pontas)) |>
    filter(is.finite(.data[[endo_var]]), is.finite(.data[[inst_var]]), !is.na(state_abbr))
  
  for (grp in grupos_analise) {
    
    # Executa a filtragem baseada na condição da subamostra
    if (grp == "Nordeste") {
      df_grp <- df_ano
    } else if (grp == "Semiarido") {
      df_grp <- df_ano |> filter(semiarido == 1)
    } else if (grp == "Nao_Semiarido") {
      df_grp <- df_ano |> filter(semiarido == 0)
    }
    
    if (nrow(df_grp) < 20) {
      cat(sprintf("  ⚠ Grupo '%s': n=%d — pulando.\n", grp, nrow(df_grp)))
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
          df = df_grp, endo_var = endo_var, inst_var = inst_var, 
          outcome_col = outcome_col, outcome_nome = outcome_nome, 
          outcome_escopo = escopo, needs_log = needs_log_val, 
          ano_trat = ano_trat, grupo_nome = grp
        )
        
        if (!is.null(res)) {
          contador_total <- contador_total + 1
          resultados_lista[[contador_total]] <- res
        }
      }
    }
    cat(sprintf("   → Grupo %s (1950) | N: %d | Regressões: %d\n", grp, nrow(df_grp), contador_total))
  }
}

# ==============================================================================
# 7. COMPILAR E SALVAR
# ==============================================================================
if (length(resultados_lista) == 0) stop("❌ Nenhuma regressão bem-sucedida.")

resultados_df <- bind_rows(resultados_lista) |>
  arrange(escopo, grupo, ano_outcome)

dir.create("03-resultados/csv", showWarnings = FALSE, recursive = TRUE)
output_file <- "03-resultados/csv/second_stage_multidimensional_1950_subamostras.csv"
write_csv(resultados_df, output_file)

cat("✅ PROCESSO CONCLUÍDO. Resultados salvos em:", output_file, "\n")