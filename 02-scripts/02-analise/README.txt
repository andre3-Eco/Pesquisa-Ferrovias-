================================================================================
PASTA 02-ANALISE — Scripts de Regressão IV (Variáveis Instrumentais)
Projeto: Ferrovias do Nordeste — Análise IV (2SLS)
Última atualização: Jul 2026 — Melhorias de eficiência e ajustes de especificação
================================================================================

Esta pasta contém 8 scripts que rodam as regressões do projeto. Todos usam o
pacote fixest para 2SLS (first-stage + second-stage) e compartilham a mesma
estrutura de controles e filtros.

================================================================================
ORDEM CORRETA DE EXECUÇÃO (mantida, com melhorias de eficiência)
================================================================================

  1. first stage den.R                              (baseline first-stage)
  2. first_stage_multiraio.R                        (multiraio first-stage)
  3. second_stage_baseline.R                        (baseline 2SLS)
  4. second_stage_multidimensional.R                (multidimensional 2SLS)
  5. second_stage_placebo_in_time.R                 (placebo in-time)
  6. second_stage_fake.R                            (placebo in-space)
  7. second_stage_multiraio.R                       (multiraio 2SLS)
  8. 9_INFERENCIA_ESPACIAL_ROBUSTA.R                (inferência espacial)

  * Adições Recentes (Agosto/2026):
  9. second_stage_1920_*.R                          (Outcomes de 1920, incluindo Maquinário, Educação, Fábricas e Casas de Negócio)
 10. second_stage_1920_spillover_*.R                (Efeitos de Spillover para variáveis de 1920)
 11. visualizacao_*.R                               (Visualizações de Efeitos Diretos, Subamostras e Spillover)

Os scripts de análise são independentes entre si (cada um carrega suas
próprias bases), exceto que:
   - Todos requerem que a pasta 01-preparacao tenha sido executada antes.
   - 9_INFERENCIA_ESPACIAL_ROBUSTA é um complemento de robustez, rodado
     após os resultados principais.
   - Todos os scripts foram otimizados para melhor desempenho e ajustes
     de especificação conforme atualizações de julho de 2026.

================================================================================
ESTRUTURA COMUM A TODOS OS SCRIPTS
================================================================================

Cada script segue o mesmo padrão:

  1. Carrega base(s) de dados (base_completa_integrada_buffer.rds ou
     base_completa_integrada.csv + base específica)
  2. Filtra para estados do Nordeste (MA, PI, CE, RN, PB, PE, AL, SE, BA)
  3. Carrega painel de pontas (painel_amcs_pontas_ano_a_ano.csv) e exclui
     AMCs que eram pontas no ano de tratamento
  4. Define controles fixos: bio_1, bio_12, bio_15, dist_rio_km,
     densidade_hidro_km_km2, pct_solo_latossolos, pct_solo_neossolos
  5. Loop por ano de tratamento: para cada ano T, regride outcome ~
     densidade_buffer_real_T | state_abbr | endo ~ instrumento
  6. Compila resultados em CSV e exporta para 03-resultados/csv/

================================================================================
DESCRIÇÃO DETALHADA DE CADA SCRIPT (versões otimizadas julho/2026)
================================================================================

── 1. first stage den.R ─────────────────────────────────────────────────────────
   O que faz: Roda o PRIMEIRO ESTÁGIO baseline da estratégia IV. Regride a
   densidade real de buffer contra a densidade sintética (LCP), para cada ano.
   (Versão otimizada julho/2026 com melhor tratamento de dados ausentes)

   Fórmula:
     densidade_buffer_real_YYYY ~ densidade_buffer_sintetica_YYYY
     + bio_1 + bio_12 + bio_15
     + dist_rio_km + densidade_hidro_km_km2
     + pct_solo_latossolos + pct_solo_neossolos
     | state_abbr

   Entrada:
     - 01-dados/processados/base_completa_integrada_buffer.rds
     - 01-dados/processados/painel_amcs_pontas_ano_a_ano.csv

   Saída:
     - 03-resultados/csv/first_stage_buffer_density_sem_pontas_baseline.csv

   Colunas do output: ano, coeficiente, erro_padrao, t_estatistica, p_valor,
   F_estatistica, n_observacoes, n_pontas_excluidas, significancia,
   instrumento_forte (F >= 10).

   Critério de instrumento forte: F-stat >= 10 (regra de bolso Stock-Yogo).
   Exclui anos onde a densidade sintética é toda zero.
   Exclui AMCs que eram pontas naquele ano específico.
   Melhorias: Tratamento robusto de erros com tryCatch, criação explícita de diretórios,
   e mensagens de progresso aprimoradas.

── 2. first_stage_multiraio.R ───────────────────────────────────────────────────
   O que faz: Versão MULTIRAIOS do primeiro estágio. Para cada raio
   (5, 10, 20, 50 km) e cada ano, regride a densidade real contra a sintética.
   (Versão otimizada julho/2026 com correção de junção de dados e loops aprimorados)

   Fórmula:
     densidade_buffer_real_<raio>km_YYYY ~ densidade_buffer_sintetica_<raio>km_YYYY
     + controles | state_abbr

   Entrada:
     - 01-dados/processados/base_completa_integrada.csv
     - 01-dados/processados/base_densidade_buffer_multiraio.csv
     - controles_clima, controles_rios, controles_solo (RDS)
     - painel_amcs_pontas_ano_a_ano.csv

   Saída:
     - 03-resultados/csv/first_stage_multiraio.csv

   Lógica: Loop aninhado ano × raio. Para cada combinação, monta fórmula com
   nomes de coluna específicos (ex: densidade_buffer_real_5km_1900). Usa
   feols com fixed effects de estado.
   Melhorias: Remoção explícita de colunas de densidade antigas para evitar sufixos .x/.y,
   junção otimizada de outcomes, detecção automática de anos de tratamento,
   e função modular para regressão do primeiro estágio com tratamento robusto de erros.

── 3. second_stage_baseline.R ───────────────────────────────────────────────────
   O que faz: Roda o SEGUNDO ESTÁGIO baseline (2SLS). Estima o efeito causal
   da densidade real de ferrovias sobre PIB e população.
   (Versão otimizada julho/2026 com integração segura de outcomes e tratamento robusto de erros)

   Instrumento: densidade_buffer_sintetica_YYYY → densidade_buffer_real_YYYY

   Outcomes:
     Persistência (outcomes distantes no tempo):
       - log(pib_2010), log(pib_2003)
       - log(pop_total_2010), log(pop_total_2000)

     Contemporâneos (outcome mais próximo do ano de tratamento):
       - Mapeamento ano → outcome mais próximo disponível:
         1858-1929 → pib_1920, pop_1940
         1930-1938 → pib_1939, pop_1940
         ... (ver tabela contemporaneo_map no script)
         2003      → pib_2003, pop_2000

   Fórmula 2SLS:
     outcome ~ controles | state_abbr | endo ~ instrumento

   Entrada:
     - 01-dados/processados/base_completa_integrada_buffer.rds
     - 01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.rds
     - 01-dados/processados/painel_amcs_pontas_ano_a_ano.csv

   Saída:
     - 03-resultados/csv/second_stage_buffer_density_sem_pontas_baseline.csv

   Lógica: Para cada ano T com densidade > 0, filtra pontas, roda 2SLS para
   cada outcome de persistência e contemporâneo. Usa feols com fórmula de
   duas partes: outcome ~ controles | state_abbr | endo ~ instrumento.

   IMPORTANTE: Faz integração dos outcomes interpolados, removendo colunas
   sobrepostas para evitar sufixos .x/.y no left_join.
   Melhorias: Tratamento robusto de erros com tryCatch, extração inteligente de coeficientes
   (lidando com versões do fixest que usam ou não usam prefixo "fit_"), cálculo automático
   do F-statístico de primeira estágio, e mensagens de progresso aprimoradas.

── 4. second_stage_multidimensional.R ───────────────────────────────────────────
   O que faz: Expande a análise para outcomes MULTIDIMENSIONAIS:
     - PIB Total e Setorial (Agropecuário, Indústria, Serviços)
     - Urbanização (tx_urbanizacao, pop_urbana)
     - IDH decomposto (Geral, Educação, Longevidade, Renda)
   (Versão otimizada julho/2026 com mapearamento avançado de outcomes e tratamento robusto)

   Fórmula: idêntica à baseline (2SLS com fixed effects de estado).

   Outcomes mapeados por prefixo:
     PIB:      pib, pibag, pibi, pibse          → log
     Urb:      tx_urbanizacao, pop_urbana        → nível
     IDH:      adh_idhm, adh_idhm_e/l/r          → nível

   Entrada:
     - base_completa_integrada_buffer.rds
     - outcomes_amc_ne_interpolado.rds
     - painel_amcs_pontas_ano_a_ano.csv

   Saída:
     - 03-resultados/csv/second_stage_multidimensional_results.csv

   Lógica: Para cada ano de tratamento T, varre todos os anos de outcome
   disponíveis para cada prefixo. Monta fórmula com log() para variáveis de
   PIB e em nível para as demais. Filtra N < 15.
   
   Melhorias: Mapeamento sofisticado de outcomes por prefixo com detecção automática
   de anos disponíveis, tratamento robusto de erros com tryCatch, validação de 
   existência de variáveis antes da regressão, função modular para 2SLS com suporte
   para variáveis em log e nível, e progress reporting aprimorado.
   Nota: Este script é o mais abrangente e gera o maior número de regressões.

── 5. second_stage_placebo_in_time.R ─────────────────────────────────────────────
   O que faz: Teste PLACEBO IN-TIME usando future density. Para cada ano T,
   usa a densidade de ferrovias inauguradas APÓS T como tratamento e testa se
   isso prediz outcomes em T.
   (Versão otimizada julho/2026 com mapeamento aprimorado de outcomes contemporâneos)

   Fórmula:
     outcome_T ~ future_density_T | state_abbr | (endo ~ instrumento)
     onde: endo = densidade_buffer_real_future_T
           inst = densidade_buffer_sintetica_future_T

   Entrada:
     - 01-dados/processados/base_completa_integrada.csv
     - 01-dados/processados/base_densidade_buffer_future.csv
       (gerado por base_buffer_future.R)
     - outcomes_amc_ne_interpolado.rds
     - controles_clima, controles_rios, controles_solo (RDS)

   Saída:
     - 03-resultados/csv/resultados_placebo_in_time_future.csv

   Lógica: Inverte a direção temporal. O outcome é o mais próximo ≤ T.
   Interpretação:
     - Se coeficiente significativo → evidência de endogeneidade (reverse
       causality): lugares que receberiam ferrovias no futuro já eram mais
       prósperos.
     - Se coeficiente ≈ 0 (p > 0.10) → placebo aprovado → instrumento exógeno.

   Outcomes testados: pib, pibag, pibi, pibse, pop_total (todos em log).

   Resumo final mostra taxa de significância por escopo (esperado ~5% se
   exógeno).
   
   Melhorias: Mapeamento sofisticado de outcomes com detecção automática de anos
   disponíveis, tratamento robusto de erros com tryCatch, validação prévia de 
   existência de arquivos necessários, função modular para 2SLS com suporte para
   variáveis em log e nível, e progress reporting aprimorado.

── 6. second_stage_fake.R ────────────────────────────────────────────────────────
   O que faz: Teste PLACEBO IN-SPACE usando rede sintética deslocada 50 km.
   A variável endógena continua sendo a densidade REAL (não deslocada), mas o
   instrumento é a densidade da sintética FALSA (deslocada).
   (Versão otimizada julho/2026 com placebo continental atualizado e tratamento robusto)

   Fórmula:
     outcome ~ controles | state_abbr |
     densidade_buffer_real_T ~ densidade_buffer_sintetica_fake50e_T

   Entrada:
     - 01-dados/processados/base_completa_integrada.csv
     - 01-dados/processados/base_densidade_buffer_placebo_multiraio.csv
       (gerado por base_buffer_placebo.R, atualização de julho/2026)
     - outcomes_amc_ne_interpolado.rds
     - painel_amcs_pontas_ano_a_ano.csv
     - controles_clima, controles_rios, controles_solo (RDS)

   Saída:
     - 03-resultados/csv/resultados_placebo_in_space_fake50e.csv

   Parâmetro: direcao ("norte" ou "leste"), deve bater com o usado em
   create_fake_routes.R e base_buffer_placebo.R.

   Outcomes: PIB total/setorial, urbanização, IDH decomposto (igual ao
   multidimensional).

   Lógica: Se o instrumento deslocado ainda prediz outcomes, a estratégia IV
   é inválida (o instrumento não é exógeno). Espera-se que os coeficientes
   sejam não-significativos para o placebo ser aprovado.

   IMPORTANTE: Este script não usa base_completa_integrada_buffer.rds. Ele
   monta sua própria base juntando base_main + base_densidade_fake + controles
   + outcomes.
   
   Melhorias: Uso de placebo continental (ao invés de deslocamento simples de 50km),
   remoção inteligente de colunas sobrepostas para evitar sufixos .x/.y, 
   tratamento robusto de erros com tryCatch, função modular para 2SLS com suporte
   para variáveis em log e nível, validação de existência de arquivos necessários,
   e progress reporting aprimorado.

── 7. second_stage_multiraio.R ───────────────────────────────────────────────────
   O que faz: Teste de sensibilidade a MÚLTIPLOS RAIOS de buffer. Para cada
   raio (5, 10, 20, 50 km) e ano, roda 2SLS completo.
   (Versão otimizada julho/2026 com tratamento robusto e progress reporting aprimorado)

   Fórmula (para cada combinação raio × ano):
     outcome ~ controles | state_abbr |
     densidade_buffer_real_<raio>km_T ~ densidade_buffer_sintetica_<raio>km_T

   Entrada:
     - 01-dados/processados/base_completa_integrada.csv
     - 01-dados/processados/base_densidade_buffer_multiraio.csv
       (gerado por base_buffer_multiraio.R)
     - outcomes_amc_ne_interpolado.rds
     - controles_clima, controles_rios, controles_solo (RDS)

   Saída:
     - 03-resultados/csv/second_stage_multiraio.csv

   Outcomes: PIB total/setorial, urbanização, IDH decomposto.

   Lógica: Loop triplo: ano_trat × raio × outcomes. Para cada combinação,
   monta fórmula com nomes de coluna específicos do raio. Resumo final agrupa
   por variável endógena para comparar raios.

   Interpretação: Se resultados são robustos a diferentes raios, fortalece a
   validade do desenho de pesquisa. Se desaparecem com raios maiores, sugere
   que o efeito é local (5-10 km).
   
   Melhorias: Remoção preventiva de join com painel_pontas para evitar 
   explosão combinatória, mapeamento sofisticado de outcomes por prefixo com 
   detecção automática de anos disponíveis, tratamento robusto de erros com 
   tryCatch, função modular super-robusta para 2SLS com múltiplas tentativas 
   de extração de coeficientes, cálculo isolado de F-stat e R², uso do N real 
   reportado pelo modelo, e progress reporting aprimorado com indicadores 
   de processamento por lote.

── 8. 9_INFERENCIA_ESPACIAL_ROBUSTA.R ────────────────────────────────────────────
   O que faz: Teste de ROBUSTEZ da inferência à correlação espacial. Roda o
   mesmo 2SLS com 5 tipos de erro-padrão:
     1. hetero          (heterocedástico-robusto, baseline)
     2. cluster         (clusterizado por microrregião)
     3. conley_50       (Conley HAC, cutoff 50 km)
     4. conley_100      (Conley HAC, cutoff 100 km)
     5. conley_200      (Conley HAC, cutoff 200 km)
   (Versão otimizada julho/2026 com proteção avançada fixest e visualização aprimorada)

   Anos testados: 1996, 2003 (fixos, evitando 2010 onde tratamento pode não
   atingir).

   Outcomes testados:
     - log(pib_2010), log(pib_2003)
     - log(pop_total_2010)
     - tx_urbanizacao_2010
     - adh_idhm_2010

   Entrada:
     - 01-dados/processados/base_completa_integrada_buffer.rds
     - 01-dados/processados/amcs_geometria.rds (para coordenadas)
     - 01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.rds
     - painel_amcs_pontas_ano_a_ano.csv

   Saída:
     - 03-resultados/csv/resultados_inferencia_espacial_robusta.csv
     - 03-resultados/graficos/inferencia_espacial_se_painel.png
     - 03-resultados/graficos/inferencia_espacial_pvalor_painel.png

   Lógica:
     1. Extrai centroides das AMCs (lon, lat) para Conley HAC.
     2. Cria cluster artificial (code_microrregiao) baseado em tercis de
        latitude/longitude caso não exista variável natural.
     3. Para cada combinação ano × outcome × tipo_se, roda 2SLS com o
        respectivo vcov.
     4. Gera gráficos comparativos: erro-padrão e p-valor por tipo de
        inferência, facetados por outcome.
   
   Melhorias: Otimização significativa com processamento vetorializado, 
   proteção robusta contra erros do fixest com múltiplas tentativas de 
   extração de coeficientes, criação automática de diretórios para saída, 
   visualização aprimorada com ggplot2 e salvamento em alta resolução, 
   e tratamento inteligente de variáveis ausentes.
   Interpretação: Se os erros-padrão inflam significativamente com Conley
   (especialmente cutoff 100-200 km) e os p-valores cruzam 0.05, a
   significância baseline pode ser espúria (devido a dependência espacial
   não modelada).

── 9. second_stage_1920_*.R (Novos - Ago/2026) ─────────────────────────────────
   O que fazem: Estimam os efeitos diretos das ferrovias sobre as variáveis 
   educacionais e estruturais de 1920. Existem versões em nível e log, bem
   como versões filtradas para Semiárido (e.g. `second_stage_1920_semiarido.R`).

   Fórmula:
     outcome_1920 ~ controles | state_abbr | endo ~ instrumento

   Entrada:
     - 01-dados/processados/base_completa_integrada_buffer.rds
     - 01-dados/processados/base_domi_1920_interpolado.rds
     - 01-dados/processados/painel_amcs_pontas_ano_a_ano.csv

   Saída:
     - 03-resultados/csv/second_stage_1920_*.csv

   Lógica:
     Similar aos modelos baseline, mas cruzam os dados com as variáveis 
     (alfabetização, maquinário, fábricas) de 1920, limitando a amostra até
     o ano de tratamento 1920.

── 10. second_stage_1920_spillover_*.R (Novos - Ago/2026) ──────────────────────
   O que fazem: Testam o efeito de "spillover" (transbordamento espacial).
   A variável dependente é o outcome da AMC, mas o tratamento é a exposição
   ferroviária dos VIZINHOS daquela AMC.

   Fórmula:
     outcome_1920 ~ controles | state_abbr | vizinhos_dens_real ~ vizinhos_dens_sint

   Entrada:
     Mesmas bases dos modelos diretos, mas usa Matriz de Vizinhança Espacial
     (tipo Rainha/Queen) gerada via pacote 'spdep'.

   Saída:
     - 03-resultados/csv/second_stage_1920_spillover_*.csv

   Lógica:
     Multiplica a densidade férrea de cada AMC pela matriz de pesos espaciais 
     (W) para obter a densidade espacialmente defasada (W*X). O 2SLS usa 
     W*dens_sintetica como instrumento para W*dens_real.

── 11. visualizacao_*.R (Novos - Ago/2026) ─────────────────────────────────────
   O que fazem: Geram os gráficos padronizados para visualização dos efeitos 
   diretos, subamostras e spillovers das variáveis de 1920.

   Fórmula/Gráficos:
     Gráficos de pontos com intervalos de confiança (erro padrão). 
     Usa o pacote `patchwork` para unir resultados A e B na mesma figura.

   Entrada:
     - CSVs gerados na etapa de estimação (e.g., `second_stage_1920_semiarido_maquinario.csv`)

   Saída:
     - 03-resultados/plots/direct_effects_maquinario_geral_1920.png
     - 03-resultados/plots/direct_effects_maquinario_subsamples_1920.png
     - 03-resultados/plots/spillover_effects_maquinario_subsamples_1920.png

   Lógica:
     Filtram a amostra de interesse (Geral, Atendidos/Não-Atendidos por ferrovias
     ou Semiárido), formatam as paletas de cores padrão (Roxo e Verde) e 
     exportam PNGs de alta qualidade para o relatório final.

================================================================================
DEPENDÊNCIAS (PRÉ-REQUISITOS PARA RODAR QUALQUER SCRIPT DESTA PASTA)
================================================================================

TODOS os scripts requerem que a pasta 01-preparacao tenha sido executada.
Especificamente:

  Arquivos sempre necessários:
    - 01-dados/processados/base_completa_integrada_buffer.rds
      OU base_completa_integrada.csv (depende do script)
    - 01-dados/processados/painel_amcs_pontas_ano_a_ano.csv
    - 01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.rds

Arquivos necessários para scripts específicos:
     - base_densidade_buffer_placebo_multiraio.csv     (second_stage_fake.R)
     - base_densidade_buffer_future.csv           (second_stage_placebo_in_time.R)
     - base_densidade_buffer_multiraio.csv        (first_stage_multiraio.R,
                                                    second_stage_multiraio.R)

  Controles (carregados via RDS):
    - controles_clima_amcs_nordeste.rds
    - controles_rios_amcs_nordeste.rds
    - controles_solo_amcs_nordeste.rds

================================================================================
PACOTES R NECESSÁRIOS
================================================================================
  tidyverse, fixest, sf, stringr, readr (todos os scripts)
  (dplyr já incluso no tidyverse)

================================================================================
SAÍDA DE RESULTADOS
================================================================================
  Todos os CSVs de resultados vão para: 03-resultados/csv/
  Gráficos (quando gerados) vão para:     03-resultados/graficos/

================================================================================
RESUMO DA ESTRATÉGIA EMPÍRICA (atualizada julho/2026)
================================================================================

  Variável endógena:     densidade_buffer_real_YYYY
  Instrumento:           densidade_buffer_sintetica_YYYY
  Fixed effects:         state_abbr (9 estados do NE)
  Controles:             7 variáveis ambientais fixas no tempo
  Amostra:               AMCs do Nordeste, excluindo pontas no ano T
  Método:                2SLS via feols (fixest)

  Testes de validade:
    First-stage F-stat   → instrumento forte se F ≥ 10
    Placebo in-time      → future density não deve predizer outcomes
    Placebo in-space     → rede deslocada não deve predizer outcomes
    Multiraio            → sensibilidade à largura do buffer
    Conley SE            → robustez à correlação espacial
     - Atualizações de julho/2026: melhorias de eficiência nos loops de estimação, ajustes nas especificações de controles e filtros, padronização de nomes de variáveis e saídas para maior reprodutibilidade.