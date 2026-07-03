# Documentação: Bateria 9 — Novos Outcomes (4 Escopos)

**Script:** `02-scripts/02-analise/9_Bateria_Novos_Outcomes_4Escopos.R`  
**Data:** 17/05/2026  
**Total de regressões:** 4 especificações × 15 outcomes × 3 tratamentos = **180 regressões**

---

## 1. Visão Geral

Esta bateria expande a análise anterior (`8_Bateria_Completa_PIB_Pop.R`) em três dimensões:

1. **Novos outcomes** — incorpora todas as variáveis dependentes dos 4 escopos do projeto, indo além de PIB e população dos Censos 2003/2010.
2. **Tratamento defasado por construção** — cada outcome usa tratamento de pelo menos 20 anos antes, eliminando a confusão entre causa e efeito no cross-section.
3. **Controles alternativos** — as 4 especificações alternam entre lag espacial, variáveis climáticas, e características físicas (rios e solo), permitindo avaliar a sensibilidade dos resultados ao conjunto de controles.

---

## 2. Outcomes (15 variáveis dependentes)

### Escopo 1 — PIB e Renda

| Variável | Ano | Transformação | Tratamento |
|----------|-----|--------------|------------|
| PIB Total | 2000 | log | 1972 |
| PIB Total | 2010 | log | 1985 |
| PIB per capita | 2000 | log | 1972 |
| PIB per capita | 2010 | log | 1985 |

**Fonte:** Ipeadata (série PIB municipal, preços de 2010, R$ mil).  
**Harmonização:** soma dos municípios componentes de cada AMC.

### Escopo 2 — Dinâmica Demográfica

| Variável | Ano | Transformação | Tratamento |
|----------|-----|--------------|------------|
| Pop. Total | 1991 | log | 1969 |
| Pop. Total | 2000 | log | 1972 |
| Pop. Total | 2010 | log | 1985 |
| Taxa de Urbanização | 2010 | nível | 1985 |

**Fonte:** Ipeadata (POPUR + POPRU, Censos decenais + PNAD Contínua 1996/2007).  
**Harmonização:** soma de pop urbana + rural por AMC; taxa calculada como pop_urbana / pop_total.

### Escopo 3 — Transformação Estrutural (PAM)

| Variável | Ano | Transformação | Tratamento |
|----------|-----|--------------|------------|
| Valor da Produção Agrícola | 2000 | log | 1972 |
| Valor da Produção Agrícola | 2010 | log | 1985 |

**Fonte:** SIDRA — Pesquisa Agrícola Municipal (tabela 5457), categoria "Total de lavouras".  
**Harmonização:** soma do valor de produção dos municípios por AMC (R$ mil correntes).  
**Nota:** valores nominais, não deflacionados. Para comparações intertemporais use com cautela.

### Escopo 4 — Desenvolvimento Humano (Atlas DH)

| Variável | Ano | Transformação | Tratamento |
|----------|-----|--------------|------------|
| IDHM | 2000 | nível | 1972 |
| IDHM | 2010 | nível | 1985 |
| Renda dom. per capita | 2000 | log | 1972 |
| Renda dom. per capita | 2010 | log | 1985 |
| % Pobres | 2010 | nível | 1985 |

**Fonte:** Ipeadata (séries ADH_ do Atlas do Desenvolvimento Humano, Censos 1991/2000/2010).  
**Harmonização:** média ponderada pela população dos municípios por AMC.  
**Definições:**
- IDHM: Índice de Desenvolvimento Humano Municipal (escala 0–1)
- Renda per capita: média da renda domiciliar per capita (R$, preços de agosto 2010)
- % Pobres: proporção com renda < R$ 255/mês (linha de pobreza, preços 2010)

---

## 3. Tratamentos (variáveis endógenas)

Três tipos de tratamento, todos referentes ao **ano de tratamento específico de cada outcome** (ver critério de defasagem na seção 5):

| Tipo | Variável | Escala | Instrumento |
|------|----------|--------|-------------|
| Distância | `dist_rail_real_{ANO}` | km (contínua) | `dist_rail_sintetica_km` |
| Dummy | `dummy_atendida_real_{ANO}` | 0/1 (≤25km da ferrovia) | `dummy_atendida_sintetica` |
| Densidade | `densidade_real_{ANO}` | km/1000km² (contínua) | `densidade_sintetica` |

**Instrumento:** rede ferroviária sintética gerada por Least Cost Path (LCP) entre pares históricos de origem-destino. A rede sintética é considerada exógena: sua trajetória reflete a topografia e distâncias geográficas, não as características econômicas das localidades.

---

## 4. Especificações (4 combinações de amostra e controles)

### Especificação 1 — Amostra Completa | Lag Espacial

- **Amostra:** todas as ~700 AMCs do Nordeste
- **FE:** estado (state_abbr)
- **Controle:** `dist_sintetica_vizinhos` — lag espacial rainha da distância sintética dos vizinhos
- **Objetivo:** replicar a lógica da bateria anterior com os novos outcomes; controlar por autocorrelação espacial via lag

**Fórmula:**
```
log(Y) ou Y ~ dist_sintetica_vizinhos | state_abbr | endogena ~ instrumento
```

### Especificação 2 — Amostra Completa | Controles Climáticos

- **Amostra:** todas as AMCs do Nordeste
- **FE:** estado (state_abbr)
- **Controles:** `bio_1` (temperatura média anual), `bio_12` (precipitação anual total), `bio_15` (sazonalidade da precipitação — coef. de variação)
- **Objetivo:** testar se os resultados são robustos a controles de clima, que podem estar correlacionados com a localização das ferrovias (ex.: evitar o semiárido) e com os outcomes econômicos

**Fórmula:**
```
log(Y) ou Y ~ bio_1 + bio_12 + bio_15 | state_abbr | endogena ~ instrumento
```

### Especificação 3 — Dist ≤200km | Rios + Solo

- **Amostra:** AMCs com `dist_rail_real_{ANO} ≤ 200km` (amostra restrita ao entorno da rede)
- **FE:** estado (state_abbr)
- **Controles:** `dist_rio_km`, `densidade_hidro_km_km2`, `pct_solo_latossolos`, `pct_solo_neossolos`
- **Objetivo:** restringir a comparação a AMCs próximas ao sistema ferroviário (reduz extrapolação da função de primeira etapa) e controlar por recursos naturais que podem ter atraído investimentos ferroviários

**Nota:** o filtro `≤ 200km` usa a distância no **ano de tratamento** de cada outcome.

**Fórmula:**
```
log(Y) ou Y ~ dist_rio_km + densidade_hidro_km_km2 + pct_solo_latossolos + pct_solo_neossolos
            | state_abbr | endogena ~ instrumento
```

### Especificação 4 — Dist ≤200km + Excl. Pontas | Controles Completos

- **Amostra:** AMCs com `dist_rail_real_{ANO} ≤ 200km`, **excluindo as 44 AMCs nas extremidades da rede**
- **FE:** estado (state_abbr)
- **Controles:** lag espacial + clima (bio_1, bio_12, bio_15) + rios (dist_rio_km) + solo (pct_solo_latossolos) — conjunto completo
- **Objetivo:** especificação mais conservadora; exclui AMCs nas pontas da rede (onde o instrumento é mais fraco) e inclui todos os controles disponíveis

**Pontas corrigidas:** 44 AMCs identificadas por `st_nearest_feature` (método anterior com `st_contains` detectava apenas 4, pois pontos sobre fronteiras de polígonos eram descartados).

**Fórmula:**
```
log(Y) ou Y ~ dist_sintetica_vizinhos + bio_1 + bio_12 + bio_15 + dist_rio_km + pct_solo_latossolos
            | state_abbr | endogena ~ instrumento
```

---

## 5. Critério de Defasagem Temporal

Uma preocupação central em cross-section é que a localização de ferrovias pode ser endógena ao nível de desenvolvimento local — ferrovias foram construídas onde havia demanda econômica. Para mitigar esse problema, usamos o tratamento de **pelo menos 20 anos antes** do outcome:

| Outcome em | Tratamento de | Defasagem |
|-----------|--------------|-----------|
| 1991 | **1969** | 22 anos |
| 2000 | **1972** | 28 anos |
| 2010 | **1985** | 25 anos |

**Justificativa:**
- Em 1969–1985, a rede ferroviária do Nordeste já estava praticamente consolidada (expansões após 1960 foram mínimas).
- A infraestrutura de 1969–1985 é um estoque fixo para os outcomes de 1991–2010.
- Com o instrumento sintético (LCP), o tratamento de 1969–1985 é ainda mais exógeno do que o de 2003, pois reflete décadas de acumulação histórica, não decisões recentes.

**Anos de tratamento disponíveis na base:** 1858–2003 (anual ou irregular).  
Os anos 1969, 1972 e 1985 estão disponíveis em `dist_rail_real_`, `dummy_atendida_real_` e `densidade_real_`.

---

## 6. Transformação das Variáveis Dependentes

| Tipo | Transformação | Interpretação do coeficiente |
|------|--------------|------------------------------|
| Monetárias / contagem | **log(Y)** | Elasticidade (efeito % por unidade de tratamento) |
| Índices (0–1) / taxas | **nível (Y)** | Efeito absoluto em pontos percentuais |

Outcomes em log: PIB, PIB per capita, pop. total, valor da produção agrícola, renda per capita.  
Outcomes em nível: taxa de urbanização, IDHM, % pobres.

---

## 7. Critérios de Qualidade dos Instrumentos

| Métrica | Forte | Moderado | Fraco |
|---------|-------|---------|-------|
| F-stat (1º estágio) | > 10 | 5–10 | < 5 |
| p-valor (2º estágio) | < 0.05 | 0.05–0.10 | > 0.10 |
| R² ajustado (2º estágio) | > 0.30 | 0.10–0.30 | < 0.10 |

Referência: Stock & Yogo (2005) — F > 10 implica viés do estimador IV menor que 10% do viés OLS.

---

## 8. Leitura dos Resultados

**Arquivo:** `03-resultados/csv/resultados_bateria9_novos_outcomes.csv`

**Colunas principais:**

| Coluna | Significado |
|--------|-------------|
| `escopo` | Grupo temático (1_PIB, 2_Pop, 3_PAM, 4_Social) |
| `especificacao` | Qual especificação (1 a 4) |
| `tratamento` | Tipo de variável endógena |
| `ano_trat` | Ano de referência do tratamento |
| `outcome` | Variável dependente |
| `transf` | "log" ou "nivel" |
| `n_obs` | N após filtros e remoção de missings |
| `coef_ss` | Coeficiente do 2º estágio |
| `se_ss` | Erro padrão (robusto à heterocedasticidade) |
| `p_value` | p-valor (baseado em normal assintótica) |
| `f_stat` | F-estatístico do 1º estágio |
| `r2_ss` | R² ajustado do 2º estágio |
| `erro` | Mensagem de erro (se a regressão falhou) |

**Exemplo de interpretação:**
```
outcome   : PIB Total (2000, R$ mil)
tratamento: Dist. ferrovia real (1972)
coef_ss   = -0.0030   transf = log
p_value   = 0.012     f_stat = 22.5

→ Uma redução de 1 km na distância até a ferrovia em 1972
  está associada a um aumento de 0,30% no PIB total da AMC em 2000.
→ Significativo a 5% (p = 0.012 < 0.05).
→ Instrumento forte (F = 22.5 > 10).
```

---

## 9. Diferenças em Relação à Bateria Anterior (8_Bateria_Completa_PIB_Pop.R)

| Aspecto | Bateria 8 | Bateria 9 |
|---------|-----------|-----------|
| Outcomes | 6 (pop 2003/2010 + PIB setorial 2003) | 15 (4 escopos, anos 1991–2010) |
| Ano de tratamento | 2003 (fixo) | 1969/1972/1985 (por outcome) |
| Defasagem mínima | 0 anos | 22–28 anos |
| Controles | Lag espacial (fixo) | Alternados: lag / clima / rios+solo / completo |
| Especificações | 5 | 4 |
| AMCs nas pontas excluídas | 4 (st_contains) | 44 (st_nearest_feature) |
| Regressões totais | 90 | 180 |

---

## 10. Próximos Passos Sugeridos

1. **Instrumento placebo** — substituir rede sintética real por uma rede fake (ex.: rotacionada 90°) e verificar que F-stat cai e coeficientes tornam-se não-significativos.
2. **Incluir 1991 para todos os escopos** — atualmente apenas pop. total tem outcome em 1991; IDHM e renda também têm (`adh_idhm_1991`, `adh_rdpc_1991`).
3. **Análise de mecanismos** — comparar coeficientes entre escopos: se PIB cresce mais que pop, o canal é produtividade; se pop cresce mais, é migração.
4. **Heterogeneidade regional** — rodar por estado ou por sub-região do Nordeste (Nordeste semi-árido vs. litoral).
