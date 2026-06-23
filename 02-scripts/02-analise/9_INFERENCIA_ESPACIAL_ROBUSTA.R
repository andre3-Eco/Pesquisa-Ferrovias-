# ==============================================================================
# INFERÊNCIA ESPACIAL ROBUSTA: ERROS DE CONLEY + CLUSTERIZAÇÃO
# Instrumento: densidade_buffer_sintetica_YYYY → densidade_buffer_real_YYYY
# Outcomes: PIB (persistência)
# ==============================================================================
# Referência: Conley (1999), Stock & Yogo (2005)
# Pacote: fixest (feols + conley())
# ==============================================================================

library(dplyr)
library(tidyverse)
library(fixest)
library(sf)
library(readr)

if (!exists("data.wd")) {
  data.wd <- normalizePath(file.path(getwd(), "..", ".."))
}
setwd(data.wd)

cat("========================================================================\n")
cat("  INFERÊNCIA ESPACIAL ROBUSTA (CONLEY + CLUSTER) — SEM PONTAS\n")
cat("========================================================================\n\n")

# ==============================================================================
# 1. CARREGA BASES
# ==============================================================================
cat("1. Carregando bases de dados...\n")

ne_states <- c("MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA")

base_main <- read_csv(
  "01-dados/processados/base_completa_integrada.csv",
  show_col_types = FALSE
)

base_densidade <- read_csv(
  "01-dados/processados/base_densidade_buffer_unificada.csv",
  show_col_types = FALSE
)

base <- base_main |>
  filter(state_abbr %in% ne_states) |>
  select(-starts_with("densidade_real_"), -starts_with("densidade_sintetica")) |>
  left_join(base_densidade, by = "code_amc")

cat(sprintf("   AMCs Nordeste: %d\n", nrow(base)))

# ==============================================================================
# 2. PONTAS (exclusão por ano)
# ==============================================================================
cat("2. Carregando painel de pontas...\n")

painel_pontas <- read_csv(
  "01-dados/processados/painel_amcs_pontas_ano_a_ano.csv",
  show_col_types = FALSE
)

pontas_por_ano <- painel_pontas |>
  select(code_amc, ano_corte) |>
  distinct()

# ==============================================================================
# 3. CONTROLES AMBIENTAIS
# ==============================================================================
cat("3. Carregando controles...\n")

ctrl_clima <- readRDS("01-dados/processados/controles_clima_amcs_nordeste.rds")
ctrl_rios  <- readRDS("01-dados/processados/controles_rios_amcs_nordeste.rds")
ctrl_solo  <- readRDS("01-dados/processados/controles_solo_amcs_nordeste.rds")

base <- base |>
  left_join(ctrl_clima |> select(code_amc, bio_1, bio_12, bio_15),              by = "code_amc") |>
  left_join(ctrl_rios  |> select(code_amc, dist_rio_km, densidade_hidro_km_km2), by = "code_amc") |>
  left_join(ctrl_solo  |> select(code_amc, pct_solo_latossolos, pct_solo_neossolos), by = "code_amc")

# ==============================================================================
# 4. OUTCOMES INTERPOLADOS
# ==============================================================================
cat("4. Carregando outcomes...\n")

outcomes_interp <- readRDS(
  "01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.rds"
)

base <- base |>
  left_join(
    outcomes_interp |> select(
      code_amc,
      pib_1920, pib_1939, pib_1949, pib_1959,
      pib_1970, pib_1975, pib_1980, pib_1985,
      pib_1996, pib_1999, pib_2003, pib_2010,
      pop_total_1940, pop_total_1950, pop_total_1960,
      pop_total_1970, pop_total_1980, pop_total_1991,
      pop_total_1996, pop_total_2000, pop_total_2010
    ),
    by = "code_amc"
  )

cat(sprintf("   Base final: %d AMCs × %d colunas\n\n", nrow(base), ncol(base)))

# ==============================================================================
# 5. COORDENADAS (lat/lon em WGS84 — necessário para Conley)
# ==============================================================================
cat("5. Extraindo coordenadas para Conley HAC...\n")

amcs_geom <- readRDS("01-dados/processados/amcs_geometria.rds")

cents  <- amcs_geom |> sf::st_transform(4326) |> sf::st_centroid()
coords <- sf::st_coordinates(cents)

centroides <- cents |>
  sf::st_drop_geometry() |>
  select(code_amc) |>
  mutate(lon = coords[, 1], lat = coords[, 2])

base <- base |>
  left_join(centroides, by = "code_amc")

# Microrregião proxy para clusterização (se não existir)
if (!("code_microrregiao" %in% names(base))) {
  base <- base |>
    mutate(code_microrregiao = paste0("MR_", ntile(lon, 3), "_", ntile(lat, 3)))
}

cat(sprintf("   Coordenadas adicionadas. Estados: %d | Microrregiões: %d\n\n",
            n_distinct(base$state_abbr), n_distinct(base$code_microrregiao)))

# ==============================================================================
# 6. CONFIGURAÇÃO
# ==============================================================================

fixed_controls <- paste(
  "bio_1", "bio_12", "bio_15",
  "dist_rio_km", "densidade_hidro_km_km2",
  "pct_solo_latossolos", "pct_solo_neossolos",
  sep = " + "
)

# Anos disponíveis para o tratamento
years <- names(base) |>
  grep("^densidade_buffer_real_[0-9]+$", x = _, value = TRUE) |>
  sub("densidade_buffer_real_", "", x = _) |>
  as.integer() |>
  sort()

cat(sprintf("Anos disponíveis no tratamento: %d–%d\n", min(years), max(years)))
cat(sprintf("⚠  Nota: não existe 'densidade_buffer_real_2010' na base — ano 2010\n"))
cat(sprintf("    será ignorado automaticamente.\n\n"))

# ==============================================================================
# 7. FUNÇÃO: rodar_2sls_espacial
# ==============================================================================
# Assinatura compatível com o loop do usuário:
#   rodar_2sls_espacial(df, ano_trat, outcome_var, tipo_se)
# ==============================================================================

rodar_2sls_espacial <- function(df,
                                 ano_trat,
                                 outcome_var,
                                 tipo_se       = "hetero",
                                 cluster_var   = "code_microrregiao") {

  endo_var <- paste0("densidade_buffer_real_",      ano_trat)
  inst_var <- paste0("densidade_buffer_sintetica_", ano_trat)

  # Verificações de colunas
  if (!endo_var %in% names(df)) {
    cat(sprintf("    ⚠ [%s] Tratamento '%s' não existe\n", tipo_se, endo_var))
    return(NULL)
  }
  if (!inst_var %in% names(df)) {
    cat(sprintf("    ⚠ [%s] Instrumento '%s' não existe\n", tipo_se, inst_var))
    return(NULL)
  }

  outcome_col <- gsub("log\\(|\\)", "", outcome_var)
  if (!outcome_col %in% names(df)) {
    cat(sprintf("    ⚠ [%s] Outcome '%s' não existe\n", tipo_se, outcome_col))
    return(NULL)
  }

  vals <- df[[outcome_col]]
  if (sum(!is.na(vals) & vals > 0, na.rm = TRUE) < 10) {
    cat(sprintf("    ⚠ [%s] Poucos obs. válidas em '%s'\n", tipo_se, outcome_col))
    return(NULL)
  }

  # Verifica disponibilidade de lat/lon para Conley
  if (grepl("conley", tipo_se) && !all(c("lat", "lon") %in% names(df))) {
    cat(sprintf("    ⚠ [%s] lat/lon ausentes — usando hetero\n", tipo_se))
    tipo_se <- "hetero"
  }

  # Verifica cluster var
  if (tipo_se == "cluster" && !cluster_var %in% names(df)) {
    cat(sprintf("    ⚠ [%s] '%s' ausente — usando hetero\n", tipo_se, cluster_var))
    tipo_se <- "hetero"
  }

  # Fórmula IV/2SLS (fixest): Y ~ controles | FE | endógena ~ instrumento
  form_str <- sprintf(
    "%s ~ %s | state_abbr | %s ~ %s",
    outcome_var, fixed_controls, endo_var, inst_var
  )

  tryCatch({
    # 1. Roda o modelo
    mod <- fixest::feols(as.formula(form_str), data = df, warn = FALSE, notes = FALSE)

    # 2. Reaplicar vcov correto via summary()
    mod_sum <- if (tipo_se == "cluster") {
      summary(mod, cluster = as.formula(paste0("~", cluster_var)))

    } else if (grepl("conley_", tipo_se)) {
      cutoff_km <- as.numeric(sub("conley_", "", tipo_se))
      # vcov_conley() recebe o modelo + lat/lon como strings + cutoff em KM
      tryCatch(
        summary(mod, vcov = fixest::vcov_conley(mod, lat = "lat", lon = "lon", cutoff = cutoff_km)),
        error = function(e) {
          cat(sprintf("    ⚠ Conley falhou (%s) — usando hetero\n", e$message))
          summary(mod, se = "hetero")
        }
      )

    } else {
      summary(mod, se = "hetero")
    }

    # 3. Extrai coeficiente do 2º estágio
    ct <- mod_sum$coeftable

    # fixest prefixa a endógena instrumentalizada com "fit_"
    nome_endo <- paste0("fit_", endo_var)

    if (!nome_endo %in% rownames(ct)) {
      cat(sprintf("    ⚠ [%s] '%s' não encontrado em coeftable\n", tipo_se, nome_endo))
      return(NULL)
    }

    coef_val <- ct[nome_endo, 1]
    se_val   <- ct[nome_endo, 2]
    t_val    <- ct[nome_endo, 3]
    p_val    <- ct[nome_endo, 4]

    # 4. F-stat do 1º estágio
    f_stat <- tryCatch(
      as.numeric(fixest::fitstat(mod, "ivf")[[1]]$stat),
      error = function(e) NA_real_
    )

    tibble(
      ano_trat             = ano_trat,
      outcome_var          = outcome_var,
      variavel_endogena    = endo_var,
      variavel_instrumento = inst_var,
      tipo_inferencia      = tipo_se,
      cutoff_km            = if_else(grepl("conley", tipo_se),
                                     as.numeric(sub("conley_", "", tipo_se)),
                                     NA_real_),
      coef                 = coef_val,
      se                   = se_val,
      t_stat               = t_val,
      p_valor              = p_val,
      sig                  = case_when(
        p_val < 0.01 ~ "***",
        p_val < 0.05 ~ "**",
        p_val < 0.10 ~ "*",
        TRUE         ~ ""
      ),
      F_stat_1estagio      = f_stat,
      instrumento_forte    = case_when(
        f_stat > 10 ~ "SIM",
        f_stat > 5  ~ "MODERADO",
        TRUE        ~ "NÃO"
      ),
      n_obs                = nrow(df)
    )

  }, error = function(e) {
    cat(sprintf("    ✗ [%s] Erro: %s\n", tipo_se, substr(e$message, 1, 60)))
    NULL
  })
}

# ==============================================================================
# 8. LOOP PRINCIPAL
# ==============================================================================
cat("6. Rodando bateria de regressões...\n\n")

# Configuração do teste
# NOTA: 2010 é pulado automaticamente pois não existe densidade_buffer_real_2010
anos_para_testar <- c(1996, 2003, 2010)
outcomes         <- c("log(pib_2010)")
tipos_se         <- c("hetero", "cluster", "conley_50", "conley_100", "conley_200")

resultados_lista <- list()
contador         <- 0

for (ano in anos_para_testar) {

  endo_verif <- paste0("densidade_buffer_real_", ano)

  if (!endo_verif %in% names(base)) {
    cat(sprintf("   ⚠ Pulando ano %d: '%s' não encontrado.\n", ano, endo_verif))
    next
  }

  # Instrumento com variação suficiente
  inst_verif <- paste0("densidade_buffer_sintetica_", ano)
  if (sum(base[[inst_verif]], na.rm = TRUE) == 0) {
    cat(sprintf("   ⚠ Pulando ano %d: instrumento sem variação.\n", ano))
    next
  }

  cat(sprintf("\n   → Processando Tratamento: Ano %d\n", ano))
  cat("     ──────────────────────────────────────────────────\n")

  # Exclui pontas do ano corrente
  codes_pontas_ano <- pontas_por_ano |>
    filter(ano_corte == ano) |>
    pull(code_amc) |>
    unique()

  df_sem_pontas <- base |>
    filter(
      !code_amc %in% codes_pontas_ano,
      is.finite(.data[[endo_verif]]),
      is.finite(.data[[inst_verif]]),
      !is.na(state_abbr),
      !is.na(lat), !is.na(lon)
    )

  cat(sprintf("     n = %d (excluídas %d pontas)\n",
              nrow(df_sem_pontas), length(codes_pontas_ano)))

  for (oc in outcomes) {
    for (t_se in tipos_se) {

      res <- rodar_2sls_espacial(
        df         = df_sem_pontas,
        ano_trat   = ano,
        outcome_var = oc,
        tipo_se    = t_se
      )

      if (!is.null(res)) {
        contador <- contador + 1
        resultados_lista[[contador]] <- res
        cat(sprintf("     [%-10s] ✓ coef = %+.4f | p-valor = %.3f %s | F = %.1f\n",
                    t_se, res$coef, res$p_valor, res$sig, res$F_stat_1estagio))
      }
    }
  }
}

# ==============================================================================
# 9. COMPILA E SALVA
# ==============================================================================
cat("\n7. Compilando resultados...\n")

if (length(resultados_lista) == 0) stop("Nenhuma regressão bem-sucedida.")

df_resultados <- bind_rows(resultados_lista)
cat(sprintf("   Total de regressões: %d\n\n", nrow(df_resultados)))

# Tabela resumo
df_resultados |>
  select(ano_trat, tipo_inferencia, coef, se, p_valor, sig, F_stat_1estagio, n_obs) |>
  print(n = Inf)

dir.create("03-resultados/csv", showWarnings = FALSE, recursive = TRUE)

write_csv(
  df_resultados,
  "03-resultados/csv/resultados_inferencia_espacial_robusta.csv"
)

saveRDS(
  df_resultados,
  "03-resultados/csv/resultados_inferencia_espacial_robusta.rds"
)

cat("\n✅ Salvo em: 03-resultados/csv/resultados_inferencia_espacial_robusta.csv\n")

# ==============================================================================
# 10. VISUALIZAÇÃO: Inflação de Erros-Padrão
# ==============================================================================
cat("\n8. Gerando visualizações...\n")

dir.create("03-resultados/graficos", showWarnings = FALSE, recursive = TRUE)

# Gráfico: SE por tipo de inferência
p_se <- df_resultados |>
  mutate(tipo_inferencia = factor(tipo_inferencia,
    levels = c("hetero", "cluster", "conley_50", "conley_100", "conley_200"))) |>
  ggplot(aes(x = tipo_inferencia, y = se, group = factor(ano_trat), color = factor(ano_trat))) +
  geom_line(linewidth = 0.8, alpha = 0.8) +
  geom_point(size = 3) +
  labs(
    title    = "Inflação dos Erros-Padrão por Tipo de Inferência Espacial",
    subtitle = "Instrumento: densidade_buffer_sintetica | Outcome: log(PIB 2010)",
    x        = "Tipo de Inferência",
    y        = "Erro-Padrão",
    color    = "Ano do Tratamento"
  ) +
  theme_minimal(base_size = 12) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))

ggsave("03-resultados/graficos/inferencia_espacial_se.png",
       p_se, width = 9, height = 5, dpi = 300)

# Gráfico: P-valor por tipo de inferência
p_pv <- df_resultados |>
  mutate(tipo_inferencia = factor(tipo_inferencia,
    levels = c("hetero", "cluster", "conley_50", "conley_100", "conley_200"))) |>
  ggplot(aes(x = tipo_inferencia, y = p_valor, group = factor(ano_trat), color = factor(ano_trat))) +
  geom_line(linewidth = 0.8, alpha = 0.8) +
  geom_point(size = 3) +
  geom_hline(yintercept = 0.05, linetype = "dashed", color = "red",    alpha = 0.6) +
  geom_hline(yintercept = 0.10, linetype = "dashed", color = "orange", alpha = 0.6) +
  labs(
    title    = "P-valor por Tipo de Inferência Espacial",
    subtitle = "Linha vermelha: p=0.05 | Linha laranja: p=0.10",
    x        = "Tipo de Inferência",
    y        = "P-valor",
    color    = "Ano do Tratamento"
  ) +
  theme_minimal(base_size = 12) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))

ggsave("03-resultados/graficos/inferencia_espacial_pvalor.png",
       p_pv, width = 9, height = 5, dpi = 300)

cat("   ✓ Gráficos salvos em 03-resultados/graficos/\n")

# ==============================================================================
# 11. DIAGNÓSTICO FINAL
# ==============================================================================
cat("\n========================================================================\n")
cat("  DIAGNÓSTICO: INFLAÇÃO DOS ERROS-PADRÃO\n")
cat("========================================================================\n\n")

df_resultados |>
  group_by(ano_trat, tipo_inferencia) |>
  summarise(se_medio = mean(se, na.rm = TRUE), .groups = "drop") |>
  tidyr::pivot_wider(names_from = tipo_inferencia, values_from = se_medio) |>
  mutate(
    inflacao_conley_100_pct = (conley_100 - hetero) / hetero * 100,
    inflacao_cluster_pct    = (cluster   - hetero) / hetero * 100
  ) |>
  select(ano_trat, hetero, cluster, conley_100, inflacao_conley_100_pct, inflacao_cluster_pct) |>
  print()

cat("\nRECOMENDAÇÕES:\n")
cat("  • Inflação > 30% → correlação espacial forte → USE Conley 100km como primário\n")
cat("  • Inflação 10–30% → moderada → inclua Conley como robustez\n")
cat("  • Inflação < 10% → baixa → hetero OK, mas Conley melhora credibilidade\n")

# Exporta para exploração interativa
assign("df_resultados_espacial", df_resultados, envir = globalenv())

cat("\n✅ Script finalizado com sucesso!\n")
cat("   Objeto 'df_resultados_espacial' disponível na sessão\n\n")
