# ==============================================================================
# SECOND-STAGE IV (2SLS): HETEROGENEIDADE ESPACIAL COM PERSISTÊNCIA LONGO PRAZO
# Escopos: PIB e População (1970 a 2023)
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
# 1. CARREGAR BASE UNIFICADA RECENTE E PAINEL DE PONTAS
# ==============================================================================
# ATENÇÃO: É crítico utilizar a base com os dados recentes para evitar erros de colunas ausentes
base <- read_csv("01-dados/processados/base_completa_integrada_buffer_com_pib_recente.csv", show_col_types = FALSE)

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

cat(sprintf("\n   ✓ Base final pronta: %d AMCs × %d colunas\n\n", nrow(base), ncol(base)))

# ==============================================================================
# 2. DEFINIÇÃO DE TRATAMENTO, CONTROLES E OUTCOMES (LONGO PRAZO)
# ==============================================================================
treatment_years <- c(1950) 
cat(sprintf("   ✓ Tratamento fixado no ano: %d\n\n", treatment_years))

fixed_controls <- paste(
  "bio_1", "bio_12", "bio_15",
  "dist_rio_km", "densidade_hidro_km_km2",
  "pct_solo_latossolos", "pct_solo_neossolos",
  sep = " + "
)

# Vetor com todos os outcomes de 1970 até o presente
outcomes_alvo <- c(
  "log(pib_1970)", "log(pop_total_1970)",
  "log(pib_1980)", "log(pop_total_1980)",
  "log(pop_total_1991)", 
  "log(pib_2000)", "log(pop_total_2000)",
  "log(pib_2010)", "log(pop_total_2010)",
  "log(pib_2021)", 
  "log(pop_total_2022)", 
  "log(pib_2023)"
)

# ==============================================================================
# 3. FUNÇÃO DE ESTIMAÇÃO (2SLS) COM IDENTIFICADOR DE GRUPO
# ==============================================================================
rodar_2sls <- function(df, endo_var, inst_var, outcome_var, ano_trat, grupo_nome) {
  
  # Extrai o nome real da coluna removendo a sintaxe log()
  outcome_col <- gsub("log\\(|\\)", "", outcome_var)
  
  if (!(outcome_col %in% names(df))) return(NULL)
  
  vals <- df[[outcome_col]]
  if (sum(!is.na(vals) & vals > 0, na.rm = TRUE) < 15) return(NULL)
  
  if (var(df[[inst_var]], na.rm = TRUE) == 0) return(NULL)
  
  formula_str <- sprintf("%s ~ %s | state_abbr | %s ~ %s", 
                         outcome_var, fixed_controls, endo_var, inst_var)
  
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
      outcome_var = outcome_var,
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
# 4. LOOP PRINCIPAL: SEGUNDO ESTÁGIO POR SUBAMOSTRA
# ==============================================================================
resultados_lista <- list()
contador_total <- 0

# Vetor com os nomes dos grupos de análise
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
    
    # Roda a regressão IV iterando diretamente sobre o vetor de outcomes recentes
    for (oc_var in outcomes_alvo) {
      res <- rodar_2sls(
        df = df_grp, 
        endo_var = endo_var, 
        inst_var = inst_var, 
        outcome_var = oc_var, 
        ano_trat = ano_trat, 
        grupo_nome = grp
      )
      
      if (!is.null(res)) {
        contador_total <- contador_total + 1
        resultados_lista[[contador_total]] <- res
      }
    }
    cat(sprintf("   → Grupo %s (1950) | N: %d | Regressões: %d\n", grp, nrow(df_grp), contador_total))
  }
}

# ==============================================================================
# 5. COMPILAR E SALVAR
# ==============================================================================
if (length(resultados_lista) == 0) stop("❌ Nenhuma regressão bem-sucedida.")

resultados_df <- bind_rows(resultados_lista) |>
  arrange(grupo, ano_outcome)

dir.create("03-resultados/csv", showWarnings = FALSE, recursive = TRUE)
output_file <- "03-resultados/csv/second_stage_longo_prazo_1950_subamostras.csv"
write_csv(resultados_df, output_file)

cat("✅ PROCESSO CONCLUÍDO. Resultados salvos em:", output_file, "\n")