================================================================================
PASTA 01-PREPARACAO — Scripts de Preparação de Dados
Projeto: Ferrovias do Nordeste — Análise IV (Variáveis Instrumentais)
================================================================================

Esta pasta contém 14 scripts que constroem as bases de dados usadas nas
regressões. A ordem de execução segue uma hierarquia lógica: dados brutos →
processamento espacial → integração.

================================================================================
ORDEM CORRETA DE EXECUÇÃO (FLUXO LÓGICO)
================================================================================

FASE 1 — FONTES PRIMÁRIAS (rodar uma vez)
  1. create_fake_routes.R
  2. pontastempo.R

FASE 2 — BASES DE DENSIDADE DE BUFFER (alternativas, uma por análise)
  3. base_buffer.R                  (baseline)
  4. base_buffer_fake.R             (placebo in-space, requer create_fake_routes.R)
  5. base_buffer_future.R           (placebo in-time)
  6. base_buffer_multiraio.R        (teste de múltiplos raios)
  7. base_buffer_placebo_in_time.R  (variação inversa no tempo — alternativa)

FASE 3 — CONTROLES AMBIENTAIS (ordem indiferente entre si)
  8. 8_controles_clima.R
  9. 9_controles_solo.R
  10. 10_controles_rios.R

FASE 4 — OUTCOMES DE DESENVOLVIMENTO
  11. 7_Extrair_Outcomes_Desenvolvimento.R

FASE 5 — PÓS-PROCESSAMENTO
  12. SPATIAL_INTERPOLACAO_OUTCOMES_v2.R

FASE 6 — INTEGRAÇÃO FINAL (MASTER)
  13. 0_MASTER_Criar_Base_Buffer_Unificada.R

================================================================================
DESCRIÇÃO DETALHADA DE CADA SCRIPT
================================================================================

── 1. create_fake_routes.R ──────────────────────────────────────────────────────
  O que faz: Cria uma rede sintética "falsa" deslocando a rede LCP original
  50 km para o norte ou leste. Serve como instrumento placebo para o teste
  "Placebo In-Space".

  Entrada:
    - 05-geometrias/Rotas_LCP_OD_Real.gpkg

  Saída:
    - 05-geometrias/Rotas_LCP_OD_Real_fake50e.gpkg (ou _fake50n.gpkg)

  Lógica: Lê a rede sintética original, soma c(50000, 0) ou c(0, 50000) às
  coordenadas, reaplica CRS EPSG:31984, salva.

  Rodar antes de: base_buffer_fake.R, second_stage_fake.R

── 2. pontastempo.R ─────────────────────────────────────────────────────────────
  O que faz: Identifica quais AMCs eram "pontas" da rede ferroviária em cada
  ano, gerando um painel longitudinal (ano a ano).

  Entrada:
    - ferrovias_reais (objeto sf em memória)
    - amcs_geometria (objeto sf em memória, ou .rds)

  Saída:
    - 01-dados/processados/painel_amcs_pontas_ano_a_ano.csv
    - 01-dados/processados/ciclo_vida_amcs_pontas.csv

  Lógica: Para cada ano, constrói a malha cumulativa (ano_inaug <= ano),
  identifica os terminais (pontos que tocam só 1 segmento), cruza com AMCs,
  e gera painel. O segundo arquivo agrupa por AMC/ferrovia para mostrar o
  ciclo de vida como ponta.

  Rodar antes de: TODOS os scripts de análise (first_stage, second_stage) que
  excluem pontas.

  Nota: Requer ferrovias_reais carregado previamente com colunas id, Nome,
  cod_part, ano_inaug.

── 3. base_buffer.R ─────────────────────────────────────────────────────────────
  O que faz: Cria a base de densidade de buffer BASELINE. Calcula, para cada
  ano, a densidade de ferrovias (real e sintética) dentro de um buffer de 5 km
  ao redor da malha, como fração da área de cada AMC.

  Entrada:
    - 05-geometrias/ferrovias_cronologicas.gpkg
    - 05-geometrias/Rotas_LCP_OD_Real.gpkg
    - (via geobr) AMCs comparáveis 1970–2010

  Saída:
    - 01-dados/processados/amcs_geometria.rds
    - 01-dados/processados/base_densidade_buffer_unificada.csv
    - 01-dados/processados/base_densidade_buffer_unificada.rds

  Lógica: Filtra AMCs do Nordeste (códigos começando com "2"), projeta para
  UTM 24S (EPSG:31984). Para cada ano, faz st_union da malha cumulativa,
  st_buffer(5000), st_intersection com AMCs, e densidade = área_interceptada /
  área_AMC. Gera colunas densidade_buffer_real_YYYY e
  densidade_buffer_sintetica_YYYY para cada ano.

  IMPORTANTE: Este script também gera amcs_geometria.rds, que é pré-requisito
  para quase todos os outros scripts.

── 4. base_buffer_fake.R ────────────────────────────────────────────────────────
  O que faz: Versão PLACEBO IN-SPACE da base_buffer.R. Usa a rede sintética
  deslocada 50 km (gerada por create_fake_routes.R) no lugar da original.

  Entrada:
    - 01-dados/processados/amcs_geometria.rds
    - 05-geometrias/ferrovias_cronologicas.gpkg
    - 05-geometrias/Rotas_LCP_OD_Real_fake50e.gpkg (ou _fake50n.gpkg)

  Saída:
    - 01-dados/processados/base_densidade_buffer_fake_fake50e.csv
    - 01-dados/processados/base_densidade_buffer_fake_fake50e.rds

  Lógica: Idêntica à base_buffer.R, mas carrega a rede sintética deslocada.
  Gera colunas densidade_buffer_real_YYYY e
  densidade_buffer_sintetica_fake50e_YYYY.

  Parâmetro ajustável: variável 'direcao' ("norte" ou "leste").

── 5. base_buffer_future.R ──────────────────────────────────────────────────────
  O que faz: Versão PLACEBO IN-TIME. Inverte a lógica de acumulação: calcula
  densidade de ferrovias inauguradas APÓS o ano T (não até T).

  Entrada:
    - 01-dados/processados/amcs_geometria.rds
    - 05-geometrias/ferrovias_cronologicas.gpkg
    - 05-geometrias/Rotas_LCP_OD_Real.gpkg

  Saída:
    - 01-dados/processados/base_densidade_buffer_future.csv
    - 01-dados/processados/base_densidade_buffer_future.rds

  Lógica: Filtra ano_inaug > ano (em vez de <=). Exclui o último ano da série
  (future density = 0 para todos). Gera colunas
  densidade_buffer_real_future_YYYY e densidade_buffer_sintetica_future_YYYY.

  Interpretação do placebo: Se future_density_T prediz PIB_T, há evidência de
  endogeneidade (lugares destinados a receber ferrovias já eram mais prósperos).

── 6. base_buffer_multiraio.R ───────────────────────────────────────────────────
  O que faz: Versão com MÚLTIPLOS RAIOS de buffer (5, 10, 20, 50 km).
  Testa sensibilidade dos resultados à largura do buffer.

  Entrada:
    - 01-dados/processados/amcs_geometria.rds
    - 05-geometrias/ferrovias_cronologicas.gpkg
    - 05-geometrias/Rotas_LCP_OD_Real.gpkg

  Saída:
    - 01-dados/processados/base_densidade_buffer_multiraio.csv
    - 01-dados/processados/base_densidade_buffer_multiraio.rds

  Lógica: Loop aninhado ano × raio. Para cada combinação, calcula densidade.
  Gera colunas como densidade_buffer_real_5km_1900,
  densidade_buffer_sintetica_20km_1900, etc.

  Parâmetros: raios_m = c(5000, 10000, 20000, 50000).

── 7. base_buffer_placebo_in_time.R ─────────────────────────────────────────────
  O que faz: Alternativa de placebo in-time com dois modos:
    - "future": usa ano_inaug > ano (similar a base_buffer_future.R)
    - "windowN": usa janela deslizante de N anos antes de T
      (ano_inaug > (ano - N) & ano_inaug <= ano)

  Entrada/Saída: Similar a base_buffer_future.R, mas com sufixo configurável.

  Parâmetro: tipo_inverso ("future", "window10", "window20", etc.)

── 8. 8_controles_clima.R ───────────────────────────────────────────────────────
  O que faz: Extrai controles climáticos do WorldClim v1 (~1 km, 10 minutos)
  por AMC do Nordeste.

  Fonte: 02_dados_espaciais/raster_clima/
    - bio_10m_esri/bio/  (BIO1–BIO19)
    - prec_10m_esri/prec/  (prec_1–prec_12)
    - tmean_10m_esri/tmean/ (tmean_1–tmean_12)

  Saída:
    - controles_clima_amcs_nordeste.csv
    - controles_clima_amcs_nordeste.rds

  Lógica: Carrega AMCs do NE (WGS84), extrai média zonal de cada raster via
  terra::extract(). Divide temperatura por 10 (WorldClim armazena ×10).
  Gera 19 + 12 + 12 = 43 variáveis.

── 9. 9_controles_solo.R ────────────────────────────────────────────────────────
  O que faz: Extrai controles pedológicos do shapefile de Solos do Brasil
  (IBGE/EMBRAPA, escala 1:5.000.000, 2020) por AMC.

  Fonte: 02_dados_espaciais/VETORES_AMBIENTAIS/brasil_solos_5m_20201104/
         brasil_solos_5m_20201104.shp

  Saída:
    - controles_solo_amcs_nordeste.csv
    - controles_solo_amcs_nordeste.rds

  Lógica: Faz st_intersection entre polígonos de solo e AMCs, calcula
  percentual de área de cada ordem de solo por AMC (pct_solo_latossolos,
  pct_solo_neossolos, etc.) + classe dominante + área mapeada total.
  NAs em ordem1 → "AGUA_DUNAS".

── 10. 10_controles_rios.R ──────────────────────────────────────────────────────
  O que faz: Extrai controles hidrográficos da Base Hidrográfica
  Ottocodificada (BHO) da ANA por AMC.

  Fonte: 02_dados_espaciais/VETORES_AMBIENTAIS/GEOFT_BHO_REF_RIO/
         GEOFT_BHO_REF_RIO.shp

  Saída:
    - controles_rios_amcs_nordeste.csv
    - controles_rios_amcs_nordeste.rds

  Lógica:
    1. Classifica rios por hierarquia Otto (≤7 dígitos = principal,
       8–9 = médio, ≥10 = tributário).
    2. Calcula distância do centroide de cada AMC ao rio mais próximo
       (qualquer e principal).
    3. Calcula st_intersection para obter comprimentos de rios dentro de
       cada AMC.
    4. Gera: dist_rio_km, dist_rio_principal_km, comp_total_rios_km,
       comp_rios_principais_km, densidade_hidro_km_km2, n_rios_distintos,
       otto_min, etc.

── 11. 7_Extrair_Outcomes_Desenvolvimento.R ──────────────────────────────────────
  O que faz: Extrai e harmoniza TODOS os outcomes de desenvolvimento em nível
  municipal, agrega para AMC, e gera base wide.

  Fontes:
    - ipeadatar: PIB total e setorial, população, IDHM, Gini, pobreza
    - SIDRA (tabela 5457): PAM — área plantada, qtd produzida, valor da produção

  Escopos:
    1. PIB e VAB setorial (PIB, PIBAG, PIBI, PIBSE, PIBG, IMPPIB)
    2. População (POPUR, POPRU) → derivados: pop_total, tx_urbanizacao
    3. PAM agrícola (SIDRA 5457)
    4. IDHM, Gini, pobreza (ADH_IDHM, ADH_IDHM_E/L/R, ADH_GINI, ADH_PMPOB,
       ADH_PIND, ADH_RDPC)

  Saída (arquivos principais):
    - 01-dados/processados/outcomes/outcomes_amc_wide.csv
    - 01-dados/processados/outcomes/outcomes_amc_wide.rds
    - (diversos arquivos intermediários por escopo)

  Lógica:
    1. Cria mapeamento município → AMC via amcs_geometria.rds.
    2. Baixa cada série do ipeadatar e SIDRA.
    3. Harmoniza: agregação para AMC (soma para PIB/Pop/PAM,
       média ponderada por população para IDH/Gini).
    4. Converte para formato wide (uma coluna por série_ano).
       Ex: pib_1920, pib_1970, pop_total_1940, adh_idhm_1991, etc.

  Requer: amcs_geometria.rds (criado por base_buffer.R)

── 12. SPATIAL_INTERPOLACAO_OUTCOMES_v2.R ───────────────────────────────────────
  O que faz: Preenche NAs nos outcomes históricos usando Inverse Distance
  Weighting (IDW) com leave-one-out cross-validation.

  Entrada:
    - amcs_geometria.rds
    - 01-dados/processados/outcomes/outcomes_amc_wide.rds

  Saída:
    - 01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.csv
    - 01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.rds
    - 01-dados/processados/outcomes/interpolados/resumo_cv_interpolacao.csv

  Lógica:
    1. Junta geometria + outcomes, calcula centroides em UTM 24S.
    2. Identifica colunas com NAs.
    3. Para cada coluna, escolhe escala (log se todos valores > 0, nível caso
       contrário). Interpola via IDW (idp=2, nmax=15).
    4. Leave-one-out CV: para cada ponto observado, interpola usando os demais
       e calcula RMSE.
    5. Substitui apenas os NAs originais pelos valores interpolados.
    6. Exporta tabela de validação cruzada.

  Importante: Rodar DEPOIS de 7_Extrair_Outcomes_Desenvolvimento.R e ANTES dos
  scripts de análise que usam outcomes interpolados (second_stage_*.R).

── 13. 0_MASTER_Criar_Base_Buffer_Unificada.R ───────────────────────────────────
  O que faz: Script MASTER que integra TUDO em uma base única pronta para
  regressão.

  Entrada (via source() dos scripts anteriores + leitura dos outputs):
    - base_buffer.R          → base_densidade_buffer_unificada.csv
    - 8_controles_clima.R    → controles_clima_amcs_nordeste.csv
    - 9_controles_solo.R     → controles_solo_amcs_nordeste.csv
    - 10_controles_rios.R    → controles_rios_amcs_nordeste.csv
    - 7_Extrair_Outcomes...R → outcomes_amc_wide.csv

  Saída:
    - 01-dados/processados/base_completa_integrada_buffer.csv
    - 01-dados/processados/base_completa_integrada_buffer.rds

  Lógica:
    1. Cria mapeamento AMC → estado (state_abbr) via geobr.
    2. Source base_buffer.R para gerar densidade.
    3. Source controles_clima.R, controles_solo.R, controles_rios.R.
    4. Adiciona coluna state_abbr.
    5. Source 7_Extrair_Outcomes_Desenvolvimento.R.
    6. Carrega todos os outputs e faz left_join sequencial por code_amc.
    7. Remove colunas duplicadas, reordena logicamente
       (code_amc, state_abbr, área, tratamento, controles, outcomes).
    8. Valida NAs e exporta.

  Este é o script que gera a base usada por TODOS os scripts da pasta
  02-analise. É o ponto final da pipeline de preparação.

  Nota: A ordem dos source() dentro deste script define a ordem de execução
  efetiva. Se rodar este script isoladamente, ele chama automaticamente
  base_buffer.R, controles_clima.R, controles_solo.R, controles_rios.R, e
  7_Extrair_Outcomes_Desenvolvimento.R.

================================================================================
DEPENDÊNCIAS ENTRE SCRIPTS (GRAFO DE EXECUÇÃO)
================================================================================

[create_fake_routes.R] ─────────────────────────────────────┐
                                                            │
[base_buffer.R] ───> amcs_geometria.rds ────────────────────┤
     │                                                      │
     ├──> base_densidade_buffer_unificada.csv                │
     │                                                      │
[base_buffer_fake.R] <─── (usa rede deslocada) ─────────────┘
[base_buffer_future.R]     (usa rede original, filtro >)
[base_buffer_multiraio.R]  (usa rede original, múltiplos raios)
[base_buffer_placebo_in_time.R] (usa rede original, modos future/window)

[pontastempo.R] ───> painel_amcs_pontas_ano_a_ano.csv

[8_controles_clima.R]  ───> controles_clima_amcs_nordeste.csv
[9_controles_solo.R]   ───> controles_solo_amcs_nordeste.csv
[10_controles_rios.R]  ───> controles_rios_amcs_nordeste.csv

[7_Extrair_Outcomes_Desenvolvimento.R] ───> outcomes_amc_wide.csv
     │
[SPATIAL_INTERPOLACAO_OUTCOMES_v2.R] ───> outcomes_amc_ne_interpolado.rds

[0_MASTER_Criar_Base_Buffer_Unificada.R] ───> base_completa_integrada_buffer.rds
     │
     └──> (usado por TODOS os scripts da pasta 02-analise)

================================================================================
CONTROLES FIXOS USADOS NAS REGRESSÕES (presentes em todos os 2nd-stage)
================================================================================
  bio_1, bio_12, bio_15          (clima: temperatura anual, precipitação anual,
                                   sazonalidade de precipitação)
  dist_rio_km                     (distância ao rio mais próximo)
  densidade_hidro_km_km2          (densidade hidrográfica)
  pct_solo_latossolos             (% de latossolos)
  pct_solo_neossolos              (% de neossolos)
  state_abbr                      (fixed effect de estado)

================================================================================
ARQUIVOS EXTERNOS NECESSÁRIOS (que NÃO são gerados por esta pasta)
================================================================================
  - 05-geometrias/ferrovias_cronologicas.gpkg
  - 05-geometrias/Rotas_LCP_OD_Real.gpkg
  - 02_dados_espaciais/raster_clima/ (rasters WorldClim)
  - 02_dados_espaciais/VETORES_AMBIENTAIS/brasil_solos_5m_20201104/
  - 02_dados_espaciais/VETORES_AMBIENTAIS/GEOFT_BHO_REF_RIO/
  - Acesso à internet (ipeadatar, SIDRA, geobr)