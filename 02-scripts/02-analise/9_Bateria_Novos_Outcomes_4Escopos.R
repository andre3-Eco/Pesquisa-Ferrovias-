# ==============================================================================
# BATERIA IV — 4 ESCOPOS DE OUTCOMES (NOVOS)
# ==============================================================================
# Script : 9_Bateria_Novos_Outcomes_4Escopos.R
# Criado : 17/05/2026
#
# ESTRUTURA DA BATERIA:
#   Escopos : 4 (PIB, Pop, PAM, Social/IDHM)
#   Outcomes: 15 variáveis dependentes
#   Tratamentos: 3 tipos (distância, dummy, densidade)
#   Especificações: 4 (variando amostra e tipo de controles)
#   Total : 4 especificações × 15 outcomes × 3 tratamentos = 180 regressões
#
# INOVAÇÕES vs. bateria anterior (8_Bateria_Completa_PIB_Pop.R):
#   1. Tratamento defasado ≥20 anos em relação ao outcome (por construção):
#        outcomes 1991 → tratamento de 1969 (22 anos)
#        outcomes 2000 → tratamento de 1972 (28 anos)
#        outcomes 2010 → tratamento de 1985 (25 anos)
#   2. Controles alternam entre 3 tipos nas 4 especificações:
#        lag espacial / clima / rios+solo / completo (todos)
#   3. Exclusão de AMCs nas pontas corrigida:
#        Anterior: st_contains → 4 AMCs (maioria das pontas estava na fronteira)
#        Atual   : st_nearest_feature → 44 AMCs (toda extremidade tem AMC associada)
#   4. Outcomes novos de todos os 4 escopos do projeto
#
# PRÉ-REQUISITOS (objetos na sessão R):
#   base_iv_sf   — geometria AMCs + tratamentos + instrumentos
#   extremidades — pontos de extremidade das ferrovias (sf)
#   (Controles e outcomes são carregados do disco)
#
# SAÍDAS:
#   03-resultados/csv/resultados_bateria9_novos_outcomes.csv
#   03-resultados/tabelas/tabela_bateria9_novos_outcomes.html  (opcional)
# ==============================================================================

library(sf)
library(dplyr)
library(spdep)
library(fixest)
library(tidyr)
library(readr)

sf_use_s2(FALSE)

if (!exists("data.wd")) data.wd <- getwd()

cat("\n", strrep("=", 80), "\n")
cat("BATERIA IV — 4 ESCOPOS DE OUTCOMES (NOVOS)\n")
cat("Data:", format(Sys.time(), "%d/%m/%Y %H:%M:%S"), "\n")
cat(strrep("=", 80), "\n\n")


# ==============================================================================
# SEÇÃO 1: CONSTRUIR BASE MESTRE
# ==============================================================================
# Combina:
#   base_iv_sf        → geometria + tratamentos anuais + instrumentos
#   outcomes_amc_wide → todos os outcomes dos 4 escopos (formato wide)
#   ctrl_clima        → bio_1, bio_12, bio_15 (variáveis WorldClim)
#   ctrl_rios         → distância e densidade hídrica
#   ctrl_solo         → composição pedológica por AMC

cat("SEÇÃO 1: Carregando e integrando bases...\n")

base_completa <- read_csv("01-dados/processados/base_completa_integrada.csv")
base_iv_sf <- amcs_geometria |>
  inner_join(base_completa, by = "code_amc")

if (!exists("base_iv_sf")) stop("'base_iv_sf' não encontrado. Execute o pipeline de preparação primeiro.")
if (!exists("extremidades")) stop("'extremidades' não encontrado. Execute 6_Bateria_Testes_Etapas_I_II.R primeiro.")

# Outcomes novos (4 escopos)
outcomes_wide <- readRDS("01-dados/processados/outcomes/outcomes_amc_wide.rds")

# Controles (carrega do disco se não estiver na sessão)
if (!exists("ctrl_clima")) ctrl_clima <- readRDS("01-dados/processados/controles_clima_amcs_nordeste.rds")
if (!exists("ctrl_rios"))  ctrl_rios  <- readRDS("01-dados/processados/controles_rios_amcs_nordeste.rds")
if (!exists("ctrl_solo"))  ctrl_solo  <- readRDS("01-dados/processados/controles_solo_amcs_nordeste.rds")

# Montar base mestre (geometry preservada para cálculo do lag espacial)
base_mestre <- base_iv_sf |>
  left_join(outcomes_wide, by = "code_amc") |>
  left_join(
    ctrl_clima |> select(code_amc, bio_1, bio_12, bio_15),
    by = "code_amc"
  ) |>
  left_join(
    ctrl_rios |> select(code_amc, dist_rio_km, densidade_hidro_km_km2),
    by = "code_amc"
  ) |>
  left_join(
    ctrl_solo |> select(code_amc, pct_solo_latossolos, pct_solo_neossolos,
                        pct_solo_luvissolos, pct_solo_planossolos),
    by = "code_amc"
  )

cat(sprintf("  ✓ Base mestre: %d AMCs × %d colunas\n\n", nrow(base_mestre), ncol(base_mestre)))


# ==============================================================================
# SEÇÃO 2: IDENTIFICAR AMCs NAS PONTAS (MÉTODO CORRIGIDO)
# ==============================================================================
# Problema do método anterior (st_contains):
#   st_contains exige que o ponto esteja ESTRITAMENTE dentro do polígono.
#   Pontos sobre fronteiras são excluídos → só 4 AMCs identificadas de 52 pontas.
#
# Solução (st_nearest_feature):
#   Para cada ponto de extremidade, encontra o polígono AMC mais próximo.
#   Garante que toda ponta seja associada a uma AMC → 44 AMCs identificadas.

cat("SEÇÃO 2: Identificando AMCs nas pontas das ferrovias (método corrigido)...\n")

# CRS já deve ser 31984 (SIRGAS 2000 / UTM 24S) — verificar por precaução
if (sf::st_crs(extremidades) != sf::st_crs(base_mestre)) {
  extremidades <- sf::st_transform(extremidades, sf::st_crs(base_mestre))
}

nearest_idx      <- sf::st_nearest_feature(extremidades, base_mestre |> select(code_amc))
codes_pontas_corr <- base_mestre$code_amc[nearest_idx] |> unique() |> sort()

cat(sprintf("  Extremidades encontradas  : %d pontos\n", nrow(extremidades)))
cat(sprintf("  Método anterior (st_contains)    : ~4 AMCs\n"))
cat(sprintf("  Método corrigido (nearest_feature): %d AMCs\n\n", length(codes_pontas_corr)))


# ==============================================================================
# SEÇÃO 3: DEFINIR OUTCOMES
# ==============================================================================
# Cada outcome especifica:
#   escopo   → grupo temático (1=PIB, 2=Pop, 3=PAM, 4=Social)
#   coluna   → nome da coluna em outcomes_amc_wide / base_mestre
#   rotulo   → rótulo para tabelas e gráficos
#   ano_trat → ano de referência do tratamento (≥20 anos antes do outcome)
#   transf   → "log" (variáveis monetárias/contagem) ou "nivel" (índices/taxas)
#
# Critério de defasagem temporal:
#   outcome em 1991 → tratamento de 1969 (22 anos de defasagem)
#   outcome em 2000 → tratamento de 1972 (28 anos de defasagem)
#   outcome em 2010 → tratamento de 1985 (25 anos de defasagem)

cat("SEÇÃO 3: Definindo outcomes...\n")

outcomes_config <- list(

  # ── ESCOPO 1: PIB e Renda ────────────────────────────────────────────────────
  list(escopo = "1_PIB",
       nome   = "pib_2000",
       coluna = "pib_2000",
       rotulo = "PIB Total (2000, R$ mil, preços 2010)",
       ano_trat = 1972, transf = "log"),

  list(escopo = "1_PIB",
       nome   = "pib_2010",
       coluna = "pib_2010",
       rotulo = "PIB Total (2010, R$ mil, preços 2010)",
       ano_trat = 1985, transf = "log"),

  list(escopo = "1_PIB",
       nome   = "pib_percapita_2000",
       coluna = "pib_percapita_2000",
       rotulo = "PIB per capita (2000, R$/hab)",
       ano_trat = 1972, transf = "log"),

  list(escopo = "1_PIB",
       nome   = "pib_percapita_2010",
       coluna = "pib_percapita_2010",
       rotulo = "PIB per capita (2010, R$/hab)",
       ano_trat = 1985, transf = "log"),

  # ── ESCOPO 2: Dinâmica Demográfica ──────────────────────────────────────────
  list(escopo = "2_Pop",
       nome   = "pop_total_1991",
       coluna = "pop_total_1991",
       rotulo = "Pop. Total (1991)",
       ano_trat = 1969, transf = "log"),

  list(escopo = "2_Pop",
       nome   = "pop_total_2000",
       coluna = "pop_total_2000",
       rotulo = "Pop. Total (2000)",
       ano_trat = 1972, transf = "log"),

  list(escopo = "2_Pop",
       nome   = "pop_total_2010",
       coluna = "pop_total_2010",
       rotulo = "Pop. Total (2010)",
       ano_trat = 1985, transf = "log"),

  list(escopo = "2_Pop",
       nome   = "tx_urban_2010",
       coluna = "tx_urbanizacao_2010",
       rotulo = "Taxa de Urbanização (2010, 0–1)",
       ano_trat = 1985, transf = "nivel"),

  # ── ESCOPO 3: Transformação Estrutural (PAM) ─────────────────────────────────
  list(escopo = "3_PAM",
       nome   = "valproducao_2000",
       coluna = "valor_producao_mil_reais_2000",
       rotulo = "Valor da Produção Agrícola (2000, R$ mil)",
       ano_trat = 1972, transf = "log"),

  list(escopo = "3_PAM",
       nome   = "valproducao_2010",
       coluna = "valor_producao_mil_reais_2010",
       rotulo = "Valor da Produção Agrícola (2010, R$ mil)",
       ano_trat = 1985, transf = "log"),

  # ── ESCOPO 4: Desenvolvimento Humano ─────────────────────────────────────────
  list(escopo = "4_Social",
       nome   = "idhm_2000",
       coluna = "adh_idhm_2000",
       rotulo = "IDHM (2000, 0–1)",
       ano_trat = 1972, transf = "nivel"),

  list(escopo = "4_Social",
       nome   = "idhm_2010",
       coluna = "adh_idhm_2010",
       rotulo = "IDHM (2010, 0–1)",
       ano_trat = 1985, transf = "nivel"),

  list(escopo = "4_Social",
       nome   = "rdpc_2000",
       coluna = "adh_rdpc_2000",
       rotulo = "Renda dom. per capita (2000, R$, preços 2010)",
       ano_trat = 1972, transf = "log"),

  list(escopo = "4_Social",
       nome   = "rdpc_2010",
       coluna = "adh_rdpc_2010",
       rotulo = "Renda dom. per capita (2010, R$, preços 2010)",
       ano_trat = 1985, transf = "log"),

  list(escopo = "4_Social",
       nome   = "pmpob_2010",
       coluna = "adh_pmpob_2010",
       rotulo = "% Pobres (2010, linha R$255/mês)",
       ano_trat = 1985, transf = "nivel")
)

n_outcomes <- length(outcomes_config)
n_trats    <- 3L
n_esps     <- 4L
n_total    <- n_esps * n_outcomes * n_trats

cat(sprintf("  %d outcomes em 4 escopos\n", n_outcomes))
cat(sprintf("  %d especificações × %d outcomes × %d tratamentos = %d regressões\n\n",
            n_esps, n_outcomes, n_trats, n_total))


# ==============================================================================
# SEÇÃO 4: DEFINIR ESPECIFICAÇÕES
# ==============================================================================
# As 4 especificações variam em:
#   (a) Filtro de amostra  : todas AMCs vs. dist ≤ 200km vs. + excluir pontas
#   (b) Tipo de controles  : lag espacial / clima / rios+solo / completo
#
# Controles disponíveis:
#   Lag espacial : dist_sintetica_vizinhos (lag espacial rainha da rede sintética)
#   Clima        : bio_1 (temp. média anual), bio_12 (precip. anual),
#                  bio_15 (sazonalidade da precipitação)
#   Rios + Solo  : dist_rio_km, densidade_hidro_km_km2,
#                  pct_solo_latossolos, pct_solo_neossolos
#   Completo     : lag + bio_1 + bio_12 + bio_15 + dist_rio_km + pct_solo_latossolos
#
# Nota: O filtro ≤200km usa dist_rail_real_{ano_trat}, ou seja, a distância até a
# rede real NO ANO DE TRATAMENTO do outcome em questão. Isso garante consistência
# entre o tratamento e o critério de inclusão na amostra restrita.

cat("SEÇÃO 4: Definindo especificações...\n\n")

especificacoes <- list(
  list(
    nome        = "1_Completa_FE_LagEsp",
    rotulo      = "Completa + FE Estado | Lag Espacial",
    filtro_200  = FALSE,
    excl_pontas = FALSE,
    fe_formula  = "state_abbr",
    controles   = "dist_sintetica_vizinhos",
    ctrl_tipo   = "lag"
  ),
  list(
    nome        = "2_Completa_FE_Clima",
    rotulo      = "Completa + FE Estado | Clima",
    filtro_200  = FALSE,
    excl_pontas = FALSE,
    fe_formula  = "state_abbr",
    controles   = "bio_1 + bio_12 + bio_15",
    ctrl_tipo   = "clima"
  ),
  list(
    nome        = "3_200km_FE_RiosSolo",
    rotulo      = "Dist ≤200km + FE Estado | Rios+Solo",
    filtro_200  = TRUE,
    excl_pontas = FALSE,
    fe_formula  = "state_abbr",
    controles   = "dist_rio_km + densidade_hidro_km_km2 + pct_solo_latossolos + pct_solo_neossolos",
    ctrl_tipo   = "rios_solo"
  ),
  list(
    nome        = "4_200km_SemPontas_FE_Completo",
    rotulo      = "Dist ≤200km + Excl.Pontas + FE Estado | Completo",
    filtro_200  = TRUE,
    excl_pontas = TRUE,
    fe_formula  = "state_abbr",
    controles   = "dist_sintetica_vizinhos + bio_1 + bio_12 + bio_15 + dist_rio_km + pct_solo_latossolos",
    ctrl_tipo   = "completo"
  )
)


# ==============================================================================
# SEÇÃO 5: FUNÇÃO DE ESTIMAÇÃO IV (2SLS via feols)
# ==============================================================================
# Adaptações em relação à versão anterior:
#   - Parâmetro 'transf': usa log(Y) ou Y em nível conforme o outcome
#   - Parâmetro 'nome_escopo': registra o escopo temático nos resultados
#   - Reporta erro descritivo sem interromper o loop

estimar_iv <- function(df, endogena, instrumento, outcome_col,
                       fe_formula, controles, transf,
                       nome_esp, nome_trat, nome_out, nome_escopo,
                       ano_trat) {
  tryCatch({
    df <- df |> dplyr::rename(Y = all_of(outcome_col))

    df <- df |>
      dplyr::filter(
        !is.na(.data[[endogena]]),
        !is.na(.data[[instrumento]]),
        !is.na(Y)
      )

    # Remover zeros apenas para log (log(0) = -Inf)
    if (transf == "log") df <- df |> dplyr::filter(Y > 0)

    n_obs <- nrow(df)
    if (n_obs < 30) stop("Amostra insuficiente (N < 30)")

    lhs        <- if (transf == "log") "log(Y)" else "Y"
    parte_ctrl <- if (is.null(controles) || nchar(trimws(controles)) == 0) "1" else controles

    if (fe_formula == "1") {
      formula_iv <- as.formula(
        sprintf("%s ~ %s | %s ~ %s", lhs, parte_ctrl, endogena, instrumento)
      )
    } else {
      formula_iv <- as.formula(
        sprintf("%s ~ %s | %s | %s ~ %s",
                lhs, parte_ctrl, fe_formula, endogena, instrumento)
      )
    }

    modelo <- feols(formula_iv, data = df, se = "hetero")

    nome_coef <- paste0("fit_", endogena)
    coefs <- coef(modelo)
    ses   <- se(modelo)

    if (!nome_coef %in% names(coefs)) {
      stop(sprintf("Coef '%s' não encontrado. Disponíveis: %s",
                   nome_coef, paste(names(coefs), collapse = ", ")))
    }

    coef_ss <- coefs[nome_coef]
    se_ss   <- ses[nome_coef]
    t_ss    <- coef_ss / se_ss
    p_ss    <- 2 * (1 - pnorm(abs(t_ss)))

    fstat_obj <- fitstat(modelo, "ivf")[[1]]
    f_stat    <- if (is.list(fstat_obj)) fstat_obj$stat else as.numeric(fstat_obj)
    r2_ss     <- tryCatch(r2(modelo, type = "ar2"), error = function(e) NA_real_)

    data.frame(
      escopo        = nome_escopo,
      especificacao = nome_esp,
      tratamento    = nome_trat,
      ano_trat      = ano_trat,
      outcome       = nome_out,
      transf        = transf,
      n_obs         = n_obs,
      coef_ss       = coef_ss,
      se_ss         = se_ss,
      t_stat        = t_ss,
      p_value       = p_ss,
      f_stat        = f_stat,
      r2_ss         = r2_ss,
      erro          = NA_character_,
      stringsAsFactors = FALSE
    )

  }, error = function(e) {
    data.frame(
      escopo=nome_escopo, especificacao=nome_esp, tratamento=nome_trat,
      ano_trat=ano_trat, outcome=nome_out, transf=transf,
      n_obs=NA_integer_, coef_ss=NA_real_, se_ss=NA_real_,
      t_stat=NA_real_, p_value=NA_real_, f_stat=NA_real_, r2_ss=NA_real_,
      erro=e$message, stringsAsFactors=FALSE
    )
  })
}


# ==============================================================================
# SEÇÃO 6: EXECUTAR BATERIA
# ==============================================================================

cat(strrep("=", 80), "\n")
cat("EXECUTANDO BATERIA\n")
cat(strrep("=", 80), "\n\n")

# Colunas auxiliares que precisam estar no df de trabalho (além de outcome + tratamento)
cols_controles <- c(
  "dist_sintetica_vizinhos",           # calculado dinamicamente
  "bio_1", "bio_12", "bio_15",
  "dist_rio_km", "densidade_hidro_km_km2",
  "pct_solo_latossolos", "pct_solo_neossolos",
  "pct_solo_luvissolos", "pct_solo_planossolos"
)

resultados <- data.frame()
contador   <- 0L

for (esp in especificacoes) {

  cat(sprintf("\n%s\n  ESPECIFICAÇÃO: %s\n%s\n",
              strrep("-", 60), esp$rotulo, strrep("-", 60)))

  for (out in outcomes_config) {

    ano_trat <- out$ano_trat

    # Nomes das variáveis de tratamento para este ano
    col_dist  <- paste0("dist_rail_real_",      ano_trat)
    col_dummy <- paste0("dummy_atendida_real_",  ano_trat)
    col_dens  <- paste0("densidade_real_",        ano_trat)

    # Verificar existência das colunas de tratamento
    cols_trat_ok <- all(c(col_dist, col_dummy, col_dens) %in% names(base_mestre))
    if (!cols_trat_ok) {
      cat(sprintf("  ⚠ Colunas de tratamento para %d não encontradas (outcome: %s). Pulando.\n",
                  ano_trat, out$nome))
      next
    }

    # Verificar existência do outcome
    if (!out$coluna %in% names(base_mestre)) {
      cat(sprintf("  ⚠ Coluna '%s' não encontrada. Pulando %s.\n", out$coluna, out$nome))
      next
    }

    # ── Filtrar amostra ────────────────────────────────────────────────────────
    df_base <- base_mestre

    if (esp$filtro_200) {
      # Usa a distância do ANO DE TRATAMENTO como critério de inclusão
      df_base <- df_base |> dplyr::filter(.data[[col_dist]] <= 200)
    }

    if (esp$excl_pontas) {
      df_base <- df_base |> dplyr::filter(!(code_amc %in% codes_pontas_corr))
    }

    if (nrow(df_base) < 30) {
      cat(sprintf("  ⚠ Amostra < 30 após filtros para %s. Pulando.\n", out$nome))
      next
    }

    # ── Calcular lag espacial (recalculado para cada amostra filtrada) ─────────
    # O lag usa dist_rail_sintetica_km (instrumento), que é exógeno e fixo.
    vizinhos_loc <- poly2nb(df_base, queen = TRUE)
    pesos_loc    <- nb2listw(vizinhos_loc, style = "W", zero.policy = TRUE)
    df_base$dist_sintetica_vizinhos <- lag.listw(
      pesos_loc, df_base$dist_rail_sintetica_km, zero.policy = TRUE
    )

    # ── Selecionar colunas necessárias (sem geometria) ─────────────────────────
    cols_necessarias <- c(
      "code_amc", "state_abbr",
      col_dist, col_dummy, col_dens,
      "dist_rail_sintetica_km", "dummy_atendida_sintetica", "densidade_sintetica",
      out$coluna,
      cols_controles
    )
    cols_presentes <- intersect(cols_necessarias, names(df_base))

    df_out <- df_base |>
      sf::st_drop_geometry() |>
      dplyr::select(all_of(cols_presentes))

    # ── Loop sobre tipos de tratamento ─────────────────────────────────────────
    tratamentos_loop <- list(
      list(
        nome        = "distancia",
        endogena    = col_dist,
        instrumento = "dist_rail_sintetica_km",
        rotulo      = sprintf("Dist. ferrovia real (%d)", ano_trat)
      ),
      list(
        nome        = "dummy",
        endogena    = col_dummy,
        instrumento = "dummy_atendida_sintetica",
        rotulo      = sprintf("Dummy atendimento ≤25km (%d)", ano_trat)
      ),
      list(
        nome        = "densidade",
        endogena    = col_dens,
        instrumento = "densidade_sintetica",
        rotulo      = sprintf("Densidade ferrovias (%d)", ano_trat)
      )
    )

    for (trat in tratamentos_loop) {

      contador <- contador + 1L
      cat(sprintf("  [%3d/%d] %-18s | %-12s | %-10s ",
                  contador, n_total, out$nome, trat$nome, esp$ctrl_tipo))

      res <- estimar_iv(
        df          = df_out,
        endogena    = trat$endogena,
        instrumento = trat$instrumento,
        outcome_col = out$coluna,
        fe_formula  = esp$fe_formula,
        controles   = esp$controles,
        transf      = out$transf,
        nome_esp    = esp$rotulo,
        nome_trat   = trat$rotulo,
        nome_out    = out$rotulo,
        nome_escopo = out$escopo,
        ano_trat    = ano_trat
      )

      resultados <- rbind(resultados, res)

      if (is.na(res$coef_ss)) {
        cat(sprintf("⚠ ERRO: %s\n", res$erro))
      } else {
        sig <- dplyr::case_when(
          res$p_value < 0.01 ~ "***",
          res$p_value < 0.05 ~ "**",
          res$p_value < 0.10 ~ "*",
          TRUE               ~ ""
        )
        cat(sprintf("β=%+.4f%s  F=%5.1f  p=%.3f  N=%d\n",
                    res$coef_ss, sig, res$f_stat, res$p_value, res$n_obs))
      }
    }
  }
}


# ==============================================================================
# SEÇÃO 7: DIAGNÓSTICO SUMÁRIO
# ==============================================================================

cat("\n\n", strrep("=", 80), "\n")
cat("DIAGNÓSTICO SUMÁRIO\n")
cat(strrep("=", 80), "\n\n")

n_ok    <- sum(!is.na(resultados$coef_ss))
n_erro  <- sum(is.na(resultados$coef_ss))
n_fraco <- sum(resultados$f_stat < 10, na.rm = TRUE)
n_sig05 <- sum(resultados$p_value < 0.05, na.rm = TRUE)
n_sig10 <- sum(resultados$p_value < 0.10, na.rm = TRUE)

cat(sprintf("Regressões estimadas com sucesso : %d / %d\n", n_ok, nrow(resultados)))
cat(sprintf("Com erro                         : %d\n", n_erro))
cat(sprintf("Instrumento fraco (F < 10)       : %d\n", n_fraco))
cat(sprintf("Significativas p < 0.05          : %d\n", n_sig05))
cat(sprintf("Significativas p < 0.10          : %d\n\n", n_sig10))

cat("F-ESTATÍSTICO MÉDIO POR TIPO DE TRATAMENTO:\n")
resumo_trat <- resultados |>
  dplyr::group_by(tratamento) |>
  dplyr::summarise(
    F_medio  = mean(f_stat,  na.rm = TRUE),
    F_minimo = min(f_stat,   na.rm = TRUE),
    n_sig05  = sum(p_value < 0.05, na.rm = TRUE),
    n_total  = dplyr::n(),
    .groups  = "drop"
  )
print(resumo_trat, n = Inf)

cat("\nCOEFICIENTE MÉDIO POR ESCOPO:\n")
resumo_esc <- resultados |>
  dplyr::group_by(escopo) |>
  dplyr::summarise(
    coef_med = mean(coef_ss, na.rm = TRUE),
    n_sig05  = sum(p_value < 0.05, na.rm = TRUE),
    n_total  = dplyr::n(),
    .groups  = "drop"
  )
print(resumo_esc, n = Inf)

cat("\nF-ESTATÍSTICO MÉDIO POR TIPO DE CONTROLES:\n")
resumo_ctrl <- resultados |>
  dplyr::mutate(ctrl = stringr::str_extract(especificacao, "(?<=\\| ).*$")) |>
  dplyr::group_by(ctrl) |>
  dplyr::summarise(
    F_medio = mean(f_stat, na.rm = TRUE),
    n_sig05 = sum(p_value < 0.05, na.rm = TRUE),
    .groups = "drop"
  )
print(resumo_ctrl, n = Inf)


# ==============================================================================
# SEÇÃO 8: EXPORTAR RESULTADOS
# ==============================================================================

cat("\n\n", strrep("=", 80), "\n")
cat("EXPORTANDO RESULTADOS\n")
cat(strrep("=", 80), "\n\n")

dir.create("03-resultados/csv",    showWarnings = FALSE, recursive = TRUE)
dir.create("03-resultados/tabelas", showWarnings = FALSE, recursive = TRUE)

# CSV completo
arq_csv <- "03-resultados/csv/resultados_bateria9_novos_outcomes.csv"
write_csv(resultados, arq_csv)
cat(sprintf("  ✓ CSV: %s\n", arq_csv))

# Tabela formatada no console
cat("\nTABELA COMPLETA DE RESULTADOS:\n\n")
tabela_fmt <- resultados |>
  dplyr::mutate(
    sig      = dplyr::case_when(
      p_value < 0.01 ~ "***",
      p_value < 0.05 ~ "**",
      p_value < 0.10 ~ "*",
      TRUE           ~ ""
    ),
    coef_fmt = sprintf("%+.4f%s",  coef_ss, sig),
    se_fmt   = sprintf("(%.4f)",   se_ss),
    f_fmt    = sprintf("%.1f",     f_stat),
    p_fmt    = sprintf("%.3f",     p_value)
  ) |>
  dplyr::select(
    Escopo        = escopo,
    Especificacao = especificacao,
    Tratamento    = tratamento,
    `Ano Trat`    = ano_trat,
    Outcome       = outcome,
    Transf        = transf,
    N             = n_obs,
    `β (2S)`      = coef_fmt,
    SE            = se_fmt,
    `F (1S)`      = f_fmt,
    `p-valor`     = p_fmt
  )

print(tabela_fmt, n = Inf)

# Tabela em HTML (requer knitr ou gt)
tryCatch({
  if (requireNamespace("knitr", quietly = TRUE)) {
    html_tabela <- knitr::kable(tabela_fmt, format = "html", escape = FALSE)
    arq_html <- "03-resultados/tabelas/tabela_bateria9_novos_outcomes.html"
    writeLines(as.character(html_tabela), arq_html)
    cat(sprintf("\n  ✓ HTML: %s\n", arq_html))
  }
}, error = function(e) cat("  ℹ Tabela HTML não gerada (knitr não disponível)\n"))

cat("\n", strrep("=", 80), "\n")
cat("✓ BATERIA 9 CONCLUÍDA —", format(Sys.time(), "%d/%m/%Y %H:%M:%S"), "\n")
cat(strrep("=", 80), "\n")
