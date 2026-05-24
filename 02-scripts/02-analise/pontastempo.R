# ==============================================================================
# IDENTIFICAÇÃO CRONOLÓGICA DAS AMCs NAS PONTAS DAS FERROVIAS (PAINEL NO TEMPO)
# ==============================================================================

library(dplyr)
library(sf)
library(tidyr)

sf_use_s2(FALSE)

cat(strrep("=", 80), "\n")
cat("GERANDO PAINEL HISTÓRICO DE AMCs NAS PONTAS DA MALHA FERROVIÁRIA\n")
cat(strrep("=", 80), "\n\n")

# 1. Checagens iniciais
if (!exists("ferrovias_reais")) stop("Carregue o objeto 'ferrovias_reais' primeiro.")
if (!exists("amcs_geometria")) stop("Carregue o objeto 'amcs_geometria' primeiro.")

# Projetar AMCs para o mesmo CRS das ferrovias
amcs_proj <- st_transform(amcs_geometria, st_crs(ferrovias_reais))
snap_tol <- 50 # Tolerância de 50 metros para arredondamento topológico

# Identificar todos os anos em que houve expansão na malha
anos_expansao <- sort(unique(na.omit(ferrovias_reais$ano_inaug)))

cat(sprintf("Processando %d anos de expansão ferroviária...\n", length(anos_expansao)))

# Lista para guardar os resultados de cada ano
lista_pontas_ano <- list()

# 2. Loop no tempo: construindo a rede cumulativa
for (ano_atual in anos_expansao) {
  
  # Filtra a rede para existir APENAS até o ano atual (Malha Cumulativa)
  rede_ano <- ferrovias_reais |> filter(ano_inaug <= ano_atual)
  
  # Descobre os terminais agrupando por ID da ferrovia
  terminais_df <- rede_ano |>
    arrange(id, cod_part) |>
    group_by(id, Nome) |> 
    group_modify(~ {
      # Extrai a primeira e a última coordenada de cada segmento
      pts_list <- lapply(seq_len(nrow(.x)), function(i) {
        coords <- st_coordinates(st_geometry(.x[i, ]))[, 1:2]
        rbind(coords[1, ], coords[nrow(coords), ])
      })
      todos <- as.data.frame(do.call(rbind, pts_list))
      names(todos) <- c("X", "Y")
      
      # Arredonda para evitar problemas de casa decimal
      todos$Xr <- round(todos$X / snap_tol) * snap_tol
      todos$Yr <- round(todos$Y / snap_tol) * snap_tol
      
      # Uma ponta VERDADEIRA da malha atual é um ponto que só toca em 1 segmento
      terminais <- todos |>
        dplyr::count(Xr, Yr) |>
        dplyr::filter(n == 1) |>
        dplyr::left_join(
          todos |> dplyr::distinct(Xr, Yr, .keep_all = TRUE) |> dplyr::select(Xr, Yr, X, Y),
          by = c("Xr", "Yr")
        )
      return(terminais)
    }) |>
    ungroup()
  
  # Se não houver terminais (erro topológico raro), pula o ano
  if (nrow(terminais_df) == 0) next
  
  # Transforma os terminais deste ano em pontos espaciais
  terminais_sf <- terminais_df |>
    st_as_sf(coords = c("X", "Y"), crs = st_crs(ferrovias_reais))
  
  # Cruzamento com as AMCs
  pontas_com_amc <- st_join(terminais_sf, amcs_proj, join = st_intersects) |>
    filter(!is.na(code_amc)) # Remove pontos que caíram no mar ou fora do mapa
  
  # Salva os resultados do ano
  if (nrow(pontas_com_amc) > 0) {
    res_ano <- pontas_com_amc |>
      st_drop_geometry() |>
      select(id_ferrovia = id, nome_ferrovia = Nome, code_amc, list_name_muni_2010) |>
      mutate(ano_corte = ano_atual) |>
      distinct() # Evita duplicatas se a cidade for grande e tiver dois terminais
    
    lista_pontas_ano[[as.character(ano_atual)]] <- res_ano
  }
}

# 3. Consolidação do Painel
painel_pontas <- bind_rows(lista_pontas_ano) |>
  arrange(code_amc, ano_corte)

cat("✓ Painel longitudinal gerado com sucesso!\n\n")

# ==============================================================================
# 4. CRIANDO A BASE DE EXPORTAÇÃO (FORMATOS LONGO E LARGO)
# ==============================================================================

# Opcional: Descobrir o "período de vida" como terminal (Ano de entrada e Ano de saída)
ciclo_pontas <- painel_pontas |>
  group_by(code_amc, list_name_muni_2010, id_ferrovia, nome_ferrovia) |>
  summarise(
    ano_virou_ponta = min(ano_corte),
    ano_deixou_ser_ponta = max(ano_corte),
    anos_totais_como_ponta = n_distinct(ano_corte),
    .groups = "drop"
  ) |>
  # Se o ano que deixou de ser ponta for o último ano da malha, ela ainda é ponta
  mutate(status_atual = ifelse(ano_deixou_ser_ponta == max(anos_expansao), "Ponta Final", "Ponta Temporária"))

# Exportação
dir.create("01-dados/processados", showWarnings = FALSE, recursive = TRUE)

write_csv(painel_pontas, "01-dados/processados/painel_amcs_pontas_ano_a_ano.csv")
write_csv(ciclo_pontas, "01-dados/processados/ciclo_vida_amcs_pontas.csv")

cat("Bases exportadas:\n")
cat("1. 'painel_amcs_pontas_ano_a_ano.csv' -> Para usar como filtro nas regressões ano a ano.\n")
cat("2. 'ciclo_vida_amcs_pontas.csv'      -> Resumo de quando a cidade ganhou e perdeu o status.\n")

# Para checar rapidamente no RStudio:
View(ciclo_pontas)