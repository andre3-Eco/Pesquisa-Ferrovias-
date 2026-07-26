# ==============================================================================
# INFERÊNCIA ESPACIAL ROBUSTA: ERROS DE CONLEY + CLUSTERIZAÇÃO
# Tratamento EXCLUSIVO: 1950
# Outcomes: Multidimensional (PIB 21, População 22, Urbanização 10, IDH 10)
# Referência: Conley (1999), Stock & Yogo (2005)
# ==============================================================================

library(tidyverse)
library(fixest)
library(sf)

if (!exists("data.wd")) {
  data.wd <- normalizePath(file.path(getwd(), "..", ".."))
}
setwd(data.wd)

# ==============================================================================
# 1. CARREGA BASE UNIFICADA E PONTAS
# ==============================================================================
ne_states <- c("MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA")

# Usando a base com os dados recentes (PIB 2021, POP 2022)
base <- read_csv("01-dados/processados/base_completa_integrada_buffer_com_pib_recente.csv", show_col_types = FALSE) |>
  filter(state_abbr %in% ne_states)

painel_pontas <- read_csv(
  "01-dados/processados/painel_amcs_pontas_ano_a_ano.csv",
  show_col_types = FALSE
)
pontas_por_ano <- painel_pontas |> select(code_amc, ano_corte) |> distinct()

# ==============================================================================
# 2. OUTCOMES INTERPOLADOS (Com proteção contra sufixos)
# ==============================================================================
outcomes_interp <- readRDS("01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.rds")

colunas_sobrepostas <- setdiff(intersect(names(base), names(outcomes_interp)), "code_amc")
base <- base |> 
  select(-all_of(colunas_sobrepostas)) |> 
  left_join(outcomes_interp, by = "code_amc")

# ==============================================================================
# 3. COORDENADAS (Obrigatório para Conley HAC)
# ==============================================================================
amcs_geom <- readRDS("01-dados/processados/amcs_geometria.rds")
cents  <- amcs_geom |> sf::st_transform(4326) |> sf::st_centroid()
coords <- sf::st_coordinates(cents)

centroides <- cents |>
  sf::st_drop_geometry() |>
  select(code_amc) |>
  mutate(lon = coords[, 1], lat = coords[, 2])

base <- base |> left_join(centroides, by = "code_amc")

if (!("code_microrregiao" %in% names(base))) {
  base <- base |> mutate(code_microrregiao = paste0("MR_", ntile(lon, 3), "_", ntile(lat, 3)))
}

cat(sprintf("   Base final pronta: %d AMCs × %d colunas\n\n", nrow(base), ncol(base)))

# ==============================================================================
# 4. CONFIGURAÇÕES DA REGRESSÃO
# ==============================================================================
fixed_controls <- paste(
  "bio_1", "bio_12", "bio_15",
  "dist_rio_km", "densidade_hidro_km_km2",
  "pct_solo_latossolos", "pct_solo_neossolos",
  sep = " + "
)

# LÓGICA CRÍTICA: Tratamento fixado em 1950
anos_para_testar <- c(1950) 

# Principais outcomes estruturais de longo prazo
outcomes_para_testar <- c(
  "log(pib_2021)", 
  "log(pop_total_2022)",
  "tx_urbanizacao_2010", 
  "adh_idhm_2010"
)

tipos_se <- c("hetero", "cluster", "conley_50", "conley_100", "conley_200")

# ==============================================================================
# 5. FUNÇÃO DE ESTIMAÇÃO ESPACIAL
# ==============================================================================
rodar_2sls_espacial <- function(df, ano_trat, outcome_var, tipo_se = "hetero", cluster_var = "code_microrregiao") {
  
  endo_var <- paste0("densidade_buffer_real_", ano_trat)
  inst_var <- paste0("densidade_buffer_sintetica_", ano_trat)
  outcome_col <- gsub("log\\(|\\)", "", outcome_var)
  
  if (!all(c(endo_var, inst_var, outcome_col) %in% names(df))) return(NULL)
  
  vals <- df[[outcome_col]]
  if (sum(!is.na(vals) & vals > 0, na.rm = TRUE) < 15) return(NULL)
  
  form_str <- sprintf(
    "%s ~ %s | state_abbr | %s ~ %s",
    outcome_var, fixed_controls, endo_var, inst_var
  )
  
  tryCatch({
    mod <- fixest::feols(as.formula(form_str), data = df, warn = FALSE, notes = FALSE)
    
    mod_sum <- if (tipo_se == "cluster") {
      summary(mod, cluster = as.formula(paste0("~", cluster_var)))
    } else if (grepl("conley_", tipo_se)) {
      cutoff_km <- as.numeric(sub("conley_", "", tipo_se))
      tryCatch(
        summary(mod, vcov = fixest::vcov_conley(mod, lat = "lat", lon = "lon", cutoff = cutoff_km)),
        error = function(e) summary(mod, se = "hetero")
      )
    } else {
      summary(mod, se = "hetero")
    }
    
    ct <- mod_sum$coeftable
    
    nome_coef <- paste0("fit_", endo_var)
    if (!(nome_coef %in% rownames(ct))) {
      if (endo_var %in% rownames(ct)) {
        nome_coef <- endo_var
      } else {
        return(NULL)
      }
    }
    
    f_stat <- tryCatch(as.numeric(fixest::fitstat(mod, "ivf")[[1]]$stat), error = function(e) NA_real_)
    
    tibble(
      ano_trat             = ano_trat,
      outcome_var          = outcome_var,
      variavel_endogena    = endo_var,
      variavel_instrumento = inst_var,
      tipo_inferencia      = tipo_se,
      cutoff_km            = if_else(grepl("conley", tipo_se), as.numeric(sub("conley_", "", tipo_se)), NA_real_),
      coef                 = ct[nome_coef, 1],
      se                   = ct[nome_coef, 2],
      t_stat               = ct[nome_coef, 3],
      p_valor              = ct[nome_coef, 4],
      sig                  = case_when(ct[nome_coef, 4] < 0.01 ~ "***", ct[nome_coef, 4] < 0.05 ~ "**", ct[nome_coef, 4] < 0.10 ~ "*", TRUE ~ ""),
      F_stat_1estagio      = f_stat,
      n_obs                = nrow(df)
    )
    
  }, error = function(e) { NULL })
}

# ==============================================================================
# 6. LOOP PRINCIPAL
# ==============================================================================
resultados_lista <- list()
contador <- 0

for (ano in anos_para_testar) {
  
  endo_verif <- paste0("densidade_buffer_real_", ano)
  inst_verif <- paste0("densidade_buffer_sintetica_", ano)
  
  if (!all(c(endo_verif, inst_verif) %in% names(base))) next
  if (sum(base[[inst_verif]], na.rm = TRUE) == 0) next
  
  cat(sprintf("   → Tratamento: Ano %d\n", ano))
  
  codes_pontas_ano <- pontas_por_ano |> filter(ano_corte == ano) |> pull(code_amc) |> unique()
  
  df_sem_pontas <- base |>
    filter(!code_amc %in% codes_pontas_ano,
           is.finite(.data[[endo_verif]]),
           is.finite(.data[[inst_verif]]),
           !is.na(lat), !is.na(lon), !is.na(state_abbr))
  
  for (oc in outcomes_para_testar) {
    for (t_se in tipos_se) {
      
      res <- rodar_2sls_espacial(df = df_sem_pontas, ano_trat = ano, outcome_var = oc, tipo_se = t_se)
      
      if (!is.null(res)) {
        contador <- contador + 1
        resultados_lista[[contador]] <- res
      }
    }
  }
}

# ==============================================================================
# 7. COMPILA E SALVA
# ==============================================================================
if (length(resultados_lista) == 0) stop("❌ Nenhuma regressão espacial bem-sucedida.")

df_resultados <- bind_rows(resultados_lista) |>
  arrange(outcome_var, ano_trat, factor(tipo_inferencia, levels = tipos_se))

dir.create("03-resultados/csv", showWarnings = FALSE, recursive = TRUE)
write_csv(df_resultados, "03-resultados/csv/resultados_inferencia_espacial_1950.csv")
cat(sprintf("   ✓ %d regressões validadas e salvas.\n", nrow(df_resultados)))

# ==============================================================================
# 8. VISUALIZAÇÃO MULTIDIMENSIONAL (FACETADA)
# ==============================================================================
dir.create("03-resultados/graficos", showWarnings = FALSE, recursive = TRUE)

df_grafico <- df_resultados |>
  mutate(tipo_inferencia = factor(tipo_inferencia, levels = tipos_se))

# Gráfico 1: Erros-Padrão facetados por Outcome
p_se <- ggplot(df_grafico, aes(x = tipo_inferencia, y = se, group = factor(ano_trat), color = factor(ano_trat))) +
  geom_line(linewidth = 0.8, alpha = 0.8) +
  geom_point(size = 3) +
  facet_wrap(~ outcome_var, scales = "free_y", ncol = 2) +
  scale_color_manual(values = c("1950" = "#1b4f72")) +
  labs(
    title = "Inflação dos Erros-Padrão por Tipo de Inferência Espacial (1950)",
    subtitle = "Painel multidimensional de outcomes",
    x = "Método de Clusterização / Conley", y = "Erro-Padrão (SE)", color = "Tratamento"
  ) +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1), strip.text = element_text(face = "bold"))

ggsave("03-resultados/graficos/inferencia_espacial_se_painel_1950.png", p_se, width = 10, height = 7, dpi = 300)

# Gráfico 2: P-Valores facetados por Outcome
p_pv <- ggplot(df_grafico, aes(x = tipo_inferencia, y = p_valor, group = factor(ano_trat), color = factor(ano_trat))) +
  geom_line(linewidth = 0.8, alpha = 0.8) +
  geom_point(size = 3) +
  geom_hline(yintercept = 0.05, linetype = "dashed", color = "red", alpha = 0.6) +
  geom_hline(yintercept = 0.10, linetype = "dotted", color = "orange", alpha = 0.8) +
  facet_wrap(~ outcome_var, ncol = 2) +
  scale_color_manual(values = c("1950" = "#1b4f72")) +
  labs(
    title = "Sensibilidade do P-Valor à Correlação Espacial (1950)",
    x = "Método", y = "P-valor", color = "Tratamento"
  ) +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1), strip.text = element_text(face = "bold"))

ggsave("03-resultados/graficos/inferencia_espacial_pvalor_painel_1950.png", p_pv, width = 10, height = 7, dpi = 300)