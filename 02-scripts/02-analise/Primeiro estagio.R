library(fixest)
library(dplyr)
library(modelsummary)

# ==============================================================================
# 0. Tratar os dados
# ==============================================================================

# 1. Fazemos a união (Join) de todas as suas bases
# base_iv_sf é o objeto espacial original + Outcomes + Controles
base_mestre <- base_iv_sf |>
  inner_join(outcomes_wide, by = "code_amc") |>
  left_join(ctrl_clima |> select(code_amc, bio_1, bio_12, bio_15), by = "code_amc") |>
  left_join(ctrl_rios |> select(code_amc, dist_rio_km, densidade_hidro_km_km2), by = "code_amc") |>
  left_join(ctrl_solo |> select(code_amc, pct_solo_latossolos, pct_solo_neossolos), by = "code_amc")

# 2. Aplicamos os filtros de exclusão
# (Lembrando de excluir as pontas que definimos na lista_amcs_pontas)
codes_pontas <- lista_amcs_pontas$amcs_codigo |>
  stringr::str_split(" e ") |> unlist() |> as.numeric() |> na.omit() |> unique()

df_limpo <- base_mestre |>
  filter(!is.na(dist_rail_real_1970)) |>    # Remove missing
  filter(dist_rail_real_1970 <= 200) |>     # Filtro de distância
  filter(!(code_amc %in% codes_pontas))     # Exclusão das pontas

# 3. TRANSFORMAMOS EM DATAFRAME COMUM (O passo crucial)
# st_drop_geometry remove a coluna 'geometry', transformando o objeto 
# 'sf' (espacial) em um 'tbl' (dataframe padrão) que o feols aceita.
df_reg <- st_drop_geometry(df_limpo)

# ==============================================================================
# 1. RODA OS MODELOS (Primeiro Estágio Incremental)
# ==============================================================================
modelos_fs <- list(
  "M1" = feols(dummy_atendida_real_1969 ~ dummy_atendida_sintetica | state_abbr, data = df_reg, se = "hetero"),
  "M2" = feols(dummy_atendida_real_1969 ~ dummy_atendida_sintetica + dist_sintetica_vizinhos | state_abbr, data = df_reg, se = "hetero"),
  "M3" = feols(dummy_atendida_real_1969 ~ dummy_atendida_sintetica + dist_sintetica_vizinhos + bio_1 + bio_12 + bio_15 | state_abbr, data = df_reg, se = "hetero"),
  "M4" = feols(dummy_atendida_real_1969 ~ dummy_atendida_sintetica + dist_sintetica_vizinhos + bio_1 + bio_12 + bio_15 + dist_rio_km + pct_solo_latossolos | state_abbr, data = df_reg, se = "hetero")
)

# ==============================================================================
# 2. FUNÇÃO ROBUSTA PARA EXTRAIR ESTATÍSTICAS
# ==============================================================================
# Acessamos a coluna 3 (t-stat) por índice para evitar erros de idioma do sistema
get_f <- function(m) {
  t_val <- summary(m)$coeftable["dummy_atendida_sintetica", 3]
  sprintf("%.2f", t_val^2)
}

# ==============================================================================
# 3. CONSTRUÇÃO DA TABELA (Matriz de Controles + Observações + F-Stat)
# ==============================================================================
linhas_extras <- data.frame(
  term = c("Observações", "F-Statistic (Instrumento)", "Efeito Fixo UF", "Lag Espacial", "Clima", "Hidrografia e Solo"),
  M1 = c(nobs(modelos_fs$M1), get_f(modelos_fs$M1), "Sim", "Não", "Não", "Não"),
  M2 = c(nobs(modelos_fs$M2), get_f(modelos_fs$M2), "Sim", "Sim", "Não", "Não"),
  M3 = c(nobs(modelos_fs$M3), get_f(modelos_fs$M3), "Sim", "Sim", "Sim", "Não"),
  M4 = c(nobs(modelos_fs$M4), get_f(modelos_fs$M4), "Sim", "Sim", "Sim", "Sim")
)

# ==============================================================================
# 4. GERAÇÃO DA TABELA FINAL
# ==============================================================================
modelsummary(
  modelos_fs,
  output = "markdown", 
  coef_map = c("dummy_atendida_sintetica" = "Dummy Sintética"),
  stars = c('*' = 0.1, '**' = 0.05, '***' = 0.01),
  add_rows = linhas_extras,
  gof_omit = ".*", # Remove estatísticas automáticas para usar apenas as nossas
  title = "Primeiro Estágio: Validação da Dummy de Tratamento",
  notes = "Nota: O F-Statistic refere-se ao teste de exclusão do instrumento (t-stat^2). 'Sim' indica a inclusão do controle no modelo."
)



modelsummary(
  modelos_fs,
  output = "03-resultados/tabelas/primeiro_estagio.tex", # Caminho e nome do arquivo
  coef_map = c("dummy_atendida_sintetica" = "Dummy Sintética"),
  add_rows = linhas_extras,
  gof_omit = ".*",
  title = "Primeiro Estágio: Validação da Dummy de Tratamento"
)
