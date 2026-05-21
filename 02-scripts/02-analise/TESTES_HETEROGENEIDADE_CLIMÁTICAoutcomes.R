# ==============================================================================
# BATERIA DE TESTES IV: HETEROGENEIDADE CLIMÁTICA (15 OUTCOMES)
# ==============================================================================

library(sf)
library(dplyr)
library(tidyverse)
library(fixest)
library(broom)
library(geobr)
library(stringr)
library(readr)

if (!exists("data.wd")) data.wd <- getwd()
sf_use_s2(FALSE)

cat("\n", strrep("=", 90), "\n")
cat("TESTE DE HETEROGENEIDADE: EFEITO CLIMA (15 OUTCOMES | EXCLUINDO PONTAS)\n")
cat(strrep("=", 90), "\n\n")

# ==============================================================================
# SEÇÃO 1: CARREGAMENTO DE DADOS (BASE MESTRE + OUTCOMES + CLIMA)
# ==============================================================================
cat("ETAPA 1: Carregando bases...\n")

base_completa <- read_csv("01-dados/processados/base_completa_integrada.csv", show_col_types = FALSE)
outcomes_wide <- readRDS("01-dados/processados/outcomes/outcomes_amc_wide.rds")
base_clima    <- read_csv("01-dados/processados/controles_clima_amcs_nordeste.csv", show_col_types = FALSE)

dados_reg <- base_completa |>
  inner_join(outcomes_wide, by = "code_amc") |>
  inner_join(base_clima, by = "code_amc")

cat(sprintf("✓ Base inicial pronta com %d AMCs\n\n", nrow(dados_reg)))
 
# ==============================================================================
# SEÇÃO 2: DEFINIÇÃO DA VARIÁVEL CLIMÁTICA (SEMIÁRIDO)
# ==============================================================================
cat("ETAPA 2: Criando Dummy de Clima (Semiárido < 800mm)...\n")

colunas <- names(dados_reg)
var_chuva <- colunas[grepl("prec|bio_12|bio12", colunas, ignore.case = TRUE)][1]

if (!is.na(var_chuva)) {
  dados_reg <- dados_reg |>
    mutate(
      chuva_num = as.numeric(!!sym(var_chuva)),
      dummy_semiarido = ifelse(chuva_num < 800, 1, 0)
    )
} else {
  stop("ERRO: Nenhuma variável de precipitação ('prec' ou 'bio_12') foi encontrada.")
}

cat(sprintf("✓ Municípios no Semiárido na base inicial: %d\n\n", sum(dados_reg$dummy_semiarido, na.rm = TRUE)))

# ==============================================================================
# SEÇÃO 3: EXCLUSÃO DAS AMCs DAS PONTAS
# ==============================================================================
cat("ETAPA 3: Filtrando AMCs das extremidades...\n")

if (!exists("lista_amcs_pontas")) stop("ERRO: 'lista_amcs_pontas' não encontrado.")

codes_pontas_corr <- lista_amcs_pontas$amcs_codigo |>
  stringr::str_split(" e ") |>
  unlist() |> as.numeric() |> na.omit() |> unique() |> sort()

nrow_antes <- nrow(dados_reg)
dados_reg <- dados_reg |> filter(!(code_amc %in% codes_pontas_corr))

cat(sprintf("✓ Excluídas %d AMCs da amostra (restam %d observações).\n\n",
            nrow_antes - nrow(dados_reg), nrow(dados_reg)))

# ==============================================================================
# SEÇÃO 4: LISTA DE OUTCOMES E TRATAMENTOS
# ==============================================================================
outcomes_config <- list(
  list(escopo = "PIB", nome = "PIB (2000)",        coluna = "pib_2000", ano_trat = 1972, transf = "log"),
  list(escopo = "PIB", nome = "PIB (2010)",        coluna = "pib_2010", ano_trat = 1985, transf = "log"),
  list(escopo = "PIB", nome = "PIB p.c. (2000)",   coluna = "pib_percapita_2000", ano_trat = 1972, transf = "log"),
  list(escopo = "PIB", nome = "PIB p.c. (2010)",   coluna = "pib_percapita_2010", ano_trat = 1985, transf = "log"),
  list(escopo = "Pop", nome = "Pop. Total (1991)", coluna = "pop_total_1991", ano_trat = 1969, transf = "log"),
  list(escopo = "Pop", nome = "Pop. Total (2000)", coluna = "pop_total_2000", ano_trat = 1972, transf = "log"),
  list(escopo = "Pop", nome = "Pop. Total (2010)", coluna = "pop_total_2010", ano_trat = 1985, transf = "log"),
  list(escopo = "Pop", nome = "Tx. Urban. (2010)", coluna = "tx_urbanizacao_2010", ano_trat = 1985, transf = "nivel"),
  list(escopo = "PAM", nome = "Val. Prod. (2000)", coluna = "valor_producao_mil_reais_2000", ano_trat = 1972, transf = "log"),
  list(escopo = "PAM", nome = "Val. Prod. (2010)", coluna = "valor_producao_mil_reais_2010", ano_trat = 1985, transf = "log"),
  list(escopo = "Soc", nome = "IDHM (2000)",       coluna = "adh_idhm_2000", ano_trat = 1972, transf = "nivel"),
  list(escopo = "Soc", nome = "IDHM (2010)",       coluna = "adh_idhm_2010", ano_trat = 1985, transf = "nivel"),
  list(escopo = "Soc", nome = "Renda p.c. (2000)", coluna = "adh_rdpc_2000", ano_trat = 1972, transf = "log"),
  list(escopo = "Soc", nome = "Renda p.c. (2010)", coluna = "adh_rdpc_2010", ano_trat = 1985, transf = "log"),
  list(escopo = "Soc", nome = "% Pobres (2010)",   coluna = "adh_pmpob_2010", ano_trat = 1985, transf = "nivel")
)

tipos_trat <- list(
  list(tipo = "distancia", pref_end = "dist_rail_real_", pref_inst = "dist_rail_sintetica_km", desc = "Distância (km)"),
  list(tipo = "dummy",     pref_end = "dummy_atendida_real_", pref_inst = "dummy_atendida_sintetica", desc = "Dummy Atendimento")
)

# ==============================================================================
# SEÇÃO 5: LOOP DE REGRESSÃO COM INTERAÇÃO
# ==============================================================================
cat("ETAPA 4: Executando Regressões 2SLS (Amostra Restrita)...\n")

resultados_hetero <- data.frame()
total_regs <- length(outcomes_config) * length(tipos_trat)
contador <- 0

for (out in outcomes_config) {
  for (trat in tipos_trat) {
    contador <- contador + 1
    
    col_endo <- paste0(trat$pref_end, out$ano_trat)
    col_inst <- trat$pref_inst # O instrumento sintético é atemporal na sua base
    
    # Verifica se as colunas existem
    if (!all(c(col_endo, col_inst, out$coluna) %in% names(dados_reg))) next
    
    dados_modelo <- dados_reg |>
      mutate(
        val_endogena    = as.numeric(!!sym(col_endo)),
        val_instrumento = as.numeric(!!sym(col_inst)),
        val_outcome     = as.numeric(!!sym(out$coluna)),
        val_dummy_clima = as.numeric(dummy_semiarido)
      ) |>
      filter(!is.na(val_endogena), !is.na(val_instrumento), !is.na(val_outcome), !is.na(val_dummy_clima))
    
    # Aplica transformação logarítmica removendo zeros para evitar -Inf
    if (out$transf == "log") {
      dados_modelo <- dados_modelo |> filter(val_outcome > 0)
      dados_modelo$y_reg <- log(dados_modelo$val_outcome)
    } else {
      dados_modelo$y_reg <- dados_modelo$val_outcome
    }
    
    if (nrow(dados_modelo) < 30) next
    
    # Prepara as interações
    dados_modelo <- dados_modelo |>
      mutate(
        inter_endogena    = val_endogena * val_dummy_clima,
        inter_instrumento = val_instrumento * val_dummy_clima
      )
    
    formula_str <- "y_reg ~ val_dummy_clima | state_abbr | val_endogena + inter_endogena ~ val_instrumento + inter_instrumento"
    
    tryCatch({
      modelo_iv <- feols(as.formula(formula_str), data = dados_modelo)
      
      coefs <- coef(modelo_iv)
      ses   <- se(modelo_iv)
      pvals <- pvalue(modelo_iv)
      
      nome_endo  <- ifelse("fit_val_endogena" %in% names(coefs), "fit_val_endogena", "val_endogena")
      nome_inter <- ifelse("fit_inter_endogena" %in% names(coefs), "fit_inter_endogena", "inter_endogena")
      
      coef_princ <- as.numeric(coefs[nome_endo])
      se_princ   <- as.numeric(ses[nome_endo])
      pval_princ <- as.numeric(pvals[nome_endo])
      
      coef_inter <- as.numeric(coefs[nome_inter])
      se_inter   <- as.numeric(ses[nome_inter])
      pval_inter <- as.numeric(pvals[nome_inter])
      
      # Extração robusta do F-stat (pega o valor mínimo quando há múltiplas endógenas)
      f_stat <- NA
      try({
        fs_obj <- fitstat(modelo_iv, "ivf")
        if (!is.null(fs_obj)) f_stat <- min(as.numeric(unlist(fs_obj)), na.rm = TRUE)
      }, silent = TRUE)
      
      res_temp <- data.frame(
        Escopo          = out$escopo,
        Tratamento      = trat$desc,
        Outcome         = out$nome,
        Transf          = out$transf,
        Coef_Base       = coef_princ,
        DP_Base         = se_princ,
        Pval_Base       = pval_princ,
        Coef_Inter      = coef_inter,
        DP_Inter        = se_inter,
        Pval_Inter      = pval_inter,
        Efeito_Total    = coef_princ + coef_inter,
        F_Stat          = f_stat,
        N_Obs           = nobs(modelo_iv)
      )
      
      resultados_hetero <- bind_rows(resultados_hetero, res_temp)
      cat(sprintf("  [%02d/%02d] ✓ %-18s | %s\n", contador, total_regs, out$nome, trat$desc))
      
    }, error = function(e) {
      cat(sprintf("  [%02d/%02d] ⚠ Falha %s | %s: %s\n", contador, total_regs, out$nome, trat$desc, e$message))
    })
  }
}

# ==============================================================================
# SEÇÃO 6: EXIBIÇÃO E EXPORTAÇÃO
# ==============================================================================

cat("\n", strrep("=", 110), "\n")
cat("RESULTADOS: HETEROGENEIDADE POR CLIMA (LITORAL VS SEMIÁRIDO)\n")
cat("Nota: 'Base' = Efeito fora do Semiárido | 'Inter' = Efeito Adicional do Semiárido\n")
cat(strrep("=", 110), "\n\n")

tabela_console <- resultados_hetero |>
  mutate(
    Sig_Base  = case_when(Pval_Base < 0.01 ~ "***", Pval_Base < 0.05 ~ "**", Pval_Base < 0.10 ~ "*", TRUE ~ ""),
    Sig_Inter = case_when(Pval_Inter < 0.01 ~ "***", Pval_Inter < 0.05 ~ "**", Pval_Inter < 0.10 ~ "*", TRUE ~ "")
  ) |>
  transmute(
    Escopo,
    Outcome,
    Trat = case_when(Tratamento == "Distância (km)" ~ "Dist", TRUE ~ "Dummy"),
    `Base: Coef`  = sprintf("%+.4f%s", Coef_Base, Sig_Base),
    `Base: DP`    = sprintf("(%.4f)", DP_Base),
    `Inter: Coef`  = sprintf("%+.4f%s", Coef_Inter, Sig_Inter),
    `Inter: DP`    = sprintf("(%.4f)", DP_Inter),
    `Ef. Total`    = sprintf("%+.4f", Efeito_Total),
    `F-Stat`       = sprintf("%.1f", F_Stat),
    `N`            = N_Obs
  ) |> arrange(Escopo, Outcome)

print(tabela_console, row.names = FALSE)
cat("\nSignificância: *** p<0.01, ** p<0.05, * p<0.10\n")

# Exportar
dir.create("03-resultados/csv", showWarnings = FALSE, recursive = TRUE)
caminho_exportacao <- "03-resultados/csv/resultados_heterogeneidade_15outcomes.csv"
write_csv(resultados_hetero, caminho_exportacao)
cat(sprintf("\n✓ Tabela bruta salva em: %s\n", caminho_exportacao))