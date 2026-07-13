# ==============================================================================
# Etapa 23
# SECOND-STAGE IV (2SLS): DENSIDADE BUFFER SINTÉTICA → REAL — SEM PONTAS
# Recortes: Nordeste, Semiárido, Não-Semiárido e por UF (MA,PI,CE,RN,PB,PE,AL,SE,BA)
# Escopos: PIB, População, Social (ADH) e PAM (Anos selecionados)
#
# Base: base_completa_integrada_buffer.csv (já com coluna 'semiarido')
# ==============================================================================

library(tidyverse)
library(fixest)

# ---- Caminho fixo do projeto ----
proj_root <- "C:/Users/André Elias/Documents/Pesquisa (Ferrovias)"

# ------------------------------------------------------------------------------
# 1. CARREGAMENTO DA BASE UNIFICADA E PAINEL DE PONTAS
# ------------------------------------------------------------------------------


base <- read.csv(file.path(proj_root, "01-dados/processados/base_completa_integrada_buffer.csv"),
                 stringsAsFactors = FALSE)

ne_states <- c("MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA")
# Base já é só NE, mas filtramos por segurança
base <- base |> filter(state_abbr %in% ne_states)
cat(sprintf("  Linhas após filtro NE: %d | Colunas: %d\n", nrow(base), ncol(base)))

# Verificar se semiarido existe
if (!"semiarido" %in% names(base)) {
  stop("Coluna 'semiarido' não encontrada! Rode criar_dummy_semiarido.R primeiro.")
}
cat(sprintf("  semiárido=1: %d | semiárido=0: %d\n",
            sum(base$semiarido == 1), sum(base$semiarido == 0)))

painel_pontas <- read_csv(file.path(proj_root, "01-dados/processados/painel_amcs_pontas_ano_a_ano.csv"),
                          show_col_types = FALSE)
pontas_por_ano <- painel_pontas |> select(code_amc, ano_corte) |> distinct()
cat(sprintf("  Painel de pontas: %d linhas, anos de corte: %s\n",
            nrow(painel_pontas),
            paste(sort(unique(pontas_por_ano$ano_corte)), collapse = ", ")))

# ------------------------------------------------------------------------------
# 2. CARREGAR E UNIR OUTCOMES DOS 4 ESCOPOS (apenas anos essenciais)
# ------------------------------------------------------------------------------


outcomes_interp <- readRDS(file.path(proj_root,
                                     "01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.rds"))

# NOMES REAIS das variáveis na base:
#   Social: adh_idhm_1991, adh_idhm_2000, adh_idhm_2010, adh_gini_2010
#   PAM:    valor_producao_mil_reais_1974, valor_producao_mil_reais_2000, valor_producao_mil_reais_2010

outcomes_selecionados <- outcomes_interp |>
  select(
    code_amc,
    # 1. Escopo PIB
    pib_1920, pib_1949, pib_1980, pib_1985, pib_2000, pib_2003, pib_2010,
    # 2. Escopo População
    pop_total_1940, pop_total_1950, pop_total_1980, pop_total_1991, pop_total_2000, pop_total_2007, pop_total_2010,
    # 3. Escopo Social (ADH — nomes reais)
    adh_idhm_1991, adh_idhm_2000, adh_idhm_2010, adh_gini_2010,
    # 4. Escopo PAM / Agro (nomes reais)
    valor_producao_mil_reais_1974, valor_producao_mil_reais_1985,
    valor_producao_mil_reais_2000, valor_producao_mil_reais_2003,
    valor_producao_mil_reais_2010
  )

# Remover colunas sobrepostas antes do join
colunas_sobrepostas <- setdiff(intersect(names(base), names(outcomes_selecionados)), "code_amc")
cat(sprintf("  Colunas sobrepostas removidas: %d\n", length(colunas_sobrepostas)))

base <- base |>
  select(-all_of(colunas_sobrepostas)) |>
  left_join(outcomes_selecionados, by = "code_amc")

cat(sprintf("  Base após join: %d linhas × %d colunas\n", nrow(base), ncol(base)))

# ------------------------------------------------------------------------------
# 3. DEFINIR ANOS DE TRATAMENTO E MAPEAMENTO DE OUTCOMES
# ------------------------------------------------------------------------------

# Anos disponíveis na base (verificado):
#   1920 e 1950 existem; 1980 e 2000 NÃO existem.
#   Anos mais próximos disponíveis: 1985 e 2003.
anos_tratamento <- c(1920, 1950, 1985, 2003)

# Verificar se os anos de buffer existem
for (ano in anos_tratamento) {
  endo_var <- paste0("densidade_buffer_real_", ano)
  inst_var <- paste0("densidade_buffer_sintetica_", ano)
  if (!all(c(endo_var, inst_var) %in% colnames(base))) {
    stop(sprintf("Variáveis de buffer para ano %d não encontradas!", ano))
  }
}


fixed_controls <- paste(
  "bio_1", "bio_12", "bio_15",
  "dist_rio_km", "densidade_hidro_km_km2",
  "pct_solo_latossolos", "pct_solo_neossolos",
  sep = " + "
)

# Efeitos de Longo Prazo (Persistência) — sempre dados de 2010
outcomes_persistencia <- c(
  "log(pib_2010)",
  "log(pop_total_2010)",
  "adh_idhm_2010",
  "adh_gini_2010",
  "log(valor_producao_mil_reais_2010)"
)

# Efeitos Contemporâneos (Curto/Médio Prazo)
# Nomes reais: adh_idhm_* (não idhm_*), valor_producao_mil_reais_* (não pam_valor_*)
# Anos de tratamento: 1920, 1950, 1985 (sub. 1980), 2003 (sub. 2000)
# PIB e PAM devem bater com o ano; pop_total usa censos próximos (1980, 1991, 2000, 2007)
outcomes_contemporaneos <- list(
  "1920" = c("log(pib_1920)", "log(pop_total_1940)"),
  "1950" = c("log(pib_1949)", "log(pop_total_1950)"),
  "1985" = c("log(pib_1985)", "log(pop_total_1991)",
             "adh_idhm_1991", "log(valor_producao_mil_reais_1985)"),
  "2003" = c("log(pib_2003)", "log(pop_total_2007)",
             "adh_idhm_2000", "log(valor_producao_mil_reais_2003)")
)

# ------------------------------------------------------------------------------
# 4. FUNÇÃO AUXILIAR: RODAR 2SLS
# ------------------------------------------------------------------------------

rodar_2sls <- function(df, endo_var, inst_var, outcome_var, ano, tipo_outcome, grupo, use_fe) {

  outcome_col <- gsub("log\\(|\\)", "", outcome_var)  # extrai nome real da coluna

  # Pula se a variável não existir na base
  if (!(outcome_col %in% names(df))) return(NULL)

  vals <- df[[outcome_col]]
  # Precisa de pelo menos 10 obs não-NA, finitas e > 0 (para log)
  if (grepl("^log\\(", outcome_var)) {
    n_valid <- sum(!is.na(vals) & is.finite(vals) & vals > 0, na.rm = TRUE)
  } else {
    n_valid <- sum(!is.na(vals) & is.finite(vals), na.rm = TRUE)
  }
  if (n_valid < 10) return(NULL)

  if (use_fe) {
    form_str <- sprintf("%s ~ %s | state_abbr | %s ~ %s",
                        outcome_var, fixed_controls, endo_var, inst_var)
  } else {
    form_str <- sprintf("%s ~ %s | %s ~ %s",
                        outcome_var, fixed_controls, endo_var, inst_var)
  }

  tryCatch({
    mod <- feols(as.formula(form_str), data = df, se = "hetero")
    ct <- summary(mod)$coeftable

    # Encontrar o coeficiente da variável endógena no segundo estágio
    nome_coef <- paste0("fit_", endo_var)
    if (!(nome_coef %in% rownames(ct))) {
      if (endo_var %in% rownames(ct)) {
        nome_coef <- endo_var
      } else {
        return(NULL)
      }
    }

    # F-stat do primeiro estágio (usando fitstat com nome dinâmico — pitfall #3)
    f_stat <- tryCatch({
      fs <- fitstat(mod, "ivf")
      # Nome dinâmico: ivf1::<var_endogena>
      nomes_fs <- names(fs)
      idx <- grep("^ivf1::", nomes_fs)[1]
      if (!is.na(idx)) fs[[idx]]$stat else NA_real_
    }, error = function(e) NA_real_)

    tibble(
      grupo                = grupo,
      ano_tratamento       = ano,
      tipo_outcome         = tipo_outcome,
      outcome_var          = outcome_var,
      coeficiente          = ct[nome_coef, 1],
      erro_padrao          = ct[nome_coef, 2],
      t_estatistica        = ct[nome_coef, 3],
      p_valor              = ct[nome_coef, 4],
      F_stat_1estagio      = f_stat,
      n_observacoes        = nobs(mod)
    )
  }, error = function(e) { NULL })
}

# ------------------------------------------------------------------------------
# 5. LOOP PRINCIPAL
# ------------------------------------------------------------------------------


resultados <- list()
contador   <- 0
grupos_analise <- c("Nordeste", "Semiarido", "Nao_Semiarido", ne_states)

for (ano in anos_tratamento) {

  endo_var <- paste0("densidade_buffer_real_", ano)
  inst_var <- paste0("densidade_buffer_sintetica_", ano)

  # AMCs que são "pontas" neste ano (corte de ferrovia = ano)
  codes_pontas_ano <- pontas_por_ano |>
    filter(ano_corte == ano) |>
    pull(code_amc) |>
    unique()

  df_ano <- base |>
    filter(!(code_amc %in% codes_pontas_ano)) |>
    filter(is.finite(.data[[endo_var]]), is.finite(.data[[inst_var]]), !is.na(state_abbr))

  n_pontas <- length(codes_pontas_ano)
  cat(sprintf("Ano %d: %d AMCs na base, %d pontas excluídas, %d AMCs efetivos\n",
              ano, nrow(base), n_pontas, nrow(df_ano)))

  if (nrow(df_ano) < 10) {
    cat(sprintf("  ⚠ Poucas observações (n=%d), pulando ano.\n\n", nrow(df_ano)))
    next
  }

  for (grp in grupos_analise) {

    if (grp == "Nordeste") {
      df_grp <- df_ano; usar_fe <- TRUE
    } else if (grp == "Semiarido") {
      df_grp <- df_ano |> filter(semiarido == 1); usar_fe <- TRUE
    } else if (grp == "Nao_Semiarido") {
      df_grp <- df_ano |> filter(semiarido == 0); usar_fe <- TRUE
    } else {
      df_grp <- df_ano |> filter(state_abbr == grp); usar_fe <- FALSE
    }

    if (nrow(df_grp) < 10) {
      cat(sprintf("  ⚠ Grupo '%s': n=%d — pulando.\n", grp, nrow(df_grp)))
      next
    }

    # A. Modelos de Persistência (Longo Prazo)
    for (oc_var in outcomes_persistencia) {
      res <- rodar_2sls(df_grp, endo_var, inst_var, oc_var, ano, "persistencia", grp, usar_fe)
      if (!is.null(res)) {
        contador <- contador + 1
        resultados[[length(resultados) + 1]] <- res
      }
    }

    # B. Modelos Contemporâneos (Curto/Médio Prazo)
    vars_contemporaneas <- outcomes_contemporaneos[[as.character(ano)]]
    if (!is.null(vars_contemporaneas)) {
      for (oc_var in vars_contemporaneas) {
        res <- rodar_2sls(df_grp, endo_var, inst_var, oc_var, ano, "contemporaneo", grp, usar_fe)
        if (!is.null(res)) {
          contador <- contador + 1
          resultados[[length(resultados) + 1]] <- res
        }
      }
    }
  }
  cat(sprintf("  → Ano %d concluído | regressões acumuladas: %d\n\n", ano, contador))
}

# ------------------------------------------------------------------------------
# 6. COMPILAR RESULTADOS
# ------------------------------------------------------------------------------

if (length(resultados) > 0) {
  resultados_df <- bind_rows(resultados) |>
    mutate(
      significancia = case_when(
        p_valor < 0.01 ~ "***",
        p_valor < 0.05 ~ "**",
        p_valor < 0.10 ~ "*",
        TRUE           ~ ""
      ),
      coeficiente_sig = sprintf("%+.4f%s", coeficiente, significancia)
    )

  dir.create(file.path(proj_root, "03-resultados/csv"), showWarnings = FALSE, recursive = TRUE)
  output_file <- file.path(proj_root, "03-resultados/csv/second_stage_buffer_adaptado.csv")
  write_csv(resultados_df, output_file)

  cat(sprintf("\n✓ %d Regressões concluídas e salvas em:\n  %s\n",
              nrow(resultados_df), output_file))

  # Resumo rápido
  cat("\n--- Resumo por grupo ---\n")
  resultados_df |>
    count(grupo, tipo_outcome) |>
    pivot_wider(names_from = tipo_outcome, values_from = n, values_fill = 0) |>
    print(n = 20)

  cat("\n--- Top 10 resultados significantes (p < 0.05) ---\n")
  resultados_df |>
    filter(p_valor < 0.05) |>
    arrange(p_valor) |>
    select(grupo, ano_tratamento, tipo_outcome, outcome_var, coeficiente_sig, p_valor, F_stat_1estagio) |>
    head(10) |>
    print()

} else {
  cat("\n⚠ Nenhuma regressão foi bem-sucedida. Verifique os nomes das variáveis.\n")
}
