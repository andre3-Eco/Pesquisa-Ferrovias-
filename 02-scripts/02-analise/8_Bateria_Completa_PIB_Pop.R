# ==============================================================================
# BATERIA COMPLETA DE TESTES IV — PIB SETORIAL + POPULAÇÃO
# ==============================================================================
# Usa as bases já carregadas na sessão:
#   base_iv_sf          → outcomes de população (2003, 2010)
#   base_iv_sfpibtotal  → PIB total (2003)
#   base_iv_sfpibva     → PIB valor adicionado (2003)
#   base_iv_sfpibag     → PIB agropecuária (2003)
#   base_iv_sfpibin     → PIB indústria (2003)
#
# Tratamentos: distância, dummy, densidade (ref. 2003)
# Instrumento: rede sintética LCP
# Especificações: com/sem FE de estado, excluindo pontas, amostra restrita
#
# NOTA SOBRE FE DE AMC:
#   Em dados cross-section (uma obs. por AMC), efeito fixo de AMC é colinear
#   com qualquer variável de tratamento definida no nível da AMC — absorveria
#   toda a variação e tornaria o modelo inestimável. O controle adequado para
#   heterogeneidade regional em cross-section é o FE de estado (state_abbr).
#   FE de AMC faz sentido apenas em painel com tratamento variante no tempo.
# ==============================================================================

library(sf)
library(dplyr)
library(spdep)
library(fixest)
library(tidyr)

if (!exists("data.wd")) data.wd <- getwd()
sf_use_s2(FALSE)

cat("\n", strrep("=", 80), "\n")
cat("BATERIA IV — PIB SETORIAL + POPULAÇÃO\n")
cat("Data:", format(Sys.time(), "%d/%m/%Y %H:%M:%S"), "\n")
cat(strrep("=", 80), "\n\n")

# ==============================================================================
# SEÇÃO 1: VERIFICAR BASES NA SESSÃO
# ==============================================================================

bases_necessarias <- c(
  "base_iv_sf", "base_iv_sfpibtotal", "base_iv_sfpibva",
  "base_iv_sfpibag", "base_iv_sfpibin", "codes_pontas"
)

for (b in bases_necessarias) {
  if (!exists(b)) stop(sprintf("Objeto '%s' não encontrado na sessão.", b))
}

cat("✓ Todas as bases encontradas na sessão\n")
cat(sprintf("  base_iv_sf:         %d AMCs\n", nrow(base_iv_sf)))
cat(sprintf("  base_iv_sfpibtotal: %d AMCs\n", nrow(base_iv_sfpibtotal)))
cat(sprintf("  base_iv_sfpibva:    %d AMCs\n", nrow(base_iv_sfpibva)))
cat(sprintf("  base_iv_sfpibag:    %d AMCs\n", nrow(base_iv_sfpibag)))
cat(sprintf("  base_iv_sfpibin:    %d AMCs\n", nrow(base_iv_sfpibin)))
cat(sprintf("  AMCs nas pontas:    %d\n\n", length(codes_pontas)))

# ==============================================================================
# SEÇÃO 2: CONFIGURAÇÃO DE OUTCOMES, TRATAMENTOS E ESPECIFICAÇÕES
# ==============================================================================

# Mapeamento: nome do outcome → (base, coluna, rótulo)
outcomes <- list(
  list(nome = "pop_2003",      base = "base_iv_sf",         coluna = "2003",  rotulo = "População (2003)"),
  list(nome = "pop_2010",      base = "base_iv_sf",         coluna = "2010",  rotulo = "População (2010)"),
  list(nome = "pibtotal_2003", base = "base_iv_sfpibtotal", coluna = "2003",  rotulo = "PIB Total (2003)"),
  list(nome = "pibva_2003",    base = "base_iv_sfpibva",    coluna = "2003",  rotulo = "PIB Valor Adicionado (2003)"),
  list(nome = "pibag_2003",    base = "base_iv_sfpibag",    coluna = "2003",  rotulo = "PIB Agropecuária (2003)"),
  list(nome = "pibin_2003",    base = "base_iv_sfpibin",    coluna = "2003",  rotulo = "PIB Indústria (2003)")
)

# Tipos de tratamento
tratamentos <- list(
  list(
    nome        = "distancia",
    endogena    = "dist_rail_real_2003",
    instrumento = "dist_rail_sintetica_km",
    rotulo      = "Distância até ferrovia (km)"
  ),
  list(
    nome        = "dummy",
    endogena    = "dummy_atendida_real_2003",
    instrumento = "dummy_atendida_sintetica",
    rotulo      = "Dummy atendimento (≤25km)"
  ),
  list(
    nome        = "densidade",
    endogena    = "densidade_real_2003",
    instrumento = "densidade_sintetica",
    rotulo      = "Densidade de ferrovias (km/1000km²)"
  )
)

# Especificações de amostra e FE
# (FE de AMC não é aplicável em cross-section — ver nota no cabeçalho)
especificacoes <- list(
  list(
    nome       = "1_Completa_semFE",
    rotulo     = "Amostra completa, sem FE",
    filtro     = NULL,
    fe_formula = "1",             # Intercepto apenas
    controles  = "dist_sintetica_vizinhos"
  ),
  list(
    nome       = "2_Completa_FE_Estado",
    rotulo     = "Amostra completa + FE Estado",
    filtro     = NULL,
    fe_formula = "state_abbr",
    controles  = "dist_sintetica_vizinhos"
  ),
  list(
    nome       = "3_Completa_FE_Estado_semplag",
    rotulo     = "Amostra completa + FE Estado (sem lag espacial)",
    filtro     = NULL,
    fe_formula = "state_abbr",
    controles  = NULL             # Sem lag espacial como controle
  ),
  list(
    nome       = "4_200km_FE_Estado",
    rotulo     = "Dist ≤200km + FE Estado",
    filtro     = "dist_rail_real_2003 <= 200",
    fe_formula = "state_abbr",
    controles  = "dist_sintetica_vizinhos"
  ),
  list(
    nome       = "5_200km_semPontas_FE_Estado",
    rotulo     = "Dist ≤200km + Excl. pontas + FE Estado",
    filtro     = "dist_rail_real_2003 <= 200 & !(code_amc %in% codes_pontas)",
    fe_formula = "state_abbr",
    controles  = "dist_sintetica_vizinhos"
  )
)

n_total <- length(especificacoes) * length(tratamentos) * length(outcomes)
cat(sprintf("Configuração:\n"))
cat(sprintf("  %d especificações × %d tratamentos × %d outcomes = %d regressões\n\n",
            length(especificacoes), length(tratamentos), length(outcomes), n_total))

# ==============================================================================
# SEÇÃO 3: FUNÇÃO PRINCIPAL DE ESTIMAÇÃO IV
# ==============================================================================

estimar_iv <- function(df, endogena, instrumento, outcome_col,
                       fe_formula, controles,
                       nome_esp, nome_trat, nome_out) {
  tryCatch({
    # Renomear outcome para nome fixo (evita problemas com colunas "2003", "2010")
    df <- df |> dplyr::rename(Y = all_of(outcome_col))

    # Remover obs. com Y <= 0 (log não definido) ou NA nas variáveis chave
    df <- df |>
      dplyr::filter(
        !is.na(.data[[endogena]]),
        !is.na(.data[[instrumento]]),
        !is.na(Y),
        Y > 0
      )

    n_obs <- nrow(df)
    if (n_obs < 30) stop("Amostra insuficiente (N < 30)")

    # Construir fórmula feols:
    # Com FE:    log(Y) ~ controles | FE | endogena ~ instrumento
    # Sem FE:    log(Y) ~ controles | endogena ~ instrumento   (sem | FE |)
    parte_controles <- if (is.null(controles)) "1" else controles
    if (fe_formula == "1") {
      # Sem FE: fórmula de 2 partes
      formula_iv <- as.formula(
        sprintf("log(Y) ~ %s | %s ~ %s", parte_controles, endogena, instrumento)
      )
    } else {
      # Com FE: fórmula de 3 partes
      formula_iv <- as.formula(
        sprintf("log(Y) ~ %s | %s | %s ~ %s",
                parte_controles, fe_formula, endogena, instrumento)
      )
    }

    # Estimar 2SLS via feols (SE robustos heterocedásticos)
    modelo <- feols(formula_iv, data = df, se = "hetero")

    # feols nomeia a variável instrumentada como "fit_VARNAME" nos coefs
    nome_coef <- paste0("fit_", endogena)
    coefs     <- coef(modelo)
    ses       <- se(modelo)

    if (!nome_coef %in% names(coefs)) {
      stop(sprintf("Coeficiente '%s' não encontrado. Nomes disponíveis: %s",
                   nome_coef, paste(names(coefs), collapse = ", ")))
    }

    coef_ss <- coefs[nome_coef]
    se_ss   <- ses[nome_coef]
    t_ss    <- coef_ss / se_ss
    p_ss    <- 2 * (1 - pnorm(abs(t_ss)))

    # F-estatístico do primeiro estágio (força do instrumento)
    fstat_obj <- fitstat(modelo, "ivf")[[1]]
    f_stat    <- if (is.list(fstat_obj)) fstat_obj$stat else as.numeric(fstat_obj)

    # R² ajustado do segundo estágio
    r2_ss <- tryCatch(r2(modelo, type = "ar2"), error = function(e) NA_real_)

    data.frame(
      especificacao = nome_esp,
      tratamento    = nome_trat,
      outcome       = nome_out,
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
      especificacao = nome_esp,
      tratamento    = nome_trat,
      outcome       = nome_out,
      n_obs         = NA_integer_,
      coef_ss       = NA_real_,
      se_ss         = NA_real_,
      t_stat        = NA_real_,
      p_value       = NA_real_,
      f_stat        = NA_real_,
      r2_ss         = NA_real_,
      erro          = e$message,
      stringsAsFactors = FALSE
    )
  })
}

# ==============================================================================
# SEÇÃO 4: EXECUTAR BATERIA DE TESTES
# ==============================================================================

cat(strrep("=", 80), "\n")
cat("EXECUTANDO BATERIA\n")
cat(strrep("=", 80), "\n\n")

resultados <- data.frame()
contador   <- 0

for (esp in especificacoes) {

  cat(sprintf("\n%s\n  ESPECIFICAÇÃO: %s\n%s\n",
              strrep("-", 60), esp$rotulo, strrep("-", 60)))

  # --- Filtrar a base principal (tratamentos + instrumentos + geometria) ---
  base_principal <- base_iv_sf
  if (!is.null(esp$filtro)) {
    base_principal <- base_principal |>
      dplyr::filter(eval(parse(text = esp$filtro)))
  }
  cat(sprintf("  N após filtro: %d AMCs\n", nrow(base_principal)))

  # --- Calcular lag espacial (uma vez por especificação) ---
  # O lag usa a rede sintética e é recalculado para a amostra filtrada
  vizinhos_esp <- poly2nb(base_principal, queen = TRUE)
  pesos_esp    <- nb2listw(vizinhos_esp, style = "W", zero.policy = TRUE)
  base_principal$dist_sintetica_vizinhos <- lag.listw(
    pesos_esp, base_principal$dist_rail_sintetica_km, zero.policy = TRUE
  )
  cat("  ✓ Lag espacial calculado\n")

  # Colunas de tratamento/instrumento/controle a transferir para outras bases
  cols_transferir <- c("code_amc", "dist_rail_real_2003", "dummy_atendida_real_2003",
                       "densidade_real_2003", "dist_rail_sintetica_km",
                       "dummy_atendida_sintetica", "densidade_sintetica",
                       "dist_sintetica_vizinhos", "state_abbr", "code_amc")
  cols_transferir <- unique(intersect(cols_transferir, names(base_principal)))

  # Tabela de join para bases PIB (sem geometria)
  join_tbl <- base_principal |>
    sf::st_drop_geometry() |>
    dplyr::select(all_of(cols_transferir))

  # --- Loop sobre outcomes ---
  for (out in outcomes) {

    # Selecionar a base correta para este outcome
    base_out <- get(out$base)

    # Filtrar base_out para manter apenas AMCs presentes em base_principal
    # e juntar variáveis de tratamento/instrumento
    if (out$base == "base_iv_sf") {
      # Mesma base — já tem tratamento; só precisamos filtrar
      df_out <- base_principal
    } else {
      # Base PIB — já contém colunas de tratamento (vieram do base_completa).
      # Selecionar apenas code_amc + outcome para evitar conflito de colunas
      # no join; depois adicionar tratamento/instrumento/lag de join_tbl.
      df_out <- base_out |>
        sf::st_drop_geometry() |>
        dplyr::select(code_amc, all_of(out$coluna)) |>
        dplyr::inner_join(join_tbl, by = "code_amc")
    }

    # --- Loop sobre tratamentos ---
    for (trat in tratamentos) {

      contador <- contador + 1
      cat(sprintf("  [%d/%d] %-20s × %-20s ",
                  contador, n_total, out$nome, trat$nome))

      res <- estimar_iv(
        df          = df_out,
        endogena    = trat$endogena,
        instrumento = trat$instrumento,
        outcome_col = out$coluna,
        fe_formula  = esp$fe_formula,
        controles   = esp$controles,
        nome_esp    = esp$rotulo,
        nome_trat   = trat$rotulo,
        nome_out    = out$rotulo
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
# SEÇÃO 5: DIAGNÓSTICO RÁPIDO
# ==============================================================================

cat("\n\n", strrep("=", 80), "\n")
cat("DIAGNÓSTICO\n")
cat(strrep("=", 80), "\n\n")

n_ok    <- sum(!is.na(resultados$coef_ss))
n_erro  <- sum(is.na(resultados$coef_ss))
n_fraco <- sum(resultados$f_stat < 10, na.rm = TRUE)
n_sig05 <- sum(resultados$p_value < 0.05, na.rm = TRUE)
n_sig10 <- sum(resultados$p_value < 0.10, na.rm = TRUE)

cat(sprintf("Total de regressões:        %d\n", nrow(resultados)))
cat(sprintf("Estimadas com sucesso:      %d\n", n_ok))
cat(sprintf("Com erro:                   %d\n", n_erro))
cat(sprintf("Instrumento fraco (F < 10): %d\n", n_fraco))
cat(sprintf("Significativas (p < 0.05):  %d\n", n_sig05))
cat(sprintf("Significativas (p < 0.10):  %d\n", n_sig10))

# Resumo por tipo de tratamento
cat("\nF-ESTATÍSTICO MÉDIO POR TRATAMENTO:\n")
resumo_trat <- resultados |>
  dplyr::group_by(tratamento) |>
  dplyr::summarise(
    F_medio   = mean(f_stat, na.rm = TRUE),
    F_minimo  = min(f_stat,  na.rm = TRUE),
    coef_med  = mean(coef_ss, na.rm = TRUE),
    n_sig05   = sum(p_value < 0.05, na.rm = TRUE),
    .groups   = "drop"
  )
print(resumo_trat, n = Inf)

# Resumo por outcome
cat("\nCOEFICIENTE MÉDIO POR OUTCOME:\n")
resumo_out <- resultados |>
  dplyr::group_by(outcome) |>
  dplyr::summarise(
    coef_med = mean(coef_ss, na.rm = TRUE),
    n_sig05  = sum(p_value < 0.05, na.rm = TRUE),
    n_testes = dplyr::n(),
    .groups  = "drop"
  )
print(resumo_out, n = Inf)

# ==============================================================================
# SEÇÃO 6: EXPORTAR RESULTADOS
# ==============================================================================

arquivo_csv <- file.path(data.wd, "resultados_bateria_iv_pib_pop.csv")
write.csv(resultados, arquivo_csv, row.names = FALSE)
cat(sprintf("\n✓ Resultados exportados: %s\n", arquivo_csv))

# Tabela formatada no console
cat("\n\nTABELA COMPLETA DE RESULTADOS:\n")
tabela <- resultados |>
  dplyr::mutate(
    sig = dplyr::case_when(
      p_value < 0.01 ~ "***",
      p_value < 0.05 ~ "**",
      p_value < 0.10 ~ "*",
      TRUE           ~ ""
    ),
    coef_fmt = sprintf("%+.4f%s", coef_ss, sig),
    se_fmt   = sprintf("(%.4f)",  se_ss),
    f_fmt    = sprintf("%.1f",    f_stat),
    p_fmt    = sprintf("%.3f",    p_value)
  ) |>
  dplyr::select(
    Especificação = especificacao,
    Tratamento    = tratamento,
    Outcome       = outcome,
    N             = n_obs,
    `β (2S)`      = coef_fmt,
    `SE`          = se_fmt,
    `F (1S)`      = f_fmt,
    `p-valor`     = p_fmt
  )

print(tabela, n = Inf)

cat("\n", strrep("=", 80), "\n")
cat("✓ BATERIA CONCLUÍDA — ", format(Sys.time(), "%d/%m/%Y %H:%M:%S"), "\n")
cat(strrep("=", 80), "\n")
