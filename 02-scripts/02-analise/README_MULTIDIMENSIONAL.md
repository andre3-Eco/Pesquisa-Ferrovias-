# ANÁLISE MULTIDIMENSIONAL: PIB, URBANIZAÇÃO E IDH

## 📋 Visão Geral

Este conjunto de scripts implementa uma análise causal **multidimensional** usando **IV/2SLS** para estimar o impacto da infraestrutura ferroviária em múltiplas dimensões do desenvolvimento regional.

### Escopos de Análise

| Escopo | Variáveis | Período | Descrição |
|--------|-----------|---------|-----------|
| **PIB Setorial** | `pib`, `pibag`, `pibi`, `pibse` | 1920-2021 | PIB Total, Agropecuário, Industrial, Serviços |
| **Urbanização** | `tx_urbanizacao`, `pop_urbana` | 1940-2022 | Taxa de urbanização e população urbana |
| **IDH (Decomposto)** | `adh_idhm`, `adh_idhm_e`, `adh_idhm_l`, `adh_idhm_r` | 1991, 2000, 2010 | Geral, Educação, Longevidade, Renda |

---

## 🚀 Como Usar

### Passo 1: Rodar a Análise Principal

```r
source("02-scripts/02-analise/second_stage_multidimensional.R")
```

**O que faz:**
- Carrega todas as bases de dados
- Identifica anos de tratamento disponíveis (1858-2003)
- Para cada ano de tratamento, roda regressões 2SLS em TODOS os outcomes
- Salva resultados em `03-resultados/csv/second_stage_multidimensional_results.csv`

**Tempo estimado:** 30-45 minutos (dependendo da quantidade de regressões)

**Saída principal:**
```
second_stage_multidimensional_results.csv
├─ ano_tratamento: Ano da inauguração da ferrovia
├─ ano_outcome: Ano do outcome observado
├─ escopo: Categoria do outcome (PIB, Urbanização, IDH)
├─ outcome_var: Nome específico da variável
├─ coeficiente: Efeito estimado
├─ p_valor: Significância
├─ F_stat_1estagio: Força do instrumento
├─ R2_2estagio: R² do segundo estágio
└─ significancia: Asteriscos (*, **, ***)
```

---

### Passo 2: Visualizar e Summarizar Resultados

```r
source("02-scripts/03-visualizacao/visualizar_multidimensional.R")
```

**O que faz:**
- Cria 5 gráficos principais
- Compila 4 tabelas resumidas
- Printa estatísticas na console

**Saída de gráficos:**
```
03-resultados/graficos/
├─ 01_boxplot_coeficientes_por_escopo.png
├─ 02_significancia_por_escopo.png
├─ 03_f_statistic_por_escopo.png
├─ 04_serie_temporal_coeficientes.png
└─ 05_heatmap_coeficientes.png
```

**Saída de tabelas:**
```
03-resultados/csv/
├─ resultados_significativos_p05.csv       (apenas p < 0.05)
├─ resumo_por_escopo.csv                   (resumo por categoria)
├─ top_efeitos_mais_fortes.csv             (15 maiores coeficientes)
└─ resultados_por_escopo_ano.csv           (matriz escopo × ano)
```

---

## 📊 Interpretação dos Resultados

### Exemplo de Leitura

```
escopo: PIB_Agropecuário
outcome_var: pibag_1980
ano_tratamento: 1970
coeficiente: 0.0385
p_valor: 0.032
F_stat_1estagio: 12.4
n_observacoes: 650

INTERPRETAÇÃO:
→ Uma unidade a mais de densidade ferroviária em 1970 está associada 
  a um aumento de 3.85% no PIB agropecuário de 1980.
→ O efeito é significativo a 5% (p = 0.032).
→ O instrumento é forte (F = 12.4 > 10).
→ Baseado em 650 AMCs.
```

### Critérios de Qualidade

| Métrica | Excelente | Bom | Aceitável | Fraco |
|---------|-----------|-----|-----------|-------|
| **F-stat** | > 20 | 10-20 | 5-10 | < 5 |
| **p-value** | < 0.01 | 0.01-0.05 | 0.05-0.10 | > 0.10 |
| **R² (2º est.)** | > 0.50 | 0.30-0.50 | 0.10-0.30 | < 0.10 |

---

## 🎯 Principais Perguntas que Você Pode Responder

### 1. Diferenças Setoriais
**"A ferrovia impactou mais o setor agropecuário ou industrial?"**

Filtro os dados por:
```r
resultados |> 
  filter(escopo %in% c("PIB_Agropecuário", "PIB_Indústria")) |>
  group_by(escopo) |>
  summarise(coef_medio = mean(coeficiente, na.rm = TRUE))
```

### 2. Efeitos de Longo Prazo (Persistência)
**"O efeito de uma ferrovia em 1970 ainda é visível no PIB de 2010?"**

Filtro:
```r
resultados |>
  filter(ano_tratamento == 1970, ano_outcome == 2010)
```

### 3. Efeitos Contemporâneos
**"Qual é o efeito no PIB do mesmo ano da inauguração?"**

Filtro:
```r
resultados |>
  filter(ano_tratamento == ano_outcome)
```

### 4. Impacto em Desenvolvimento Humano
**"A ferrovia mais impactou a renda ou a educação?"**

Filtro:
```r
resultados |>
  filter(escopo %in% c("IDH_Renda", "IDH_Educação")) |>
  group_by(escopo) |>
  summarise(
    n_sig = sum(p_valor < 0.05),
    coef_medio = mean(coeficiente)
  )
```

### 5. Estabilidade Temporal
**"O efeito é consistente ao longo do tempo ou varia?"**

Visualizar com:
```r
resultados |>
  filter(outcome_var == "pib_1980") |>
  ggplot(aes(x = ano_tratamento, y = coeficiente)) +
  geom_line() +
  geom_hline(yintercept = 0, linetype = "dashed")
```

---

## ⚙️ Detalhes Técnicos

### Especificação do Modelo

**Primeiro Estágio:**
```
densidade_buffer_real_YYYY ~ densidade_buffer_sintetica_YYYY + controles | estado
```

**Segundo Estágio:**
```
log(outcome_ZZZZ) ~ fit_densidade_buffer_real_YYYY + controles | estado
```

Onde:
- `YYYY` = ano de inauguração da ferrovia
- `ZZZZ` = ano do outcome observado
- `controles` = clima (bio_1, bio_12, bio_15), rios, solos
- `estado` = efeito fixo de UF (Nordeste)

### Amostra

- **AMCs:** ~650 por ano (após excluir pontas e missing values)
- **Região:** 9 estados do Nordeste (MA, PI, CE, RN, PB, PE, AL, SE, BA)
- **Período de tratamento:** 1858-2003
- **Período de outcomes:** 1920-2022

### Exclusões

1. **Pontas ferroviárias:** AMCs que tiveram ferrovia apenas no ano específico são excluídas
2. **Missing values:** Observações com valores faltantes em endógena, instrumento ou outcomes
3. **Distância restrita:** (opcional) Pode-se filtrar para AMCs a ≤200 km da rede sintética

---

## 📈 Exemplo de Workflow Completo

### Passo a Passo para Publicação

```r
# 1. Rodar análise completa
source("02-scripts/02-analise/second_stage_multidimensional.R")

# 2. Visualizar e tabular
source("02-scripts/03-visualizacao/visualizar_multidimensional.R")

# 3. Explorar resultados
resultados <- read_csv("03-resultados/csv/second_stage_multidimensional_results.csv")

# 4. Identificar efeitos significativos
sig <- resultados |> filter(p_valor < 0.05)
print(sig)

# 5. Criar tabela para paper
sig |>
  select(
    Escopo = escopo,
    Outcome = outcome_var,
    `Ano Trat.` = ano_tratamento,
    Coeficiente = coeficiente,
    `P-valor` = p_valor,
    `F-stat` = F_stat_1estagio,
    N = n_observacoes
  ) |>
  arrange(Escopo, `P-valor`)
```

---

## 🔍 Troubleshooting

### Problema: Poucos resultados significativos

**Solução:**
1. Verifique se o instrumento é forte: `mean(resultados$F_stat_1estagio, na.rm = TRUE)`
2. Veja a distribuição de p-valores: `hist(resultados$p_valor)`
3. Considere expandir a amostra ou relaxar critérios de exclusão

### Problema: Muitos valores NA no F-stat

**Causa:** Alguns outcomes podem ter pouca variação
**Solução:** Filtrar `resultados |> filter(!is.na(F_stat_1estagio))`

### Problema: Resultados muito diferentes do baseline

**Possível causa:** IDH tem apenas 3 anos (1991, 2000, 2010)
**Verificação:** `resultados |> filter(escopo == "IDH_Geral") |> count(ano_outcome)`

---

## 📚 Referências Rápidas

- **Stock & Yogo (2005):** Critério de F > 10 para força de instrumento
- **Wooldridge (2010):** Econometria de cross-section e painel
- **Seu projeto:** Rede sintética LCP como instrumento exógeno

---

## 🤝 Próximos Passos Sugeridos

1. **Robustez:** Rodar com especificações alternativas (polinômio espacial, amostra restrita)
2. **Heterogeneidade:** Testar efeitos por região (Litoral vs. Interior)
3. **Mecanismos:** Investigar por que a ferrovia afeta mais agro ou indústria
4. **Publicação:** Usar as tabelas geradas como base para papers

---

**Última atualização:** Junho 2026
