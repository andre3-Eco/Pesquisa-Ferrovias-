# ==============================================================================
# Etapa 20
# FIRST-STAGE IV (2SLS) – MÚLTIPLOS RAIOS DE BUFFER
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
base_densidade <- read_csv("01-dados/processados/base_densidade_buffer_multiraio.csv", show_col_types = FALSE)
painel_pontas <- read_csv("01-dados/processados/painel_amcs_pontas_ano_a_ano.csv", show_col_types = FALSE)
outcomes_interp <- readRDS("01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.rds")

ne_states <- c("MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA")

# -------------------- 2. PREPARAR BASE --------------------
base <- base_main %>%
  filter(state_abbr %in% ne_states) %>%
  # Remove colunas antigas de densidade genérica para evitar sufixos .x e .y
  select(-starts_with("densidade_")) %>%
  left_join(base_densidade, by = "code_amc") %>%
  # O left_join com painel_pontas foi removido aqui para evitar duplicação de AMCs!
  left_join(outcomes_interp, by = "code_amc")

# -------------------- 3. CONTROLES AMBIENTAIS --------------------
cat("Etapa 2: Carregando controles ambientais...\n")
ctrl_clima  <- readRDS("01-dados/processados/controles_clima_amcs_nordeste.rds")
ctrl_rios   <- readRDS("01-dados/processados/controles_rios_amcs_nordeste.rds")
ctrl_solo   <- readRDS("01-dados/processados/controles_solo_amcs_nordeste.rds")

base <- base %>%
  left_join(ctrl_clima  %>% select(code_amc, bio_1, bio_12, bio_15), by = "code_amc") %>%
  left_join(ctrl_rios   %>% select(code_amc, dist_rio_km, densidade_hidro_km_km2), by = "code_amc") %>%
  left_join(ctrl_solo   %>% select(code_amc, pct_solo_latossolos, pct_solo_neossolos), by = "code_amc")

# Atualiza as colunas após os joins
cols <- colnames(base)

# -------------------- 4. ANOS DE TRATAMENTO DISPONÍVEIS --------------------

# Detectar todas as colunas de densidade real da nova base
prefix_real  <- "densidade_buffer_real_"
treatment_cols_real <- grep(paste0("^", prefix_real, "[0-9]+km_[0-9]+$"), cols, value = TRUE)

# Extrair os anos capturando o último conjunto de números da string
get_year <- function(x) as.integer(sub(".*_", "", x))
anos_trat <- sort(unique(get_year(treatment_cols_real)))

cat(sprintf("   ✓ %d anos de tratamento encontrados: %d–%d\n\n",
            length(anos_trat), min(anos_trat), max(anos_trat)))

# -------------------- 5. CONTROLES FIXOS --------------------
fixed_controls <- paste(
  "bio_1", "bio_12", "bio_15",
  "dist_rio_km", "densidade_hidro_km_km2",
  "pct_solo_latossolos", "pct_solo_neossolos",
  sep = " + "
)

# -------------------- 6. FUNÇÃO FIRST STAGE (CORRIGIDA) --------------------
rodar_first_stage <- function(df, endo_var, inst_var, ano_trat) {
  if (!(endo_var %in% names(df)) || !(inst_var %in% names(df))) return(NULL)
  
  if (sum(!is.na(df[[inst_var]]) & df[[inst_var]] > 0, na.rm = TRUE) < 5) return(NULL)
  
  # A sintaxe para o 1º estágio é um OLS padrão com Efeitos Fixos.
  # A endógena é a Y, e o instrumento é o X, junto aos controles.
  formula_str <- sprintf(
    "%s ~ %s + %s | state_abbr",
    endo_var, inst_var, fixed_controls
  )
  
  tryCatch({
    mod <- feols(as.formula(formula_str), data = df, se = "hetero")
    ct  <- summary(mod)$coeftable
    
    if (!(inst_var %in% rownames(ct))) return(NULL)
    
    coef  <- ct[inst_var, 1]
    se    <- ct[inst_var, 2]
    t_stat<- ct[inst_var, 3]
    p_val <- ct[inst_var, 4]
    
    # Em um modelo com 1 único instrumento, o F-stat (Wald) é o quadrado da estatística t
    f_stat <- t_stat^2
    r2     <- fitstat(mod, "r2")[[1]]
    
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

# -------------------- 7. LOOP PRINCIPAL --------------------
cat("Etapa 3: Rodando regressões do Primeiro Estágio...\n")
resultados_lista <- list()
contador_total <- 0

for (ano_trat in anos_trat) {
  for (r in raios_km) {
    endo_var <- paste0("densidade_buffer_real_", r, "km_", ano_trat)
    inst_var <- paste0("densidade_buffer_sintetica_", r, "km_", ano_trat)
    
    if (!all(c(endo_var, inst_var) %in% cols)) next
    
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

# -------------------- 8. COMPILAR E SALVAR --------------------

if (length(resultados_lista) == 0) {
  stop("❌ Nenhuma regressão bem-sucedida. Verifique os dados e colunas.")
}

resultados_df <- bind_rows(resultados_lista) %>%
  arrange(variavel_endogena, ano_tratamento)

# Garantir que o diretório exista antes de salvar
output_dir <- "03-resultados/csv"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

output_file <- paste0(output_dir, "/first_stage_multiraio.csv")
write_csv(resultados_df, output_file)

cat("\n✅ RESULTADOS SALVOS COM SUCESSO!\n")
cat(sprintf("   Foram geradas %d regressões salvas em: %s\n", contador_total, output_file))