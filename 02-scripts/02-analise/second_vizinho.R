# ==============================================================================
# Etapa 26
# SECOND-STAGE IV (2SLS): EFEITOS DE SPILLOVER (VIZINHOS) COM SUBAMOSTRAS
# Instrumento: vizinhos_dens_sint_YYYY → vizinhos_dens_real_YYYY
# Subamostras: Geral, Atendidos (dummy=1) e Não Atendidos (dummy=0)
# ==============================================================================

library(tidyverse)
library(fixest)

if (!exists("data.wd")) {
  data.wd <- normalizePath(file.path(getwd(), "..", ".."))
}
setwd(data.wd)

# ------------------------------------------------------------------------------
# 1. CARREGAMENTO DA BASE INTEGRADA E CONTROLES (Corrigido)
# ------------------------------------------------------------------------------

arquivo_principal <- "01-dados/processados/base_completa_integrada.csv"
if (file.exists(arquivo_principal)) {
  base_principal <- read_csv(arquivo_principal, show_col_types = FALSE)
} else {
  base_principal <- readRDS("01-dados/processados/base_completa_integrada.rds")
}

base_vizinhos <- readRDS("01-dados/processados/base_densidade_buffer_vizinhos.rds")

# Carrega os controles ambientais perdidos
ctrl_clima  <- readRDS("01-dados/processados/controles_clima_amcs_nordeste.rds")
ctrl_rios   <- readRDS("01-dados/processados/controles_rios_amcs_nordeste.rds")
ctrl_solo   <- readRDS("01-dados/processados/controles_solo_amcs_nordeste.rds")

# Faz o merge garantindo todas as peças do quebra-cabeça
base <- base_principal |>
  select(-starts_with("densidade_"), -starts_with("dens_"), -starts_with("dummy_"), -starts_with("vizinhos_")) |> 
  left_join(base_vizinhos, by = "code_amc") |>
  left_join(ctrl_clima |> select(code_amc, bio_1, bio_12, bio_15), by = "code_amc") |>
  left_join(ctrl_rios |> select(code_amc, dist_rio_km, densidade_hidro_km_km2), by = "code_amc") |>
  left_join(ctrl_solo |> select(code_amc, pct_solo_latossolos, pct_solo_neossolos), by = "code_amc")

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

outcomes_selecionados <- outcomes_interp |>
  select(
    code_amc,
    pib_1920, pib_1939, pib_1949, pib_1959,
    pib_1970, pib_1975, pib_1980, pib_1985,
    pib_1996, pib_1999, pib_2000, pib_2003, pib_2010,
    pop_total_1940, pop_total_1950, pop_total_1960,
    pop_total_1970, pop_total_1980, pop_total_1991,
    pop_total_1996, pop_total_2000, pop_total_2010
  )

colunas_sobrepostas <- setdiff(intersect(names(base), names(outcomes_selecionados)), "code_amc")
base <- base |> 
  select(-all_of(colunas_sobrepostas)) |> 
  left_join(outcomes_selecionados, by = "code_amc")

cat(sprintf("   AMCs Nordeste na base pronta para regressão: %d\n\n", nrow(base)))

# ------------------------------------------------------------------------------
# 3. IDENTIFICAR ANOS E DEFINIR MAPA DE OUTCOMES
# ------------------------------------------------------------------------------

cols <- colnames(base)
# Usando o prefixo da variável de vizinhos real para mapear os anos
dens_real_cols <- grep("^vizinhos_dens_real_[0-9]+$", cols, value = TRUE)
years <- sort(as.integer(sub("vizinhos_dens_real_", "", dens_real_cols)))

fixed_controls <- paste(
  "bio_1", "bio_12", "bio_15",
  "dist_rio_km", "densidade_hidro_km_km2",
  "pct_solo_latossolos", "pct_solo_neossolos",
  sep = " + "
)

outcomes_persistencia <- c("log(pib_2010)", "log(pib_2003)", "log(pop_total_2010)", "log(pop_total_2000)")

contemporaneo_map <- tribble(
  ~ano_min, ~ano_max, ~outcome_pib,         ~outcome_pop,
  1858,     1929,     "log(pib_1920)",       "log(pop_total_1940)",
  1930,     1938,     "log(pib_1939)",       "log(pop_total_1940)",
  1939,     1948,     "log(pib_1939)",       "log(pop_total_1940)",
  1949,     1958,     "log(pib_1949)",       "log(pop_total_1950)",
  1959,     1969,     "log(pib_1959)",       "log(pop_total_1960)",
  1970,     1974,     "log(pib_1970)",       "log(pop_total_1970)",
  1975,     1979,     "log(pib_1975)",       "log(pop_total_1970)",
  1980,     1984,     "log(pib_1980)",       "log(pop_total_1980)",
  1985,     1995,     "log(pib_1985)",       "log(pop_total_1991)",
  1996,     1998,     "log(pib_1996)",       "log(pop_total_1996)",
  1999,     1999,     "log(pib_1999)",       "log(pop_total_2000)",
  2000,     2002,     "log(pib_2000)",       "log(pop_total_2000)",
  2003,     2003,     "log(pib_2003)",       "log(pop_total_2000)"
)

get_contemporaneo <- function(ano) {
  row <- contemporaneo_map |> filter(ano >= ano_min, ano <= ano_max)
  if (nrow(row) == 0) return(NULL)
  list(pib = row$outcome_pib[1], pop = row$outcome_pop[1])
}

# ------------------------------------------------------------------------------
# 4. FUNÇÃO AUXILIAR: RODAR 2SLS (fixest::feols) CORRIGIDA E VERBOSA
# ------------------------------------------------------------------------------

rodar_2sls <- function(df, endo_var, inst_var, outcome_var, ano, tipo_outcome, subamostra) {
  
  outcome_col <- gsub("log\\(|\\)", "", outcome_var)
  
  if (!(outcome_col %in% names(df))) return(NULL)
  
  vals <- df[[outcome_col]]
  if (sum(!is.na(vals) & vals > 0, na.rm = TRUE) < 10) return(NULL)
  
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
      ano                  = ano,
      subamostra           = subamostra,
      tipo_outcome         = tipo_outcome,
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
    # NOVIDADE: Em vez de falhar em silêncio, vai cuspir a causa exata no console.
    cat(sprintf("  ⚠ Falha [Ano: %d | Sub: %s | Var: %s] -> %s\n", ano, subamostra, outcome_col, e$message))
    NULL 
  })
}
# ------------------------------------------------------------------------------
# 5. LOOP PRINCIPAL: SEGUNDO ESTÁGIO COM SUBAMOSTRAS
# ------------------------------------------------------------------------------

resultados <- list()
contador   <- 0

# Estrutura de subamostras para o loop
filtros_subamostra <- list(
  "Geral" = function(df, d_var) df,
  "Atendidos_Dummy1" = function(df, d_var) df |> filter(.data[[d_var]] == 1),
  "Nao_Atendidos_Dummy0" = function(df, d_var) df |> filter(.data[[d_var]] == 0)
)

for (ano in years) {
  
  endo_var <- paste0("vizinhos_dens_real_", ano)
  inst_var <- paste0("vizinhos_dens_sint_", ano)
  dummy_var <- paste0("dummy_real_", ano)
  
  if (!all(c(endo_var, inst_var, dummy_var) %in% cols)) next
  if (sum(base[[inst_var]], na.rm = TRUE) == 0) next
  
  codes_pontas_ano <- pontas_por_ano |> filter(ano_corte == ano) |> pull(code_amc) |> unique()
  
  # Base limpa do ano (sem pontas e com dados válidos)
  df_ano <- base |>
    filter(!(code_amc %in% codes_pontas_ano)) |>
    filter(
      is.finite(.data[[endo_var]]),
      is.finite(.data[[inst_var]]),
      !is.na(state_abbr)
    )
  
  for (nome_sub in names(filtros_subamostra)) {
    
    # Aplica o filtro da dummy (1, 0, ou todos)
    df_fatiada <- filtros_subamostra[[nome_sub]](df_ano, dummy_var)
    
    if (nrow(df_fatiada) < 15) next # Pula se a fatia ficou muito pequena
    
    # A. Modelos de Persistência
    for (oc_var in outcomes_persistencia) {
      res <- rodar_2sls(df_fatiada, endo_var, inst_var, oc_var, ano, "persistencia", nome_sub)
      if (!is.null(res)) {
        contador <- contador + 1
        resultados[[paste0("p_", ano, "_", nome_sub, "_", oc_var)]] <- res
      }
    }
    
    # B. Modelos Contemporâneos
    ct <- get_contemporaneo(ano)
    if (!is.null(ct)) {
      for (oc_var in unique(c(ct$pib, ct$pop))) {
        res <- rodar_2sls(df_fatiada, endo_var, inst_var, oc_var, ano, "contemporaneo", nome_sub)
        if (!is.null(res)) {
          contador <- contador + 1
          resultados[[paste0("c_", ano, "_", nome_sub, "_", oc_var)]] <- res
        }
      }
    }
  }
  
  if (which(years == ano) %% 10 == 0 || ano == max(years)) {
    cat(sprintf("  → Ano %d processado | regressões acumuladas: %d\n", ano, contador))
  }
}

# ------------------------------------------------------------------------------
# 6. COMPILAR E SALVAR RESULTADOS
# ------------------------------------------------------------------------------
cat("\n5. Compilando e salvando resultados...\n")

if (length(resultados) == 0) stop("Nenhuma regressão bem-sucedida.")

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
  arrange(subamostra, ano, tipo_outcome)

dir.create("03-resultados/csv", showWarnings = FALSE, recursive = TRUE)

output_file <- "03-resultados/csv/second_stage_spillover_vizinhos_subamostras.csv"
write_csv(resultados_df, output_file)

cat(sprintf("   ✓ %d Regressões validadas\n", nrow(resultados_df)))
cat(sprintf("   ✓ Resultados salvos em: %s\n\n", output_file))
cat("✅ PROCESSO CONCLUÍDO.\n")