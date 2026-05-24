# ==============================================================================
# BATERIA V — SEGUNDO ESTÁGIO (TRATAMENTO: DUMMY 1969 | MÚLTIPLOS LIMIARES)
# ==============================================================================

library(sf)
library(dplyr)
library(spdep)
library(fixest)
library(stringr)
library(readr)
library(tidyr)

sf_use_s2(FALSE)
if (!exists("data.wd")) data.wd <- getwd()

cat("\n", strrep("=", 80), "\n")
cat("BATERIA V: SEGUNDO ESTÁGIO IV (DUMMY 1969 | TESTE DE LIMIARES DE DISTÂNCIA)\n")
cat(strrep("=", 80), "\n\n")

# ==============================================================================
# SEÇÃO 1: CARREGAMENTO DA BASE MESTRE E CONTROLES (Rodado apenas 1 vez)
# ==============================================================================
cat("ETAPA 1: Carregando base mestre e calculando lag espacial estático...\n")

outcomes_wide <- readRDS("01-dados/processados/outcomes/outcomes_amc_wide.rds")
ctrl_clima    <- readRDS("01-dados/processados/controles_clima_amcs_nordeste.rds")
ctrl_rios     <- readRDS("01-dados/processados/controles_rios_amcs_nordeste.rds")
ctrl_solo     <- readRDS("01-dados/processados/controles_solo_amcs_nordeste.rds")

codes_pontas <- lista_amcs_pontas$amcs_codigo |>
  stringr::str_split(" e ") |> unlist() |> as.numeric() |> na.omit() |> unique()

base_mestre <- base_iv_sf |>
  inner_join(outcomes_wide, by = "code_amc") |>
  left_join(ctrl_clima |> select(code_amc, bio_1, bio_12, bio_15), by = "code_amc") |>
  left_join(ctrl_rios |> select(code_amc, dist_rio_km, densidade_hidro_km_km2), by = "code_amc") |>
  left_join(ctrl_solo |> select(code_amc, pct_solo_latossolos, pct_solo_neossolos), by = "code_amc") |>
  filter(!(code_amc %in% codes_pontas))

# Recalcular Lag Espacial Sintético ESTRITAMENTE para a amostra limpa
# (Como a distância contínua sintética não muda com os limiares, fazemos isso fora do loop)
vizinhos <- poly2nb(base_mestre, queen = TRUE)
pesos    <- nb2listw(vizinhos, style = "W", zero.policy = TRUE)
base_mestre$dist_sintetica_vizinhos <- lag.listw(pesos, base_mestre$dist_rail_sintetica_km, zero.policy = TRUE)

df_base_reg <- st_drop_geometry(base_mestre)

# ==============================================================================
# SEÇÃO 2: CONFIGURAÇÃO DE OUTCOMES E MODELOS
# ==============================================================================
# O Tratamento será atualizado dinamicamente pelo loop, mas os nomes das colunas são fixos:
tratamento <- list(endo = "dummy_atendida_real_1969", inst = "dummy_atendida_sintetica")

outcomes_config <- list(
  list(escopo="1_PIB", nome="PIB Total (2000)",   col="pib_2000", transf="log"),
  list(escopo="1_PIB", nome="PIB Total (2010)",   col="pib_2010", transf="log"),
  list(escopo="1_PIB", nome="PIB p.c. (2000)",    col="pib_percapita_2000", transf="log"),
  list(escopo="1_PIB", nome="PIB p.c. (2010)",    col="pib_percapita_2010", transf="log"),
  list(escopo="2_Pop", nome="Pop. Total (1991)",  col="pop_total_1991", transf="log"),
  list(escopo="2_Pop", nome="Pop. Total (2000)",  col="pop_total_2000", transf="log"),
  list(escopo="2_Pop", nome="Pop. Total (2010)",  col="pop_total_2010", transf="log"),
  list(escopo="2_Pop", nome="Tx. Urban. (2010)",  col="tx_urbanizacao_2010", transf="nivel"),
  list(escopo="3_PAM", nome="Val. Prod. (2000)",  col="valor_producao_mil_reais_2000", transf="log"),
  list(escopo="3_PAM", nome="Val. Prod. (2010)",  col="valor_producao_mil_reais_2010", transf="log"),
  list(escopo="4_Soc", nome="IDHM (2000)",        col="adh_idhm_2000", transf="nivel"),
  list(escopo="4_Soc", nome="IDHM (2010)",        col="adh_idhm_2010", transf="nivel"),
  list(escopo="4_Soc", nome="Renda p.c. (2000)",  col="adh_rdpc_2000", transf="log"),
  list(escopo="4_Soc", nome="Renda p.c. (2010)",  col="adh_rdpc_2010", transf="log"),
  list(escopo="4_Soc", nome="% Pobres (2010)",    col="adh_pmpob_2010", transf="nivel")
)

especificacoes <- list(
  list(id = "M1", nome = "Base", controles = "1"),
  list(id = "M2", nome = "+ Lag", controles = "dist_sintetica_vizinhos"),
  list(id = "M3", nome = "+ Clima", controles = "dist_sintetica_vizinhos + bio_1 + bio_12 + bio_15"),
  list(id = "M4", nome = "+ Geo",   controles = "dist_sintetica_vizinhos + bio_1 + bio_12 + bio_15 + dist_rio_km + pct_solo_latossolos")
)

# ==============================================================================
# SEÇÃO 3: LOOP TRIPLO (LIMIARES -> OUTCOMES -> MODELOS)
# ==============================================================================
cat("ETAPA 2: Estimando Modelos 2SLS para Múltiplos Limiares...\n\n")

limiares_km <- c(10, 25, 50, 100)
resultados_2sls <- data.frame()
contador <- 0
total_regs <- length(limiares_km) * length(outcomes_config) * length(especificacoes)

for (limiar in limiares_km) {
  
  # 1. Carregar Dummies do Limiar Atual
  arq_dummy <- sprintf("%s/01-dados/processados/limiares_atendimento/base_dummy_simples_%dkm.csv", data.wd, limiar)
  
  if (!file.exists(arq_dummy)) {
    cat(sprintf("\n[PULANDO] Arquivo não encontrado para %d km.\n", limiar))
    next
  }
  
  base_dummy <- read_csv(arq_dummy, show_col_types = FALSE) |> 
    select(code_amc, dummy_atendida_sintetica, dummy_atendida_real_1969)
  
  # 2. Acoplar na Base Mestre (Removendo as do limiar anterior, se houver)
  df_reg <- df_base_reg |> 
    select(-any_of(c("dummy_atendida_sintetica", "dummy_atendida_real_1969"))) |> 
    inner_join(base_dummy, by = "code_amc") |>
    filter(!is.na(dummy_atendida_real_1969), !is.na(dummy_atendida_sintetica))
  
  # 3. Loops Regulares de Outcome e Especificação
  for (out in outcomes_config) {
    if (!(out$col %in% names(df_reg))) next
    
    for (esp in especificacoes) {
      contador <- contador + 1
      
      df_iter <- df_reg |> 
        filter(!is.na(.data[[out$col]]))
      
      if (out$transf == "log") {
        df_iter <- df_iter |> filter(.data[[out$col]] > 0)
        lhs <- paste0("log(", out$col, ")")
      } else {
        lhs <- out$col
      }
      
      # Fórmula: Y ~ Controles | FE | Endogena ~ Instrumento
      form_str <- sprintf("%s ~ %s | state_abbr | %s ~ %s", lhs, esp$controles, tratamento$endo, tratamento$inst)
      
      tryCatch({
        modelo_iv <- feols(as.formula(form_str), data = df_iter, se = "hetero")
        
        coefs <- coef(modelo_iv)
        ses   <- se(modelo_iv)
        
        nome_coef <- paste0("fit_", tratamento$endo)
        if (!nome_coef %in% names(coefs)) nome_coef <- tratamento$endo
        
        # F-Stat
        fs_obj <- fitstat(modelo_iv, "ivf")[[1]]
        f_stat <- if (is.list(fs_obj)) fs_obj$stat else as.numeric(fs_obj)
        
        res <- data.frame(
          Limiar_km = paste0(limiar, " km"),
          Outcome   = out$nome,
          Modelo    = esp$id,
          Coef      = as.numeric(coefs[nome_coef]),
          DP        = as.numeric(ses[nome_coef]),
          P         = 2 * (1 - pnorm(abs(as.numeric(coefs[nome_coef]) / as.numeric(ses[nome_coef])))),
          F_Stat    = f_stat,
          N         = nobs(modelo_iv),
          stringsAsFactors = FALSE
        )
        
        resultados_2sls <- bind_rows(resultados_2sls, res)
        cat(sprintf("\rProgresso: [%d/%d] Estimando %d km | %s | %s...", contador, total_regs, limiar, out$nome, esp$id))
        
      }, error = function(e) {
        # Omitido para não poluir, mas você pode usar cat() aqui se quiser caçar erros específicos
      })
    }
  }
}
cat("\n\n✓ Bateria concluída!\n")

# ==============================================================================
# SEÇÃO 4: EXIBIÇÃO E EXPORTAÇÃO
# ==============================================================================

# Formatar a Tabela colocando os Limiares e Outcomes nas Linhas, e Modelos nas Colunas
tabela_final <- resultados_2sls |>
  mutate(Sig = case_when(P < 0.01 ~ "***", P < 0.05 ~ "**", P < 0.10 ~ "*", TRUE ~ "")) |>
  mutate(Valor = sprintf("%+.4f%s (%.4f)", Coef, Sig, DP)) |>
  select(Outcome, Limiar_km, Modelo, Valor) |>
  pivot_wider(names_from = Modelo, values_from = Valor) |>
  arrange(Outcome, Limiar_km)

cat("\n", strrep("=", 100), "\n")
cat("RESULTADOS: SEGUNDO ESTÁGIO POR LIMIARES DE DISTÂNCIA (DUMMY 1969)\n")
cat(strrep("=", 100), "\n\n")

print(tabela_final, n = Inf)

cat("\nSignificância: *** p<0.01, ** p<0.05, * p<0.10\n")

# Exportar base bruta com tudo (incluindo F-Stat para verificar validade em cada limiar)
dir.create("03-resultados/csv", showWarnings = FALSE, recursive = TRUE)
caminho_csv <- "03-resultados/csv/resultados_2estagio_limiares_dummy_1969.csv"
write_csv(resultados_2sls, caminho_csv)
cat(sprintf("\n✓ Tabela bruta salva em: %s\n", caminho_csv))