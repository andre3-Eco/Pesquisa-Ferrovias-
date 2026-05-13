# ============================================================================
# DOWNLOAD COP30 
# ============================================================================

required_packages <- c("httr", "terra", "progress", "lubridate")
install_if_missing <- function(pkgs) {
  new <- pkgs[!pkgs %in% installed.packages()[, "Package"]]
  if(length(new)) install.packages(new, dependencies = TRUE)
  invisible(lapply(pkgs, require, character.only = TRUE))
}
install_if_missing(required_packages)

# ============================================================================
# 1. CONFIGURAÇÕES
# ============================================================================

api_key <- "Chave-API"
dem_type <- "COP30"
output_format <- "GTiff"
base_url <- "https://portal.opentopography.org/API/globaldem"

# ⚙️ PARÂMETROS OTIMIZADOS
CHUNK_LAT <- 2.0          # Altura do bloco em graus (latitude)
CHUNK_LON <- 2.0          # Largura do bloco em graus (longitude)
TIMEOUT_SEC <- 900        # Timeout: 15 minutos por request
MAX_RETRIES <- 5          # Número máximo de tentativas
MIN_FILE_SIZE <- 50000    # Tamanho mínimo válido: 50 KB

# Área de interesse: Nesse caso Nordeste do Brasil
bbox <- list(south = -18.5, north = -1.0, west = -48.5, east = -34.5)

# ============================================================================
# 2. CRIAR GRID DE BLOCOS 2° x 2°
# ============================================================================
#   Subdivide uma área geográfica delimitada (bounding box) em uma grade (grid) de blocos menores, baseando-se em intervalos definidos de latitude e longitude.

create_fine_grid <- function(bbox, lat_step, lon_step) {
  lats <- seq(bbox$south, bbox$north, by = lat_step)
  lons <- seq(bbox$west, bbox$east, by = lon_step)
  
  chunks <- list()
  id <- 1
  
  for (i in seq_len(length(lats) - 1)) {
    for (j in seq_len(length(lons) - 1)) {
      chunks[[id]] <- list(
        id = id,
        name = sprintf("tile_%02d_%02d", i, j),
        south = lats[i], 
        north = min(lats[i + 1], bbox$north), 
        west = lons[j], 
        east = min(lons[j + 1], bbox$east)
      )
      id <- id + 1
    }
  }
  return(chunks)
}

chunks <- create_fine_grid(bbox, CHUNK_LAT, CHUNK_LON)
cat(sprintf("🔲 Grid criado: %d blocos de %.1f° x %.1f°\n\n", length(chunks), CHUNK_LAT, CHUNK_LON))

# ============================================================================
# 3. FUNÇÃO DE DOWNLOAD COM RESUME E TIMEOUT ESTENDIDO
# ============================================================================

download_with_resume <- function(chunk, api_key, dem_type, output_format,
                                 timeout = TIMEOUT_SEC, max_retries = MAX_RETRIES) {
  
  file_name <- paste0("mde_", chunk$name, ".tif")
  partial_file <- paste0(file_name, ".partial")
  
  log <- function(msg, level = "INFO") {
    ts <- format(Sys.time(), "%H:%M:%S")
    cat(sprintf("[%s] [%s] %s: %s\n", ts, level, chunk$name, msg))
  }
  
  # Verificar se já existe arquivo completo válido
  if (file.exists(file_name)) {
    if (file.info(file_name)$size > MIN_FILE_SIZE) {
      log("✅ Arquivo já existe e é válido - pulando", "SKIP")
      return(list(success = TRUE, file = file_name, skipped = TRUE))
    } else {
      log("⚠️ Arquivo existente muito pequeno - removendo", "WARN")
      file.remove(file_name)
    }
  }
  
  # Preparar para download 
  mode <- if (file.exists(partial_file)) "append" else "write"
  start_byte <- if (file.exists(partial_file)) file.info(partial_file)$size else 0
  
  log(sprintf("Iniciando download (área: %.0f km²)%s", 
              chunk$area, if(start_byte > 0) paste0(" - RESUME a partir de ", round(start_byte/1e6, 1), " MB") else ""))
  
  for (attempt in 1:max_retries) {
    tryCatch({
      
     
      headers <- if (start_byte > 0) {
        list(`Range` = paste0("bytes=", start_byte, "-"))
      } else {
        list()
      }
      
      response <- httr::GET(
        url = base_url,
        query = list(
          demtype = dem_type,
          south = chunk$south, north = chunk$north,
          west = chunk$west, east = chunk$east,
          outputFormat = output_format,
          API_Key = api_key
        ),
        httr::write_disk(partial_file, overwrite = (start_byte == 0)),
        httr::timeout(timeout),
        httr::progress(),
        do.call(httr::add_headers, headers)
      )
      
      status <- httr::status_code(response)
      
      if (status %in% c(200, 206)) {  # 206 = Partial Content (resume)
        # Mover arquivo parcial para final
        file.rename(partial_file, file_name)
        
        file_size <- file.info(file_name)$size
        if (file_size > MIN_FILE_SIZE) {
          log(sprintf("✅ Download concluído: %.2f MB", file_size / 1e6))
          return(list(success = TRUE, file = file_name, size = file_size))
        } else {
          log("⚠️ Arquivo muito pequeno após download", "WARN")
          file.remove(file_name)
        }
        
      } else if (status == 204) {
        log("⚠️ Sem dados para esta região", "WARN")
        if (file.exists(partial_file)) file.remove(partial_file)
        return(list(success = FALSE, reason = "no_data"))
        
      } else if (status == 401) {
        log("❌ API Key inválida", "ERROR")
        return(list(success = FALSE, reason = "unauthorized"))
        
      } else {
        log(sprintf("⚠️ HTTP %d - Tentativa %d/%d", status, attempt, max_retries), "WARN")
      }
      
    }, error = function(e) {
      log(sprintf("❌ Erro: %s (tentativa %d/%d)", e$message, attempt, max_retries), "ERROR")
      
      # Manter arquivo parcial para resume na próxima tentativa
      if (file.exists(partial_file)) {
        log(sprintf("📦 Arquivo parcial mantido: %.2f MB", 
                    file.info(partial_file)$size / 1e6), "INFO")
      }
    })
    
    # Backoff exponencial com limite máximo
    if (attempt < max_retries) {
      wait <- min(2^attempt, 30)  # Máximo 30s entre tentativas
      log(sprintf("⏳ Aguardando %ds antes de retry...", wait))
      Sys.sleep(wait)
    }
  }
  
  # Falha definitiva
  log("❌ Falha após todas as tentativas", "ERROR")
  return(list(success = FALSE, reason = "max_retries"))
}

# ============================================================================
# 4. LOOP PRINCIPAL 
# ============================================================================


successful <- c()
failed <- c()
skipped <- c()

pb <- progress::progress_bar$new(
  total = length(chunks),
  format = "[:bar] :percent | Chunk :current/:total | ETA: :eta",
  clear = FALSE
)

for (i in seq_along(chunks)) {
  pb$tick()
  
  cat(sprintf("\n[%d/%d] %s\n", i, length(chunks), chunks[[i]]$name))
  
  result <- download_with_resume(
    chunk = chunks[[i]],
    api_key = api_key,
    dem_type = dem_type,
    output_format = output_format
  )
  
  # ✅ CORREÇÃO: Usar isTRUE() para evitar erro com NULL
  if (isTRUE(result$success)) {
    
    # ✅ CORREÇÃO: isTRUE() retorna FALSE se skipped for NULL
    if (isTRUE(result$skipped)) {
      skipped <- c(skipped, chunks[[i]]$name)
      cat(sprintf("⏭️  Pulado: %s\n", chunks[[i]]$name))
    } else {
      successful <- c(successful, result$file)
      cat(sprintf("✅ Concluído: %s (%.2f MB)\n", 
                  chunks[[i]]$name, (result$size %||% 0) / 1e6))
    }
    
  } else {
    reason <- result$reason %||% "desconhecido"
    failed <- c(failed, sprintf("%s (%s)", chunks[[i]]$name, reason))
    cat(sprintf("❌ Falhou: %s - %s\n", chunks[[i]]$name, reason))
  }
  
  # Rate limiting: pausa leve a cada 10 chunks
  if (i %% 10 == 0) {
    cat("⏸️ Pausa de 3s para rate limiting...\n")
    Sys.sleep(3)
  }
}

# Operador auxiliar para lidar com NULL (adicione no início do script)
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

# ============================================================================
# 5. MERGE DE MDEs - COP30 
# ============================================================================

# 1. Limpeza total de memória antes de começar um processo pesado
if ("raster" %in% loadedNamespaces()) detach("package:raster", unload = TRUE)
rm(list = ls(all.names = TRUE))
gc()

library(terra)

# Configura o R para usar o disco rígido em vez da RAM sempre que possível
terra::terraOptions(todisk = TRUE, progress = 4)

# 2. Localizar todos os arquivos baixados
cat("🔍 Buscando arquivos baixados...\n")
valid_files <- list.files(pattern = "^mde_tile_.*\\.tif$", full.names = TRUE)

if (length(valid_files) == 0) {
  stop("❌ Nenhum arquivo MDE encontrado na pasta atual. Verifique o diretório de trabalho (setwd).")
}

cat(sprintf("📦 Encontrados %d arquivos para união.\n", length(valid_files)))

# 3. Preparar a coleção e fundir
cat("🔗 Criando a coleção virtual (isso poupa RAM)...\n")
# Carrega as referências de todos os rasters de uma vez
rasters <- lapply(valid_files, terra::rast)

# Transforma a lista numa coleção espacial otimizada em C++
r_collection <- terra::sprc(rasters)

cat("⚙️ Iniciando o merge... \n")
# O merge real acontece aqui
mde_final <- terra::merge(r_collection)

# 4. Salvar o arquivo final comprimido
output_file <- "alt_nordeste_completo_COP30_30m.tif"
cat(sprintf("\n💾 Salvando o mosaico final: %s\n", output_file))

# Exportação pesada.
terra::writeRaster(
  mde_final,
  filename = output_file,
  overwrite = TRUE,
  gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2", "BIGTIFF=YES", "NUM_THREADS=ALL_CPUS"),
  progress = TRUE
)

cat("\n SUCESSO! Mosaico gerado.\n")
cat(sprintf("📏 Dimensões: %d x %d células\n", nrow(mde_final), ncol(mde_final)))





