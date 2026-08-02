# ==============================================================================
# SECOND-STAGE IV (2SLS): HETEROGENEIDADE ESPACIAL (SEMIÁRIDO)
# Instrumento: densidade_buffer_sintetica_YYYY → densidade_buffer_real_YYYY
# Subamostras: Nordeste (Geral), Semiárido (1) e Não Semiárido (0)
# Outcomes: Maquinário 1920 e Instrução 
# Anos: até 1920
# ==============================================================================

library(tidyverse)
library(fixest)

if (!exists("data.wd")) {
  data.wd <- "C:/Users/André Elias/Documents/Pesquisa (Ferrovias)"
}
setwd(data.wd)

# ------------------------------------------------------------------------------
# 1. CARREGAMENTO DA BASE INTEGRADA E CONTROLES
# ------------------------------------------------------------------------------

arquivo_principal <- "01-dados/processados/base_completa_integrada_buffer.csv"
if (file.exists(arquivo_principal)) {
  base <- read_csv(arquivo_principal, show_col_types = FALSE)
} else {
  base <- readRDS("01-dados/processados/base_completa_integrada_buffer.rds")
}

ne_states <- c("MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA")
base <- base |> filter(state_abbr %in% ne_states)

if (!"semiarido" %in% names(base)) {
  stop("Coluna 'semiarido' não encontrada na base principal!")
}

painel_pontas <- read_csv("01-dados/processados/painel_amcs_pontas_ano_a_ano.csv", show_col_types = FALSE)
pontas_por_ano <- painel_pontas |> select(code_amc, ano_corte) |> distinct()

# ------------------------------------------------------------------------------
# 2. CARREGAR E PREPARAR OUTCOMES 1920 (MAQUINÁRIO)
# ------------------------------------------------------------------------------

outcomes_1920 <- readRDS("01-dados/processados/outcomes/interpolados/dados_1920_amc_interpolado.rds")

outcomes_1920 <- outcomes_1920 |>
  mutate(
    pct_commaquinas = ifelse(numeroestabelecimento > 0, commaquinas / numeroestabelecimento, NA),
    pct_cominstruagra = ifelse(numeroestabelecimento > 0, cominstruagra / numeroestabelecimento, NA)
  )

colunas_sobrepostas <- setdiff(intersect(names(base), names(outcomes_1920)), "code_amc")
if(length(colunas_sobrepostas) > 0) {
  base <- base |> select(-all_of(colunas_sobrepostas))
}

base <- base |> left_join(outcomes_1920, by = "code_amc")

cat(sprintf("Base preparada com %d AMCs no Nordeste.\n\n", nrow(base)))

# ------------------------------------------------------------------------------
# 3. IDENTIFICAR ANOS DE TRATAMENTO ATÉ 1920 E DEFINIR CONTROLES
# ------------------------------------------------------------------------------

cols <- colnames(base)
dens_real_cols <- grep("^densidade_buffer_real_[0-9]+$", cols, value = TRUE)
years <- sort(as.integer(sub("densidade_buffer_real_", "", dens_real_cols)))

years_1920 <- years[years <= 1920]

fixed_controls <- paste(
  "bio_1", "bio_12", "bio_15",
  "dist_rio_km", "densidade_hidro_km_km2",
  "pct_solo_latossolos", "pct_solo_neossolos",
  sep = " + "
)

outcomes_a_testar <- c("pct_commaquinas", "pct_cominstruagra")

# ------------------------------------------------------------------------------
# 4. FUNÇÃO AUXILIAR: RODAR 2SLS (fixest::feols)
# ------------------------------------------------------------------------------

rodar_2sls <- function(df, endo_var, inst_var, outcome_var, ano, subamostra) {
  
  outcome_col <- gsub("log\\(|\\)", "", outcome_var)
  
  if (!(outcome_col %in% names(df))) return(NULL)
  
  vals <- df[[outcome_col]]
  if (sum(!is.na(vals)) < 10) return(NULL)
  
  form_str <- sprintf(
    "%s ~ %s | state_abbr | %s ~ %s",
    outcome_var, fixed_controls, endo_var, inst_var
  )
  
  tryCatch({
    mod <- feols(as.formula(form_str), data = df, se = "hetero")
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
    
    tibble(
      ano_tratamento       = ano,
      subamostra           = subamostra,
      outcome_var          = outcome_var,
      variavel_endogena    = endo_var,
      variavel_instrumento = inst_var,
      coeficiente          = ct[nome_coef, 1],
      erro_padrao          = ct[nome_coef, 2],
      t_estatistica        = ct[nome_coef, 3],
      p_valor              = ct[nome_coef, 4],
      F_stat_1estagio      = f_stat,
      n_observacoes        = nrow(df)
    )
  }, error = function(e) {
    cat(sprintf("  ⚠ Erro [ano=%d, sub=%s, outcome=%s]: %s\n", ano, subamostra, outcome_var, e$message))
    NULL
  })
}

# ------------------------------------------------------------------------------
# 5. LOOP PRINCIPAL COM SUBAMOSTRAS (SEMIÁRIDO)
# ------------------------------------------------------------------------------

resultados <- list()
contador   <- 0

filtros_subamostra <- list(
  "Geral" = function(df) df,
  "Semiarido_Dummy1" = function(df) df |> filter(semiarido == 1),
  "Nao_Semiarido_Dummy0" = function(df) df |> filter(semiarido == 0)
)

cat("Iniciando regressões 2SLS (Heterogeneidade Espacial: Semiárido)...\n")

for (ano in years_1920) {
  
  endo_var <- paste0("densidade_buffer_real_", ano)
  inst_var <- paste0("densidade_buffer_sintetica_", ano)
  
  if (!all(c(endo_var, inst_var) %in% cols)) next
  if (sum(base[[inst_var]], na.rm = TRUE) == 0) next
  
  codes_pontas_ano <- pontas_por_ano |> filter(ano_corte == ano) |> pull(code_amc) |> unique()
  
  df_ano <- base |>
    filter(!(code_amc %in% codes_pontas_ano)) |>
    filter(
      is.finite(.data[[endo_var]]),
      is.finite(.data[[inst_var]]),
      !is.na(state_abbr)
    )
  
  for (nome_sub in names(filtros_subamostra)) {
    
    df_fatiada <- filtros_subamostra[[nome_sub]](df_ano)
    if (nrow(df_fatiada) < 15) next 
    
    for (oc_var in outcomes_a_testar) {
      res <- rodar_2sls(df_fatiada, endo_var, inst_var, oc_var, ano, nome_sub)
      if (!is.null(res)) {
        contador <- contador + 1
        resultados[[paste0(ano, "_", nome_sub, "_", oc_var)]] <- res
      }
    }
  }
}

# ------------------------------------------------------------------------------
# 6. COMPILAR E SALVAR RESULTADOS
# ------------------------------------------------------------------------------

cat(sprintf("\nConcluído! Total de %d regressões estimadas.\n", contador))

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
    ) |> 
    arrange(subamostra, ano_tratamento)
  
  dir.create("03-resultados/csv", showWarnings = FALSE, recursive = TRUE)
  output_file <- "03-resultados/csv/second_stage_1920_semiarido_maquinario.csv"
  write_csv(resultados_df, output_file)
  
  cat(sprintf("Resultados salvos em: %s\n", output_file))
} else {
  cat("Nenhuma regressão foi bem sucedida.\n")
}
