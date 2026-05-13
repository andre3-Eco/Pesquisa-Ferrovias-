# ==============================================================================
# BATERIA COMPLETA DE TESTES: PRIMEIRO E SEGUNDO ESTÁGIO (IV)
# ==============================================================================
# Script que executa análises IV (2SLS) com:
#   • Diferentes tipos de tratamento (distância, dummy, densidade)
#   • Diferentes outcomes (população, PIB setorial, PIB geral)
#   • Especificações variadas (efeitos fixos, excluindo pontas)
# ==============================================================================

library(sf)
library(dplyr)
library(tidyverse)
library(geobr)
library(spdep)
library(lmtest)
library(sandwich)
library(fixest)
library(knitr)
library(broom)
library(readxl)

# Configuração inicial
if (!exists("data.wd")) data.wd <- getwd()
sf_use_s2(FALSE)

cat("\n", strrep("=", 80), "\n")
cat("BATERIA DE TESTES: PRIMEIRO E SEGUNDO ESTÁGIO (IV)\n")
cat("Data:", format(Sys.time(), "%d/%m/%Y %H:%M:%S"), "\n")
cat(strrep("=", 80), "\n\n")

# ==============================================================================
# SEÇÃO 1: CARREGAMENTO DE DADOS
# ==============================================================================

cat("ETAPA 1: Carregando bases de dados...\n\n")

# Base integrada (contém distância, dummy, densidade)
base_completa <- read_csv(
  paste0(data.wd, "/base_completa_integrada.csv"),
  show_col_types = FALSE
)

cat(sprintf("✓ Base integrada carregada: %d AMCs\n", nrow(base_completa)))

# Geometria das AMCs do Nordeste
amcs_geometria <- read_comparable_areas(start_year = 1970, end_year = 2010) |>
  filter(substr(list_code_muni_2010, 1, 1) == "2") |>
  distinct(code_amc, .keep_all = TRUE) |>
  st_make_valid() |>
  st_transform(31984)

cat(sprintf("✓ Geometria das AMCs carregada: %d AMCs\n", nrow(amcs_geometria)))

# Ferrovias reais (para identificar pontas)
ferrovias_reais <- st_read(
  paste0(data.wd, "/ferrovias_cronologicas.gpkg"),
  quiet = TRUE
)

cat(sprintf("✓ Ferrovias reais carregadas: %d features\n", nrow(ferrovias_reais)))

# Dados de população
# (assumindo que 'população' está carregado na sessão)
if (!exists("população")) {
  warning("Objeto 'população' não encontrado. Carregando de população.xlsx...")
  população <- readxl::read_excel(paste0(data.wd, "/população.xlsx"))
}

cat(sprintf("✓ Dados de população carregados\n"))

# Dados de PIB 

pibtotal <- read_excel("tabelaspib.xlsx", 
                         sheet = "Tabela 1_2")
pibva <- read_excel("tabelaspib.xlsx", 
                       sheet = "Tabela 2_2")
pibag <- read_excel("tabelaspib.xlsx", 
                       sheet = "Tabela 3_2")
pibin <- read_excel("tabelaspib.xlsx", 
                       sheet = "Tabela 4_2")

# ==============================================================================
# SEÇÃO 2: PREPARAÇÃO DE DADOS DE OUTCOMES
# ==============================================================================

cat("\nETAPA 2: Preparando variáveis de outcome...\n\n")

# Agregação de população para nível de AMC
amc_lookup <- read_comparable_areas(start_year = 1970, end_year = 2010) |>
  st_drop_geometry() |>
  select(code_muni = list_code_muni_2010, code_amc) |>
  mutate(code_muni = as.character(code_muni))

pop_clean <- população |>
  rename(code_muni = `Cód.`) |>
  mutate(code_muni = as.character(code_muni))

pop_amc <- pop_clean |>
  inner_join(amc_lookup, by = "code_muni") |>
 
  mutate(across(starts_with("20"), as.numeric)) |> 
  group_by(code_amc) |>
  summarise(
    
    across(starts_with("20"), \(x) sum(x, na.rm = TRUE)),
    .groups = "drop"
  )

cat(sprintf("✓ População agregada para %d AMCs\n", nrow(pop_amc)))

# Tratar dados de PIB e agregar também
# Pib total
pibtotal_clean <- pibtotal |>
  rename(code_muni = `Cód.`) |>
  mutate(code_muni = as.character(code_muni))

pibtotal_amc <- pibtotal_clean|>
  inner_join(amc_lookup, by = "code_muni") |>
  
  mutate(across(starts_with("20"), as.numeric)) |> 
  group_by(code_amc) |>
  summarise(
    
    across(starts_with("20"), \(x) sum(x, na.rm = TRUE)),
    .groups = "drop"
  )

cat(sprintf("✓ PIB total agregada para %d AMCs\n", nrow(pibtotal_amc )))

# Pib valor agregado
pibva_clean <- pibva |>
  rename(code_muni = `Cód.`) |>
  mutate(code_muni = as.character(code_muni))

pibva_amc <- pibva_clean|>
  inner_join(amc_lookup, by = "code_muni") |>
  
  mutate(across(starts_with("20"), as.numeric)) |> 
  group_by(code_amc) |>
  summarise(
    
    across(starts_with("20"), \(x) sum(x, na.rm = TRUE)),
    .groups = "drop"
  )

cat(sprintf("✓ PIB Va agregada para %d AMCs\n", nrow(pibva_amc )))

# Pib agro
pibag_clean <- pibag |>
  rename(code_muni = `Cód.`) |>
  mutate(code_muni = as.character(code_muni))

pibag_amc <- pibag_clean|>
  inner_join(amc_lookup, by = "code_muni") |>
  
  mutate(across(starts_with("20"), as.numeric)) |> 
  group_by(code_amc) |>
  summarise(
    
    across(starts_with("20"), \(x) sum(x, na.rm = TRUE)),
    .groups = "drop"
  )

cat(sprintf("✓ PIB ag agregada para %d AMCs\n", nrow(pibag_amc )))

# Pib indus
pibin_clean <- pibin |>
  rename(code_muni = `Cód.`) |>
  mutate(code_muni = as.character(code_muni))

pibin_amc <- pibin_clean|>
  inner_join(amc_lookup, by = "code_muni") |>
  
  mutate(across(starts_with("20"), as.numeric)) |> 
  group_by(code_amc) |>
  summarise(
    
    across(starts_with("20"), \(x) sum(x, na.rm = TRUE)),
    .groups = "drop"
  )

cat(sprintf("✓ PIB in agregada para %d AMCs\n", nrow(pibin_amc )))

# ==============================================================================
# SEÇÃO 3: IDENTIFICAR AMCs NAS PONTAS DAS FERROVIAS
# ==============================================================================

cat("\nETAPA 3: Identificando AMCs nas extremidades das ferrovias...\n\n")

origens_pts <- ferrovias_reais |>
  group_by(id) |>
  filter(cod_part == min(cod_part)) |>
  ungroup() |>
  suppressWarnings(st_cast("POINT")) |>
  group_by(id) |>
  slice(1) |>
  ungroup() |>
  st_transform(31984)

destinos_pts <- ferrovias_reais |>
  group_by(id) |>
  filter(cod_part == max(cod_part)) |>
  ungroup() |>
  suppressWarnings(st_cast("POINT")) |>
  group_by(id) |>
  slice(n()) |>
  ungroup() |>
  st_transform(31984)

extremidades <- bind_rows(
  origens_pts  |> select(id, Nome) |> mutate(tipo = "origem"),
  destinos_pts |> select(id, Nome) |> mutate(tipo = "destino")
)

codes_pontas <- st_join(
  amcs_geometria |> select(code_amc),
  extremidades,
  join = st_contains
) |>
  st_drop_geometry() |>
  filter(!is.na(id)) |>
  distinct(code_amc) |>
  pull(code_amc)

cat(sprintf("✓ Identificadas %d AMCs nas pontas das ferrovias\n", length(codes_pontas)))

# ==============================================================================
# SEÇÃO 4: CONSTRUÇÃO DA BASE ANALÍTICA
# ==============================================================================

cat("\nETAPA 4: Construindo base analítica integrada...\n\n")

# Merge: geometria + população + distâncias/dummy/densidade
base_iv_sf <- amcs_geometria |>
  inner_join(pop_amc, by = "code_amc") |>
  inner_join(base_completa, by = "code_amc")

base_iv_sfpibtotal <- amcs_geometria |>
  inner_join(pibtotal_amc, by = "code_amc") |>
  inner_join(base_completa, by = "code_amc")

base_iv_sfpibva <- amcs_geometria |>
  inner_join(pibva_amc, by = "code_amc") |>
  inner_join(base_completa, by = "code_amc")

base_iv_sfpibag <- amcs_geometria |>
  inner_join(pibag_amc, by = "code_amc") |>
  inner_join(base_completa, by = "code_amc")

base_iv_sfpibin <- amcs_geometria |>
  inner_join(pibin_amc, by = "code_amc") |>
  inner_join(base_completa, by = "code_amc")

cat(sprintf("✓ Base analítica construída: %d AMCs\n", nrow(base_iv_sf)))

# ==============================================================================
# SEÇÃO 5: DEFINIÇÃO DE CONFIGURAÇÕES DE TESTE
# ==============================================================================

# Lista de especificações a testar
especificacoes <- list(
  list(
    nome = "Amostra completa",
    filtro = NULL,
    efeito_fixo = FALSE,
    label_efeito = ""
  ),
  list(
    nome = "Amostra completa com FE Estado",
    filtro = NULL,
    efeito_fixo = TRUE,
    label_efeito = " + state_abbr"
  ),
  list(
    nome = "Distância ≤ 200km + FE Estado",
    filtro = "dist_rail_real_2003 <= 200",
    efeito_fixo = TRUE,
    label_efeito = " + state_abbr"
  ),
  list(
    nome = "Distância ≤ 200km + Excluindo pontas + FE Estado",
    filtro = "dist_rail_real_2003 <= 200 & !(code_amc %in% codes_pontas)",
    efeito_fixo = TRUE,
    label_efeito = " + state_abbr"
  )
)

# Tipos de tratamento (variáveis independentes)
tratamentos <- list(
  list(
    nome = "distancia",
    var_endogena = "dist_rail_real_2003",
    var_instrumento = "dist_rail_sintetica_km",
    descricao = "Distância até ferrovia (km)"
  ),
  list(
    nome = "dummy",
    var_endogena = "dummy_atendida_real_2003",
    var_instrumento = "dummy_atendida_sintetica",
    descricao = "Dummy de atendimento por ferrovia"
  ),
  list(
    nome = "densidade",
    var_endogena = "densidade_real_2003",
    var_instrumento = "densidade_sintetica",
    descricao = "Densidade de ferrovias (km/1000km²)"
  )
)

# Outcomes de interesse
outcomes <- list(
  list(
    nome = "populacao_2003",
    variavel = "2003",
    descricao = "População (2003)"
  ),
  list(
    nome = "populacao_2010",
    variavel = "2010",
    descricao = "População (2010)"
  )
)


cat(sprintf("✓ Configurações de teste definidas:\n"))
cat(sprintf("  - %d especificações de amostra\n", length(especificacoes)))
cat(sprintf("  - %d tipos de tratamento\n", length(tratamentos)))
cat(sprintf("  - %d outcomes\n", length(outcomes)))
cat(sprintf("  - Total de combinações: %d\n\n", 
            length(especificacoes) * length(tratamentos) * length(outcomes)))

# ==============================================================================
# SEÇÃO 6: FUNÇÃO PARA RODAR PRIMEIRO E SEGUNDO ESTÁGIO
# ==============================================================================
dados <- base_iv_sf

rodar_analise_iv <- function(dados, 
                              var_endogena,
                              var_instrumento,
                              especificacao,
                              outcomes,
                              tratamento,
                              resultados_list) {
  
  tryCatch({
    # Número de observações
    n_obs <- nrow(dados)
    
    # --- PRIMEIRO ESTÁGIO: Reduzir forma ---
    formula_fs <- as.formula(paste(var_endogena, "~ ", var_instrumento, "+ dist_sintetica_vizinhos"))
    
    modelo_fs <- lm(formula_fs, data = dados)
    vcov_hc_fs <- vcovHC(modelo_fs, type = "HC1")
    coef_fs <- coef(modelo_fs)
    coef_fs_se <- sqrt(diag(vcov_hc_fs))
    
    # Teste F de força do instrumento
    f_test <- waldtest(modelo_fs, vcov = vcov_hc_fs)
    f_stat <- f_test$`F`[2]
    
    # R² do primeiro estágio
    r2_fs <- summary(modelo_fs)$r.squared
    
    # --- SEGUNDO ESTÁGIO: 2SLS com outcome ---
    # Fórmula: log(outcome) ~ 1 | var_endogena ~ var_instrumento
    formula_ss <- as.formula(
      paste("log(", outcomes, ") ~ 1 | ", 
            var_endogena, " ~ ", var_instrumento)
    )
    
    modelo_ss <- feols(formula_ss, data = dados)
    
    # Extrair coeficiente e SE do segundo estágio
    coef_ss <- coef(modelo_ss)[1]
    se_ss <- se(modelo_ss)[1]
    t_stat_ss <- coef_ss / se_ss
    p_value_ss <- 2 * (1 - pnorm(abs(t_stat_ss)))
    
    # R² do segundo estágio (pseudoR2)
    r2_ss <- modelo_ss$pseudo_r2
    
    # Armazenar resultados
    resultado <- data.frame(
      especificacao = especificacao,
      tratamento = tratamento,
      outcomes = outcomes,
      n_obs = n_obs,
      coef_fs = coef_fs[var_instrumento],
      se_fs = coef_fs_se[var_instrumento],
      f_stat = f_stat,
      r2_fs = r2_fs,
      coef_ss = coef_ss,
      se_ss = se_ss,
      t_stat = t_stat_ss,
      p_value = p_value_ss,
      r2_ss = r2_ss,
      stringsAsFactors = FALSE
    )
    
    return(resultado)
    
  }, error = function(e) {
    # Retornar linha com NA em caso de erro
    return(data.frame(
      especificacao = especificacao,
      tratamento = tratamento,
      outcomes = outcomes,
      n_obs = NA,
      coef_fs = NA,
      se_fs = NA,
      f_stat = NA,
      r2_fs = NA,
      coef_ss = NA,
      se_ss = NA,
      t_stat = NA,
      p_value = NA,
      r2_ss = NA,
      erro = e$message,
      stringsAsFactors = FALSE
    ))
  })
}

# ==============================================================================
# SEÇÃO 7: EXECUTAR BATERIA COMPLETA DE TESTES
# ==============================================================================

cat("\n", strrep("=", 80), "\n")
cat("EXECUTANDO BATERIA COMPLETA DE TESTES\n")
cat(strrep("=", 80), "\n\n")

resultados_completos <- data.frame()

for (i in seq_along(especificacoes)) {
  esp <- especificacoes[[i]]
  
  # Aplicar filtro
  if (is.null(esp$filtro)) {
    dados_filtrados <- base_iv_sf
  } else {
    dados_filtrados <- base_iv_sf |>
      filter(eval(parse(text = esp$filtro)))
  }
  
  cat(sprintf("\n%s ESPECIFICAÇÃO %d: %s (N=%d) %s\n",
              strrep("-", 20), i, esp$nome, nrow(dados_filtrados), strrep("-", 20)))
  
  # Calcular matriz de vizinhança e lag espacial
  vizinhos <- poly2nb(dados_filtrados, queen = TRUE)
  pesos <- nb2listw(vizinhos, style = "W", zero.policy = TRUE)
  
  dados_filtrados$dist_sintetica_vizinhos <- lag.listw(
    pesos, dados_filtrados$dist_rail_sintetica_km, zero.policy = TRUE
  )
  
  # Testar cada combinação de tratamento e outcome
  for (j in seq_along(tratamentos)) {
    trat <- tratamentos[[j]]
    
    for (k in seq_along(outcomes)) {
      out <- outcomes[[k]]
      
      # Pular se outcome não existe na base
      if (!out$variavel %in% names(dados_filtrados)) {
        cat(sprintf("  ⚠ Skipping %s x %s (outcome não encontrado)\n", 
                    trat$nome, out$nome))
        next
      }
      
      # Rodar análise
      res <- rodar_analise_iv(
        dados = dados_filtrados,
        var_endogena = trat$var_endogena,
        var_instrumento = trat$var_instrumento,
        outcome = out$variavel,
        especificacao = esp$nome,
        tratamento = trat$descricao,
        resultados_list = NULL
      )
      
      resultados_completos <- rbind(resultados_completos, res)
      
      # Feedback
      if (is.na(res$coef_ss)) {
        cat(sprintf("  ⚠ Erro: %s x %s\n", trat$nome, out$nome))
      } else {
        cat(sprintf("  ✓ %s x %s: β=%.4f (t=%.2f, p=%.3f), F=%.1f\n",
                    trat$nome, out$nome,
                    res$coef_ss, res$t_stat, res$p_value, res$f_stat))
      }
    }
  }
}

# ==============================================================================
# SEÇÃO 8: RESUMO E EXPORTAÇÃO DOS RESULTADOS
# ==============================================================================

cat("\n\n", strrep("=", 80), "\n")
cat("RESUMO DOS RESULTADOS\n")
cat(strrep("=", 80), "\n\n")

# Tabela de resultados
cat("TABELA COMPLETA DE RESULTADOS:\n\n")
print(resultados_completos, n = Inf)

# Salvar resultados em CSV
arquivo_saida <- paste0(data.wd, "/resultados_bateria_iv.csv")
write.csv(resultados_completos, arquivo_saida, row.names = FALSE)
cat(sprintf("\n✓ Resultados salvos em: %s\n", arquivo_saida))

# Resumo por especificação
cat("\n\nRESUMO POR ESPECIFICAÇÃO:\n")
resumo_esp <- resultados_completos |>
  group_by(especificacao) |>
  summarise(
    n_testes = n(),
    testes_sucesso = sum(!is.na(coef_ss)),
    coef_ss_medio = mean(coef_ss, na.rm = TRUE),
    f_stat_medio = mean(f_stat, na.rm = TRUE),
    .groups = "drop"
  )
print(resumo_esp)

# Resumo por tratamento
cat("\n\nRESUMO POR TIPO DE TRATAMENTO:\n")
resumo_trat <- resultados_completos |>
  group_by(tratamento) |>
  summarise(
    n_testes = n(),
    testes_sucesso = sum(!is.na(coef_ss)),
    coef_ss_medio = mean(coef_ss, na.rm = TRUE),
    f_stat_medio = mean(f_stat, na.rm = TRUE),
    .groups = "drop"
  )
print(resumo_trat)

# Salvar resumos
write.csv(resumo_esp, 
          paste0(data.wd, "/resumo_por_especificacao.csv"), 
          row.names = FALSE)
write.csv(resumo_trat, 
          paste0(data.wd, "/resumo_por_tratamento.csv"), 
          row.names = FALSE)

# ==============================================================================
# SEÇÃO 9: VALIDAÇÃO E DIAGNÓSTICO
# ==============================================================================

cat("\n\n", strrep("=", 80), "\n")
cat("DIAGNÓSTICO E VALIDAÇÃO\n")
cat(strrep("=", 80), "\n\n")

# Verificar instrumentos fracos
fraco_count <- sum(resultados_completos$f_stat < 10, na.rm = TRUE)
cat(sprintf("Instrumentos fracos (F < 10): %d testes\n", fraco_count))

# Significância estatística
sig_001 <- sum(resultados_completos$p_value < 0.01, na.rm = TRUE)
sig_005 <- sum(resultados_completos$p_value < 0.05, na.rm = TRUE)
sig_010 <- sum(resultados_completos$p_value < 0.10, na.rm = TRUE)

cat(sprintf("\nSignificância dos coeficientes (segundo estágio):\n"))
cat(sprintf("  p < 0.01: %d testes\n", sig_001))
cat(sprintf("  p < 0.05: %d testes\n", sig_005))
cat(sprintf("  p < 0.10: %d testes\n", sig_010))

# Estrutura dos dados
cat(sprintf("\nRESUMO GERAL:\n"))
cat(sprintf("  Total de testes executados: %d\n", nrow(resultados_completos)))
cat(sprintf("  Testes bem-sucedidos: %d\n", sum(!is.na(resultados_completos$coef_ss))))
cat(sprintf("  Testes com erro: %d\n", sum(is.na(resultados_completos$coef_ss))))

# ==============================================================================
# FIM DO SCRIPT
# ==============================================================================

cat("\n\n", strrep("=", 80), "\n")
cat("🎉 BATERIA DE TESTES CONCLUÍDA COM SUCESSO!\n")
cat(strrep("=", 80), "\n")
cat("Finalizado em:", format(Sys.time(), "%d/%m/%Y %H:%M:%S"), "\n\n")
