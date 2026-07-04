================================================================================
PASTA EXPLORATORIA — Scripts Exploratórios e de Geração de Dados Espaciais
Projeto: Ferrovias do Nordeste — Análise IV
================================================================================

Esta pasta contém 4 scripts que geram os dados geoespaciais fundamentais do
projeto: o Modelo Digital de Elevação (COP30), o raster de custo ferroviário,
e as redes sintéticas (LCP — Least Cost Path). São a base de tudo; sem eles
não há instrumento.

================================================================================
ORDEM CORRETA DE EXECUÇÃO (SEQUENCIAL E DEPENDENTE)
================================================================================

  1. API opentopography01.R      → baixa e mescla MDE COP30 30m
  2. Rastercusto.R               → gera raster de custo a partir do MDE
  3. LCP_Sintetica_Real_OD.R     → gera rede sintética LCP (pares O-D reais)
  4. LCP(random).R               → gera rede sintética aleatória (contrafactual)

Os scripts 1→2→3 são estritamente sequenciais. O script 4 é independente
(usa o mesmo raster de custo que o 3, mas não depende dele).

================================================================================
DESCRIÇÃO DETALHADA DE CADA SCRIPT
================================================================================

── 1. API opentopography01.R ────────────────────────────────────────────────────
  O que faz: Baixa o Modelo Digital de Elevação (MDE) COP30 a 30m de
  resolução para todo o Nordeste do Brasil via API do OpenTopography,
  e depois mescla todos os tiles em um único raster.

  Etapas:
    a) Divide o Nordeste (bbox: -18.5° a -1.0° S, -48.5° a -34.5° W)
       em grid de blocos 2°×2°.
    b) Para cada bloco, faz download via API OpenTopography com:
       - Suporte a resume (Range headers) se download interrompido
       - Retry com backoff exponencial (até 5 tentativas)
       - Timeout de 15 minutos por request
       - Rate limiting (pausa 3s a cada 10 chunks)
       - Verificação de tamanho mínimo (50 KB)
    c) Após todos os downloads, mescla os tiles com terra::merge() e
       terra::sprc().

  Saída:
    - Diversos arquivos mde_tile_XX_YY.tif (intermediários, um por bloco)
    - alt_nordeste_completo_COP30_30m.tif (raster final mesclado)

  Requer:
    - Chave de API do OpenTopography (variável api_key)
    - Pacotes: httr, terra, progress, lubridate

  Nota: A chave de API no script é placeholder ("Chave-API"). Deve ser
  substituída por uma chave real. Sem chave válida, o script não baixa nada.

  Tempo estimado: ~30-60 minutos dependendo da conexão (≈ 130 blocos de
  2°×2° para cobrir o NE).

── 2. Rastercusto.R ─────────────────────────────────────────────────────────────
  O que faz: Gera o raster de custo ferroviário histórico (século XIX,
  bitola métrica) a partir do MDE COP30.

  Lógica da função de custo:
    1. Agrega MDE de 30m para 90m (fator 3, média).
    2. Calcula declividade em % (tan(slope_rad) * 100).
    3. Aplica função de custo físico-exponencial:
       custo = 1 + 20 × rampa% + (rampa%)^6
       - 1 = custo base fixo
       - 20 × rampa% = equação de Davis (resistência ao movimento)
       - (rampa%)^6 = penalidade exponencial para rampas íngremes
    4. Aplica barreira: declividade > 1.8% → custo = 999999 (intransponível)
    5. Visualiza o raster com máscara (NA para áreas proibitivas).

  Entrada:
    - alt_nordeste_completo_COP30_30m.tif

  Saída:
    - cost_raster_ferrovias_ne_1880_1920_90m.tif

  Parâmetros:
    - rampa_maxima = 1.8 (limite técnico para bitola métrica)
    - Agregação: fator 3 (30m → 90m)
    - Compressão: LZW via GDAL

  Nota técnica: Usa álgebra de rasters nativa do terra (C++) em vez de
  app() com função R customizada — ordens de magnitude mais rápido.
  A execução real (writeRaster) só ocorre no momento da gravação; até lá
  as operações são "lazy".

── 3. LCP_Sintetica_Real_OD.R ───────────────────────────────────────────────────
  O que faz: Gera a REDE SINTÉTICA PRINCIPAL do projeto, usando pares
  Origem-Destino REAIS extraídos das ferrovias históricas. Esta rede é o
  INSTRUMENTO em toda a estratégia IV.

  Etapas:
    a) Prepara raster de custo: agrega (fator 3), preenche NAs com
       9999999, calcula condutância = 1/custo.
    b) Cria máscara de terra continental com recuo costeiro de 2.5 km
       (buffer negativo) para evitar rotas sobre o mar. Aplica máscara
       na condutância.
    c) Extrai pares O-D reais das ferrovias históricas:
       - Para cada ramal (id, Nome), identifica terminais (pontos que
         tocam só 1 segmento na malha).
       - A origem é o ponto mais antigo (menor ano_inaug) com preferência
         por is_start=TRUE.
       - Os destinos são todos os demais terminais do mesmo ramal.
       - Filtra pares com distância ≥ 5 km.
    d) Para cada par O-D:
       - Cria janela local (buffer 130 km ao redor dos dois pontos).
       - Recorta condutância local, extende bordas.
       - Faz snapping dos pontos para terra firme (evita pontos no mar).
       - Calcula LCP via leastcostpath::create_lcp() com 16 vizinhos.
       - Atribui metadados: id, Nome, cod_part, ano_inaug, tipo_rota.
    e) Exporta rede final.
    f) Cria PAINEL CUMULATIVO: para cada ano, gera a malha cumulativa
       (ano_inaug <= ano) e empilha em um único gpkg.

  Entrada:
    - cost_raster_ferrovias_ne_1880_1920_90m.tif
    - 05-geometrias/ferrovias_cronologicas.gpkg

  Saída:
    - 05-geometrias/Rotas_LCP_OD_Real.gpkg (rede sintética principal)
    - 05-geometrias/Painel_LCP_Cumulativo.gpkg (painel ano a ano)

  Pacotes críticos: leastcostpath (cria grafo de condutância e calcula LCP)

  Lógica do instrumento: A rede sintética responde à pergunta contrafactual:
  "Se os engenheiros do século XIX só tivessem o mapa topográfico (sem
  conhecer fatores econômicos/políticos), por onde teriam construído as
  ferrovias?" A rota LCP minimiza o custo topográfico entre os mesmos pares
  O-D reais. A correlação entre densidade real e sintética captura o
  componente topográfico (exógeno) do traçado.

  Nota: O parâmetro snap_tol=50 (tolerância de snapping em metros) é usado
  tanto na extração de terminais quanto na identificação de pontas. Deve
  ser consistente com pontastempo.R.

── 4. LCP(random).R ─────────────────────────────────────────────────────────────
  O que faz: Gera uma rede sintética ALTERNATIVA/CONTRAFACTUAL usando pares
  O-D totalmente ALEATÓRIOS (não baseados nas ferrovias reais).

  Parâmetros:
    - N_ORIGENS = 10 (pontos de partida sorteados)
    - N_DESTINOS = 10 (destinos por origem → ~100 rotas)
    - Semente fixa: set.seed(42) para reprodutibilidade

  Etapas:
    a) Prepara raster de custo (similar ao LCP_Sintetica_Real_OD.R mas
       sem máscara de terra — usa apenas filtro de custo < 9999999).
    b) Amostra 5000 pontos aleatórios viáveis via spatSample() com
       na.rm=TRUE.
    c) Filtra pontos com custo < 9999999 (remove mar e serras).
    d) Sorteia 10 origens do pool filtrado.
    e) Para cada origem, sorteia 10 destinos (excluindo o próprio ponto).
    f) Para cada par, usa janela móvel (buffer 100 km) para recortar
       condutância local e calcular LCP.

  Saída:
    - Rotas_Aleatorias_LCP_Sinteticas.gpkg

  Uso: Esta rede é um contrafactual "puro" — não usa informação histórica
  de onde as ferrovias realmente foram construídas. Pode servir como:
    - Teste de robustez alternativo (instrumento puramente topográfico)
    - Placebo adicional (se nem a topografia + aleatoriedade geram
      correlação com outcomes, fortalece a estratégia)

  Diferenças vs LCP_Sintetica_Real_OD.R:
    - Pares O-D aleatórios (não extraídos das ferrovias reais)
    - Sem máscara de terra/recuo costeiro
    - Sem painel cumulativo
    - Sem coluna ano_inaug (não usável diretamente na estratégia IV
      cronológica sem adaptação)

================================================================================
DEPENDÊNCIAS (GRAFO DE EXECUÇÃO)
================================================================================

[API opentopography01.R]
     │
     └──> alt_nordeste_completo_COP30_30m.tif
              │
[Rastercusto.R] ───> cost_raster_ferrovias_ne_1880_1920_90m.tif
              │
              ├──> [LCP_Sintetica_Real_OD.R] ───> Rotas_LCP_OD_Real.gpkg
              │         │                              │
              │         └──> Painel_LCP_Cumulativo.gpkg │
              │                                        │
              └──> [LCP(random).R] ───> Rotas_Aleatorias_LCP_Sinteticas.gpkg

O arquivo Rotas_LCP_OD_Real.gpkg é o INSTRUMENTO usado em toda a pipeline:
  → base_buffer.R (cálculo de densidade sintética)
  → create_fake_routes.R (deslocamento para placebo in-space)
  → Todos os first_stage/second_stage (via colunas densidade_buffer_sintetica_*)

O arquivo cost_raster_ferrovias_ne_1880_1920_90m.tif é necessário para
  ambos os scripts LCP.

================================================================================
PACOTES R NECESSÁRIOS
================================================================================
  API opentopography01.R:  httr, terra, progress, lubridate
  Rastercusto.R:           terra
  LCP_Sintetica_Real_OD.R: tidyverse, sf, terra, leastcostpath, geobr
  LCP(random).R:           tidyverse, sf, terra, leastcostpath

================================================================================
ARQUIVOS GERADOS QUE ALIMENTAM O RESTO DO PROJETO
================================================================================

  05-geometrias/Rotas_LCP_OD_Real.gpkg
    → base_buffer.R (lê este arquivo)
    → create_fake_routes.R (lê e desloca este arquivo)
    → base_buffer_fake.R, base_buffer_future.R, base_buffer_multiraio.R,
      base_buffer_placebo_in_time.R (todos leem este arquivo ou derivados)

  05-geometrias/Painel_LCP_Cumulativo.gpkg
    → (opcional, usável para visualização/análise temporal)

  cost_raster_ferrovias_ne_1880_1920_90m.tif
    → LCP_Sintetica_Real_OD.R e LCP(random).R (leem este arquivo)
    → Não é usado diretamente nos scripts de regressão

  alt_nordeste_completo_COP30_30m.tif
    → Rastercusto.R (lê este arquivo)
    → Não é usado diretamente nos scripts de regressão