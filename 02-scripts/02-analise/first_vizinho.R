# ==============================================================================
# Etapa 25
# FIRST-STAGE: DENSIDADE, DUMMY E VIZINHOS (SINTÉTICA vs REAL) — SEM PONTAS
# Baseline OLS (Modelos Independentes para cada Mecanismo)
# ==============================================================================

library(tidyverse)
library(fixest)

if (!exists("data.wd")) {
  data.wd <- normalizePath(file.path(getwd(), "..", ".."))
}
setwd(data.wd)


# ------------------------------------------------------------------------------
# 1. CARREGAMENTO E INTEGRAÇÃO DAS BASES E CONTROLES
# ------------------------------------------------------------------------------

# Carrega a base principal
arquivo_principal <- "01-dados/processados/base_completa_integrada.csv"
if (file.exists(arquivo_principal)) {
  base_principal <- read_csv(arquivo_principal, show_col_types = FALSE)
} else {
  base_principal <- readRDS("01-dados/processados/base_completa_integrada.rds")
}

# Carrega a base NOVA gerada na Etapa 04
base_vizinhos <- readRDS("01-dados/processados/base_densidade_buffer_vizinhos.rds")

# Carrega os controles ambientais (mesma rotina do Segundo Estágio)
ctrl_clima  <- readRDS("01-dados/processados/controles_clima_amcs_nordeste.rds")
ctrl_rios   <- readRDS("01-dados/processados/controles_rios_amcs_nordeste.rds")
ctrl_solo   <- readRDS("01-dados/processados/controles_solo_amcs_nordeste.rds")

# Realiza o join dinâmico de TUDO: base principal + vizinhos + controles
base <- base_principal |>
  select(-starts_with("densidade_"), -starts_with("dens_"), -starts_with("dummy_"), -starts_with("vizinhos_")) |> 
  left_join(base_vizinhos, by = "code_amc") |>
  left_join(ctrl_clima |> select(code_amc, bio_1, bio_12, bio_15), by = "code_amc") |>
  left_join(ctrl_rios |> select(code_amc, dist_rio_km, densidade_hidro_km_km2), by = "code_amc") |>
  left_join(ctrl_solo |> select(code_amc, pct_solo_latossolos, pct_solo_neossolos), by = "code_amc")

ne_states <- c("MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA")

base <- base |>
  filter(state_abbr %in% ne_states)

cat(sprintf("   AMCs Nordeste na base unificada: %d\n", nrow(base)))

# Carrega o painel de pontas para exclusão nos anos de corte
painel_pontas <- read_csv(
  "01-dados/processados/painel_amcs_pontas_ano_a_ano.csv",
  show_col_types = FALSE
)

pontas_por_ano <- painel_pontas |>
  select(code_amc, ano_corte) |>
  distinct()

# ------------------------------------------------------------------------------
# 2. IDENTIFICAR ANOS DISPONÍVEIS
# ------------------------------------------------------------------------------

cols <- colnames(base)

# Busca os prefixos exatos gerados pela nova Etapa 04
dens_real_cols <- grep("^dens_real_[0-9]+$", cols, value = TRUE)
years <- sort(as.integer(sub("dens_real_", "", dens_real_cols)))

cat(sprintf("   %d anos disponíveis: %d–%d\n\n", length(years), min(years), max(years)))

# ------------------------------------------------------------------------------
# 3. LOOP PRINCIPAL: PRIMEIRO ESTÁGIO POR ANO E TIPO DE TRATAMENTO
# ------------------------------------------------------------------------------

fixed_controls <- paste(
  "bio_1", "bio_12", "bio_15",
  "dist_rio_km", "densidade_hidro_km_km2",
  "pct_solo_latossolos", "pct_solo_neossolos",
  sep = " + "
)

resultados <- list()

# Definição dos três pares de tratamento que serão testados
modelos_specs <- list(
  densidade = c(endog = "dens_real_", inst = "dens_sint_"),
  dummy     = c(endog = "dummy_real_", inst = "dummy_sint_"),
  spillover = c(endog = "vizinhos_dens_real_", inst = "vizinhos_dens_sint_")
)

for (ano in years) {
  
  # AMCs que eram pontas NESTE ano específico para excluir da base
  codes_pontas_ano <- pontas_por_ano |>
    filter(ano_corte == ano) |>
    pull(code_amc) |>
    unique()
  
  n_excluidas <- sum(base$code_amc %in% codes_pontas_ano)
  
  for (tipo in names(modelos_specs)) {
    
    endo_var <- paste0(modelos_specs[[tipo]]["endog"], ano)
    inst_var <- paste0(modelos_specs[[tipo]]["inst"], ano)
    
    if (!all(c(endo_var, inst_var) %in% cols)) next
    
    if (sum(base[[inst_var]], na.rm = TRUE) == 0) {
      next
    }
    
    df <- base |>
      select(
        code_amc, state_abbr,
        all_of(endo_var),
        all_of(inst_var),
        bio_1, bio_12, bio_15,
        dist_rio_km, densidade_hidro_km_km2,
        pct_solo_latossolos, pct_solo_neossolos
      ) |>
      filter(!(code_amc %in% codes_pontas_ano)) |>
      filter(
        is.finite(.data[[endo_var]]),
        is.finite(.data[[inst_var]]),
        !is.na(state_abbr)
      )
    
    if (nrow(df) < 10) next
    
    # Formula: endo ~ inst + controles | fixed_effects
    form_str <- sprintf(
      "%s ~ %s + %s | state_abbr",
      endo_var, inst_var, fixed_controls
    )
    
    tryCatch({
      modelo <- feols(as.formula(form_str), data = df, se = "hetero")
      
      coef_inst <- coef(modelo)[[inst_var]]
      se_inst   <- se(modelo)[[inst_var]]
      t_inst    <- coef_inst / se_inst
      p_inst    <- 2 * pt(abs(t_inst), df = nrow(df) - length(coef(modelo)) - 1,
                          lower.tail = FALSE)
      f_stat    <- t_inst^2 
      
      # Salva o resultado adicionando a coluna 'tipo_mecanismo'
      nome_lista <- paste0(tipo, "_", ano)
      
      resultados[[nome_lista]] <- tibble(
        ano                  = ano,
        tipo_mecanismo       = tipo,
        variavel_endogena    = endo_var,
        variavel_instrumento = inst_var,
        coeficiente          = coef_inst,
        erro_padrao          = se_inst,
        t_estatistica        = t_inst,
        p_valor              = p_inst,
        F_estatistica        = f_stat,
        n_observacoes        = nrow(df),
        n_pontas_excluidas   = n_excluidas
      )
    }, error = function(e) {
      cat(sprintf("  ⚠ Erro (%s) no ano %d: %s\n", tipo, ano, e$message))
    })
  }
  
  if (which(years == ano) %% 15 == 0) {
    cat(sprintf("  → Ano %d (%d/%d) processado | pontas excluídas: %d\n",
                ano, which(years == ano), length(years), n_excluidas))
  }
}

# ------------------------------------------------------------------------------
# 4. COMPILAR E SALVAR
# ------------------------------------------------------------------------------

if (length(resultados) == 0) stop("Nenhuma regressão bem-sucedida.")

resultados_df <- bind_rows(resultados) |>
  mutate(
    significancia = case_when(
      p_valor < 0.01 ~ "***",
      p_valor < 0.05 ~ "**",
      p_valor < 0.10 ~ "*",
      TRUE           ~ ""
    ),
    coeficiente_sig   = sprintf("%+.4f%s", coeficiente, significancia),
    instrumento_forte = F_estatistica >= 10
  ) |>
  arrange(tipo_mecanismo, ano)

dir.create("03-resultados/csv", showWarnings = FALSE, recursive = TRUE)

output_file <- "03-resultados/csv/first_stage_vizinhos_dummy_sem_pontas.csv"
write_csv(resultados_df, output_file)
cat(sprintf("   ✓ Resultados salvos em: %s\n\n", output_file))