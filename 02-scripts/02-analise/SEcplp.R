# ==============================================================================
# BATERIA V — SEGUNDO ESTÁGIO (TRATAMENTO FIXO EM 1969 + CONTROLES INCREMENTAIS)
# FOCO: CURTO E MÉDIO PRAZO (1970 - 2000)
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
cat("BATERIA V: SEGUNDO ESTÁGIO IV (ANO: 1969 | SEM PONTAS | INCREMENTAL)\n")
cat("PERÍODO DE ANÁLISE: CURTO E MÉDIO PRAZO (1970 - 2000)\n")
cat(strrep("=", 80), "\n\n")

# ==============================================================================
# SEÇÃO 1: CARREGAMENTO DE DADOS
# ==============================================================================
cat("ETAPA 1: Carregando e cruzando bases...\n")

if (!exists("base_iv_sf")) stop("ERRO: 'base_iv_sf' não encontrado. Execute a preparação.")
if (!exists("lista_amcs_pontas")) stop("ERRO: 'lista_amcs_pontas' não encontrado.")

outcomes_wide <- readRDS("01-dados/processados/outcomes/outcomes_amc_wide.rds")
ctrl_clima    <- readRDS("01-dados/processados/controles_clima_amcs_nordeste.rds")
ctrl_rios     <- readRDS("01-dados/processados/controles_rios_amcs_nordeste.rds")
ctrl_solo     <- readRDS("01-dados/processados/controles_solo_amcs_nordeste.rds")

# Construir Base Mestre
base_mestre <- base_iv_sf |>
  inner_join(outcomes_wide, by = "code_amc") |>
  left_join(ctrl_clima |> select(code_amc, bio_1, bio_12, bio_15), by = "code_amc") |>
  left_join(ctrl_rios |> select(code_amc, dist_rio_km, densidade_hidro_km_km2), by = "code_amc") |>
  left_join(ctrl_solo |> select(code_amc, pct_solo_latossolos, pct_solo_neossolos), by = "code_amc")


# ==============================================================================
# SEÇÃO 2: APLICAÇÃO DE FILTROS FIXOS DA AMOSTRA
# ==============================================================================
cat("ETAPA 2: Filtrando amostra (Excluindo AMCs Pontas e Dist > 100km)...\n")

# 1. Extrair códigos das pontas
codes_pontas <- lista_amcs_pontas$amcs_codigo |>
  stringr::str_split(" e ") |> unlist() |> as.numeric() |> na.omit() |> unique()

# 2. Filtrar a base (garantindo que 1969 não tem NAs)
df_limpo <- base_mestre |>
  filter(!is.na(dist_rail_real_1969)) |>
  filter(dist_rail_real_1969 <= 100) |>
  filter(!(code_amc %in% codes_pontas))

# 3. Recalcular Lag Espacial Sintético ESTRITAMENTE para a amostra limpa
vizinhos <- poly2nb(df_limpo, queen = TRUE)
pesos    <- nb2listw(vizinhos, style = "W", zero.policy = TRUE)
df_limpo$dist_sintetica_vizinhos <- lag.listw(pesos, df_limpo$dist_rail_sintetica_km, zero.policy = TRUE)

df_reg <- st_drop_geometry(df_limpo)
cat(sprintf("✓ Amostra final travada em %d AMCs.\n\n", nrow(df_reg)))


# ==============================================================================
# SEÇÃO 3: CONFIGURAÇÕES DA BATERIA
# ==============================================================================
cat("ETAPA 3: Configurando Regressões (Outcomes 1970-2000, 3 Tratamentos, 4 Modelos)...\n")

# Tratamentos Fixos em 1969
tratamentos <- list(
  list(nome = "Distância", endo = "dist_rail_real_1969",      inst = "dist_rail_sintetica_km"),
  list(nome = "Dummy",     endo = "dummy_atendida_real_1969", inst = "dummy_atendida_sintetica"),
  list(nome = "Densidade", endo = "densidade_real_1969",      inst = "densidade_sintetica")
)

# Outcomes: Curto e Médio Prazo (1970 - 2000)
outcomes_config <- list(
  # 1. PIB TOTAL (gap nos anos 90, usando 1996)
  list(escopo="1_PIB", nome="PIB Total (1970)",  col="pib_1970", transf="log"),
  list(escopo="1_PIB", nome="PIB Total (1980)",  col="pib_1980", transf="log"),
  list(escopo="1_PIB", nome="PIB Total (1996)",  col="pib_1996", transf="log"),
  list(escopo="1_PIB", nome="PIB Total (2000)",  col="pib_2000", transf="log"),
  
  # 2. PIB PER CAPITA
  list(escopo="2_PIB_pc", nome="PIB p.c. (1970)",  col="pib_percapita_1970", transf="log"),
  list(escopo="2_PIB_pc", nome="PIB p.c. (1980)",  col="pib_percapita_1980", transf="log"),
  list(escopo="2_PIB_pc", nome="PIB p.c. (1996)",  col="pib_percapita_1996", transf="log"),
  list(escopo="2_PIB_pc", nome="PIB p.c. (2000)",  col="pib_percapita_2000", transf="log"),
  
  # 3. DEMOGRAFIA E POPULAÇÃO
  list(escopo="3_Pop", nome="Pop. Total (1970)",  col="pop_total_1970", transf="log"),
  list(escopo="3_Pop", nome="Pop. Total (1980)",  col="pop_total_1980", transf="log"),
  list(escopo="3_Pop", nome="Pop. Total (1991)",  col="pop_total_1991", transf="log"),
  list(escopo="3_Pop", nome="Pop. Total (2000)",  col="pop_total_2000", transf="log"),
  
  # 4. URBANIZAÇÃO
  list(escopo="4_Urb", nome="Tx. Urban. (1970)",  col="tx_urbanizacao_1970", transf="nivel"),
  list(escopo="4_Urb", nome="Tx. Urban. (1980)",  col="tx_urbanizacao_1980", transf="nivel"),
  list(escopo="4_Urb", nome="Tx. Urban. (1991)",  col="tx_urbanizacao_1991", transf="nivel"),
  list(escopo="4_Urb", nome="Tx. Urban. (2000)",  col="tx_urbanizacao_2000", transf="nivel"),
  
  # 5. AGRICULTURA (Série PAM começa em 1974, usando 1975 como proxy para os 70s)
  list(escopo="5_PAM", nome="Val. Prod. (1975)",  col="valor_producao_mil_reais_1975", transf="log"),
  list(escopo="5_PAM", nome="Val. Prod. (1980)",  col="valor_producao_mil_reais_1980", transf="log"),
  list(escopo="5_PAM", nome="Val. Prod. (1991)",  col="valor_producao_mil_reais_1991", transf="log"),
  list(escopo="5_PAM", nome="Val. Prod. (2000)",  col="valor_producao_mil_reais_2000", transf="log"),
  
  # 6. INDICADORES SOCIAIS (Atlas PNUD só inicia em 1991)
  list(escopo="6_Soc", nome="IDHM (1991)",        col="adh_idhm_1991", transf="nivel"),
  list(escopo="6_Soc", nome="IDHM (2000)",        col="adh_idhm_2000", transf="nivel"),
  list(escopo="6_Soc", nome="% Pobres (1991)",    col="adh_pmpob_1991", transf="nivel"),
  list(escopo="6_Soc", nome="% Pobres (2000)",    col="adh_pmpob_2000", transf="nivel")
)

# Inclusão Incremental de Controles
especificacoes <- list(
  list(id = "M1", nome = "Base (Efeito Fixo UF)",          controles = "1"),
  list(id = "M2", nome = "+ Lag Espacial",                 controles = "dist_sintetica_vizinhos"),
  list(id = "M3", nome = "+ Clima",                        controles = "dist_sintetica_vizinhos + bio_1 + bio_12 + bio_15"),
  list(id = "M4", nome = "+ Geografia/Solo (Completa)",    controles = "dist_sintetica_vizinhos + bio_1 + bio_12 + bio_15 + dist_rio_km + pct_solo_latossolos")
)

# ==============================================================================
# SEÇÃO 4: LOOP DE REGRESSÕES (2SLS)
# ==============================================================================
cat("ETAPA 4: Estimando Modelos...\n\n")

resultados_2sls <- data.frame()
contador <- 0
total_regs <- length(outcomes_config) * length(tratamentos) * length(especificacoes)

for (out in outcomes_config) {
  if (!(out$col %in% names(df_reg))) {
    cat(sprintf("\n[Aviso] Variável %s não encontrada. Pulando...\n", out$col))
    next
  }
  
  for (trat in tratamentos) {
    for (esp in especificacoes) {
      contador <- contador + 1
      
      # Filtrar NAs específicos da iteração
      df_iter <- df_reg |> 
        filter(!is.na(.data[[out$col]]), !is.na(.data[[trat$endo]]), !is.na(.data[[trat$inst]]))
      
      if (out$transf == "log") {
        df_iter <- df_iter |> filter(.data[[out$col]] > 0)
        lhs <- paste0("log(", out$col, ")")
      } else {
        lhs <- out$col
      }
      
      # Fórmula feols (Y ~ Controles | FE | Endogena ~ Instrumento)
      form_str <- sprintf("%s ~ %s | state_abbr | %s ~ %s", lhs, esp$controles, trat$endo, trat$inst)
      
      tryCatch({
        modelo_iv <- feols(as.formula(form_str), data = df_iter, se = "hetero")
        
        # Extrair resultados
        coefs <- coef(modelo_iv)
        ses   <- se(modelo_iv)
        
        nome_coef <- paste0("fit_", trat$endo)
        if (!nome_coef %in% names(coefs)) nome_coef <- trat$endo
        
        coef_ss <- as.numeric(coefs[nome_coef])
        se_ss   <- as.numeric(ses[nome_coef])
        t_ss    <- coef_ss / se_ss
        p_ss    <- 2 * (1 - pnorm(abs(t_ss)))
        
        fs_obj <- fitstat(modelo_iv, "ivf")[[1]]
        f_stat <- if (is.list(fs_obj)) fs_obj$stat else as.numeric(fs_obj)
        
        res <- data.frame(
          Escopo       = out$escopo,
          Outcome      = out$nome,
          Tratamento   = trat$nome,
          Modelo       = esp$id,
          Desc_Modelo  = esp$nome,
          Coeficiente  = coef_ss,
          DP           = se_ss,
          P_Valor      = p_ss,
          F_Stat       = f_stat,
          N_Obs        = nobs(modelo_iv),
          stringsAsFactors = FALSE
        )
        
        resultados_2sls <- bind_rows(resultados_2sls, res)
        cat(sprintf("\rProgresso: [%d/%d] Estimando %s | %s | %s", contador, total_regs, out$nome, trat$nome, esp$id))
        
      }, error = function(e) {
        # Em caso de erro (ex: falta de dados num dos controles), guarda NA
      })
    }
  }
}
cat("\n\n✓ Bateria concluída!\n")

# ==============================================================================
# SEÇÃO 5: EXIBIÇÃO E EXPORTAÇÃO (MATRIZ DE SENSIBILIDADE)
# ==============================================================================

# Formatação limpa para o Console
tabela_console <- resultados_2sls |>
  mutate(
    Sig = case_when(P_Valor < 0.01 ~ "***", P_Valor < 0.05 ~ "**", P_Valor < 0.10 ~ "*", TRUE ~ ""),
    Resultado = sprintf("%+.4f%s (%.4f)", Coeficiente, Sig, DP),
    F_Stat    = sprintf("%.1f", F_Stat)
  ) |>
  select(Escopo, Outcome, Tratamento, Modelo, Resultado, F_Stat) |>
  # Pivotar para colocar os modelos lado a lado (M1, M2, M3, M4)
  pivot_wider(names_from = Modelo, values_from = c(Resultado, F_Stat)) |>
  arrange(Escopo, Outcome, Tratamento)

cat("\n", strrep("=", 120), "\n")
cat("RESULTADOS DE SENSIBILIDADE: CURTO E MÉDIO PRAZO (1970-2000)\n")
cat("Modelos: M1=Base(UF) | M2=+Lag Espacial | M3=+Clima | M4=+Geografia/Solo\n")
cat(strrep("=", 120), "\n\n")

print(tabela_console |> select(Escopo, Outcome, Tratamento, starts_with("Resultado")), n = Inf)

cat("\nSignificância: *** p<0.01, ** p<0.05, * p<0.10\n")

# Exportação do CSV completo
dir.create("03-resultados/csv", showWarnings = FALSE, recursive = TRUE)
caminho_csv <- "03-resultados/csv/resultados_2estagio_incremental_1970_2000.csv"
write_csv(resultados_2sls, caminho_csv)
cat(sprintf("\n✓ Tabela bruta detalhada salva em: %s\n", caminho_csv))