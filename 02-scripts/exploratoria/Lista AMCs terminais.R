library(dplyr)
library(sf)

snap_tol <- 50

# 1. Extrair os pontos terminais (adaptado da sua Seção 3)
terminais_df <- ferrovias_reais |>
  arrange(id, cod_part) |>
  group_by(id, Nome) |> 
  group_modify(~ {
    pts_list <- lapply(seq_len(nrow(.x)), function(i) {
      coords <- st_coordinates(st_cast(st_geometry(.x[i, ]), "POINT"))[, 1:2]
      rbind(coords[1, ], coords[nrow(coords), ])
    })
    todos <- as.data.frame(do.call(rbind, pts_list))
    names(todos) <- c("X", "Y")
    
    todos$Xr <- round(todos$X / snap_tol) * snap_tol
    todos$Yr <- round(todos$Y / snap_tol) * snap_tol
    
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

# 2. Transformar o dataframe de terminais em um objeto espacial (pontos)
terminais_sf <- terminais_df |>
  st_as_sf(coords = c("X", "Y"), crs = st_crs(ferrovias_reais))

# 3. Projetar as AMCs para o mesmo CRS das ferrovias para garantir precisão no cruzamento
amcs_proj <- st_transform(amcs_geometria, st_crs(terminais_sf))

# 4. Cruzamento Espacial: descobre qual AMC toca cada ponto terminal
pontas_com_amc <- st_join(terminais_sf, amcs_proj, join = st_intersects)

# 5. Agrupar os resultados para criar uma lista amigável por ferrovia
lista_amcs_pontas <- pontas_com_amc |>
  st_drop_geometry() |>
  group_by(id, Nome) |>
  summarise(
    # Agrupa os códigos e nomes das AMCs separados por um delimitador
    amcs_codigo = paste(unique(na.omit(code_amc)), collapse = " e "),
    amcs_municipios = paste(unique(na.omit(list_name_muni_2010)), collapse = " | "),
    .groups = "drop"
  )

# Visualizar o resultado final
View(lista_amcs_pontas)