# Pesquisa: Impacto de Ferrovias no Desenvolvimento Regional (Nordeste)

**Status:** ✅ Projeto organizado em estrutura clara e pronto para análise

---

## 🎯 Visão Geral

**Objetivo:** Analisar o impacto causal de infraestrutura ferroviária na população e PIB do Nordeste brasileiro

**Abordagem:** Variáveis Instrumentais (IV/2SLS) com instrumento exógeno (rede sintética LCP)

**Período:** 1858-2003 (foco em censos 2003, 2010)

**Unidade:** AMCs do Nordeste (~700)

**Metodologia:** 24 regressões (4 especificações × 3 tratamentos × 2 outcomes) + análises de persistência histórica e testes por ano

---

## 📁 Estrutura do Projeto (Atualizada 27/05/2026)

```
Pesquisa (Ferrovias)/
│
├── 📖 README.md              ← COMECE AQUI (visão geral)
├── 🔍 INDEX.md               ← Atalhos rápidos e FAQ
├── 📋 ESTRUTURA_VISUAL.txt   ← Guia visual com flowcharts
├── 📚 AGENTS.md              ← Este arquivo (referência técnica)
│
├── 01-dados/
│   ├── brutos/               (4 arquivos: população, PIB, etc)
│   └── processados/          (25+ arquivos: bases integradas, controles, interpolados, sintéticos)
│
├── 02-scripts/
│   ├── 01-preparacao/        (9 scripts: criar bases)
│   ├── 02-analise/           (3 scripts: 2SLS, análise IV)
│   ├── 03-visualizacao/      (1 script: gráficos e tabelas)
│   └── exploratoria/         (24+ scripts: testes e desenvolvimento)
│
├── 03-resultados/
│   ├── csv/                  (resultados_bateria_iv_pib_pop.csv, first_stage_sintetica_vs_real_por_ano.csv, etc.)
│   ├── graficos/             (event_study_did.png, heatmap_*.png)
│   └── tabelas/              (HTML + XLSX formatados)
│
├── 04-documentacao/          (README, guias, dicionários, DATA_DICTIONARIES.md)
├── 05-geometrias/            (GeoPackage com dados espaciais)
└── 06-anexos/                (histórico, logs, conversas)
```

---

## 🚀 Como Começar

### **Opção 1: Quick Start (Recomendado)** ⭐

```r
source("02-scripts/02-analise/QUICK_START_BATERIA_IV.R")
```

**Tempo:** 30-40 minutos  
**O que faz:** Carrega base, roda 2SLS, gera gráficos  
**Saída:** `03-resultados/csv/resultados_bateria_iv_pib_pop.csv`

---

### **Opção 2: Pipeline Completo**

```r
# Passo 1: Preparar dados (se necessário)
source("02-scripts/01-preparacao/0_MASTER_Criar_Todas_Bases.R")
# → Cria base_completa_integrada.csv

# Passo 2: Rodar análise IV
source("02-scripts/02-analise/6_Bateria_Testes_Etapas_I_II.R")
# → Gera resultados_bateria_iv.csv

# Passo 3: Visualizar
source("02-scripts/03-visualizacao/7_Visualizar_Resultados_IV.R")
# → Gera gráficos e tabelas
```

**Tempo total:** 50-60 minutos

---

## 📊 Base Principal de Dados

**Arquivo:** `01-dados/processados/base_completa_integrada.csv` (ou `.rds`)

**Dimensões:** ~700 AMCs × ~1700 variáveis

**Contém:**
- Distâncias até ferrovias (real + sintética)
- Indicadores de atendimento (dummy)
- Densidade de ferrovias
- Outcomes: população 2003 e 2010
- Controles: clima, solo, rios
- Efeitos fixos: estado

**Carregar em R:**
```r
base <- readRDS("01-dados/processados/base_completa_integrada.rds")
# ou
base <- read.csv("01-dados/processados/base_completa_integrada.csv")
```

---

## 🔧 Variáveis Principais

### **Tratamentos (Endógenos)**
- `dist_rail_real_YYYY` - Distância até rede real no ano YYYY
- `dummy_atendida_real_YYYY` - Dummy: 1 se ≤25km da ferrovia
- `densidade_real_YYYY` - Densidade: km de ferrovia / 1000 km²

### **Instrumentos (Exógenos)**
- `dist_rail_sintetica_km` - Distância até rede sintética LCP (time-invariant)
- `dummy_atendida_sintetica` - Dummy baseado em rede sintética (time-invariant)
- `densidade_sintetica` - Densidade baseada em rede sintética (time-invariant)
- `dist_rail_sintetica_YYYY` - Distância até rede sintética acumulada até ano YYYY (from CRIAR_BASE_SINTETICA_CRONOLOGICA.R)
- `dummy_atendida_sintetica_YYYY` - Dummy sintético por ano
- `densidade_sintetica_YYYY` - Densidade sintética por ano

### **Outcomes**
- `2003` - População no censo 2003
- `2010` - População no censo 2010
- Outcomes interpolados: `pib_1920`, `pib_1939`, `pib_1949`, `pib_1959`, etc. (from SPATIAL_INTERPOLACAO_OUTCOMES.R)

### **Controles**
- `dist_sintetica_vizinhos` - Lag espacial (vizinhança Queen) da distância sintética
- Variáveis de clima, solo, rios
- `state_abbr` - UF (para efeitos fixos)

---

## 📈 Especificações de Teste

### **Amostras (4)**
1. Amostra Completa (~700 AMCs)
2. Amostra Completa + FE Estado
3. Distância ≤200km + FE Estado
4. Distância ≤200km + Excluindo Pontas + FE

### **Tratamentos (3)**
| Variável | Tipo | Intervalo |
|----------|------|-----------|
| Distância | Contínua | 0-2000 km |
| Dummy | Binária | 0 ou 1 |
| Densidade | Contínua | 0-100 km/1000km² |

### **Outcomes (2)**
- População 2003
- População 2010

**Total:** 4 × 3 × 2 = **24 regressões** (básica IV/2SLS)

---

## 📊 Interpretação dos Resultados

**Arquivo Principal:** `03-resultados/csv/resultados_bateria_iv_pib_pop.csv`

**Colunas-chave:**
- `coef_ss` - Coeficiente (2º estágio)
- `p_value` - Significância
- `f_stat` - F-statístico (força do instrumento)
- `r2_ss` - R² do 2º estágio
- `n_obs` - Tamanho da amostra
- `especificacao` - Qual especificação
- `tratamento` - Qual variável endógena
- `outcome` - Qual outcome (população 2003 ou 2010)

### **Exemplo de Leitura**

```
Especificação: Amostra Completa + FE Estado
Tratamento: Distância até ferrovia
Outcome: População 2003
─────────────────────────────────
coef_ss = 0.15
p_value = 0.032
f_stat = 18.5
n_obs = 700

INTERPRETAÇÃO:
→ Uma redução de 1 km na distância está associada a +0.15% na população
→ Significativo a 5% (p = 0.032 < 0.05)
→ Instrumento forte (F = 18.5 > 10)
→ Baseado em ~700 AMCs
```

### **Critérios de Qualidade**

| Métrica | Bom | Aceitável | Ruim |
|---------|-----|-----------|------|
| F-stat | > 10 | 5-10 | < 5 |
| p-value | < 0.05 | 0.05-0.10 | > 0.10 |
| R² (2º estágio) | > 0.30 | 0.10-0.30 | < 0.10 |

---

## 🔍 Estrutura de Scripts

### **01-preparacao/** (Antes de rodar análise)

| Script | O que faz | Saída |
|--------|-----------|-------|
| `0_MASTER_Criar_Todas_Bases.R` | Executa tudo | base_completa_integrada.* |
| `1_Criar_Base_Distancias.R` | Calcula distâncias | base_distancias_*.csv |
| `2_Criar_Base_Dummy_Atendimento.R` | Cria dummies | base_dummy_*.csv |
| `3_Criar_Base_Densidade_Ferrovias.R` | Calcula densidade | base_densidade_*.csv |
| `4_Integrar_Bases_Completas.R` | Integra tudo | base_completa_integrada.csv |

### **02-analise/** (Análise econométrica)

| Script | O que faz | Tempo | Saída |
|--------|-----------|-------|-------|
| `QUICK_START_BATERIA_IV.R` | IV rápido | 30-40 min | Gráficos automáticos |
| `6_Bateria_Testes_Etapas_I_II.R` | IV completo | 15 min | resultados_bateria_iv.csv |
| `8_Bateria_Completa_PIB_Pop.R` | IV com PIB | 20 min | resultados_pib_pop.csv |

### **03-visualizacao/** (Pós-estimação)

| Script | Cria |
|--------|------|
| `7_Visualizar_Resultados_IV.R` | Gráficos PNG + Tabelas HTML |

### **02-scripts/exploratoria/** (Testes e desenvolvimento - NOVOS)

| Script | O que faz | Tempo | Saída |
|--------|-----------|-------|-------|
| `SPATIAL_INTERPOLACAO_OUTCOMES.R` | Interpola valores faltantes em outcomes históricos usando IDW | 10-15 min | `01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.*` |
| `CRIAR_BASE_SINTETICA_CRONOLOGICA.R` | Cria variáveis sintéticas por ano (dist, dummy, dens, compr) | 20-30 min | `01-dados/processados/base_sintetica_cronologica.*` |
| `FIRST_STAGE_SYNTHETIC_VS_REAL_BY_YEAR.R` | Primeira etapa: sintético → real por ano | 15-20 min | `03-resultados/csv/first_stage_sintetica_vs_real_por_ano.csv` |
| `SECOND_STAGE_PIB_YEARLY_TREATMENT.R` | Segunda etapa: PIB ~ tratamentos sintéticos por ano | 20-25 min | `03-resultados/csv/second_stage_pib_tratamentos_sinteticos_por_ano.csv` |
| `PERSISTENCIA_SEM_PONTAS.R` | Análise de persistência: PIB_2010 ~ tratamentos sintéticos históricos (sem pontas) | 10-15 min | `03-resultados/csv/second_stage_persistencia_pib2010_sem_pontas.csv` |
| `testefirststage.R` | Diagnóstico do primeiro estágio (versão original) | 5 min | console output |
| `PERSISTÊNCIA HISTÓRICA.R` | Impacto de longo prazo (versão original) | 10 min | `03-resultados/csv/second_stage_persistencia_pib2010.csv` |
| `SElimiares.R` | Testa diferentes limiares de distância (dummy 1969) | 15 min | `03-resultados/csv/resultados_2estagio_limiares_dummy_1969.csv` |

---

## 📚 Documentação

| Arquivo | Para quem | Tempo |
|---------|-----------|-------|
| `README.md` | Iniciantes | 5 min |
| `INDEX.md` | Todos (atalhos) | 3 min |
| `ESTRUTURA_VISUAL.txt` | Entender fluxo | 5 min |
| `04-documentacao/README_BASES_DADOS.md` | Detalhes das bases | 10 min |
| `04-documentacao/README_BATERIA_TESTES_IV.md` | Econometria | 15 min |
| `04-documentacao/INDICE_COMPLETO.md` | Referência | 20 min |
| `04-documentacao/DATA_DICTIONARIES.md` | Dicionário completo das variáveis | 15 min |

---

## ⚙️ Configurações Técnicas

### **Pacotes R Necessários**
```r
tidyverse      # dplyr, ggplot2, readr, stringr
sf             # dados geoespaciais
fixest         # regressões IV (2SLS)
readxl         # Excel
broom          # limpar outputs de modelos
purrr          # functional programming
spdep          # lag espacial
gstat          # interpolação IDW (novos scripts)
viridis        # paletas de cores para mapas
patchwork      # combinar gráficos
```

### **Metodologia Estatística**

**1º Estágio (First Stage):**
```
y_endógena ~ z_instrumento + controles
```

**2º Estágio (Second Stage):**
```
y_outcome ~ y_endógena_predito + controles
```

**Teste de Força:**
- F > 10: Instrumento forte ✅
- 5 ≤ F ≤ 10: Moderado ⚠️
- F < 5: Fraco ❌

**Teste de Exogeneidade:**
- Teste de Sargan (se múltiplos instrumentos)
- Discussão teórica da exogeneidade da rede sintética

---

## 🔗 Fluxo de Dados

```
01-dados/brutos/
├─ população.xlsx
└─ tabelaspib.xlsx
        ↓
02-scripts/01-preparacao/
├─ 0_MASTER_Criar_Todas_Bases.R
├─ 1_Criar_Base_Distancias.R
├─ 2_Criar_Base_Dummy_Atendimento.R
├─ 3_Criar_Base_Densidade_Ferrovias.R
└─ 4_Integrar_Bases_Completas.R
        ↓
01-dados/processados/
└─ base_completa_integrada.csv/rds
        ↓
02-scripts/02-analise/
├─ QUICK_START_BATERIA_IV.R
├─ 6_Bateria_Testes_Etapas_I_II.R
└─ 8_Bateria_Completa_PIB_Pop.R
        ↓
03-resultados/csv/
└─ resultados_bateria_iv_pib_pop.csv
        ↓
02-scripts/03-visualizacao/
└─ 7_Visualizar_Resultados_IV.R
        ↓
03-resultados/
├─ graficos/ (PNG)
└─ tabelas/ (HTML, XLSX)
```

**Novos fluxos de dados:**

*Interpolacão de Outcomes:*
```
outcomes_amc_wide.csv
        ↓
SPATIAL_INTERPOLACAO_OUTCOMES.R
        ↓
outcomes/outcomes_amc_ne_interpolado.*
```

*Variáveis Sintéticas por Ano:*
```
Rotas_LCP_OD_Real.gpkg
        ↓
CRIAR_BASE_SINTETICA_CRONOLOGICA.R
        ↓
base_sintetica_cronologica.*
```

*Análise de Primeiro Estágio por Ano:*
```
base_completa_integrada.* + base_sintetica_cronologica.*
        ↓
FIRST_STAGE_SYNTHETIC_VS_REAL_BY_YEAR.R
        ↓
first_stage_sintetica_vs_real_por_ano.csv
```

*Análise de Segundo Estágio por Ano:*
```
outcomes/outcomes_amc_ne_interpolado.* + base_sintetica_cronologica.*
        ↓
SECOND_STAGE_PIB_YEARLY_TREATMENT.R
        ↓
second_stage_pib_tratamentos_sinteticos_por_ano.csv
```

*Análise de Persistência (Sem Pontas):*
```
outcomes/outcomes_amc_ne_interpolado.* + base_sintetica_cronologica.* + amcs_geometria.rds
        ↓
PERSISTENCIA_SEM_PONTAS.R
        ↓
second_stage_persistencia_pib2010_sem_pontas.csv
```

---

## 💡 Próximos Passos Sugeridos

### **CURTO PRAZO (Baseado em Replication Package)**
1. **Adicionar polinômio espacial** → Controlar gradientes (GUIA §5.2)
2. **Testar instrumento fake** → Validar exogeneidade (GUIA §8)
3. **Compilar F-stats em tabela** → Transparência (GUIA §7.2)
4. **Rodar replication.R** → Benchmark (GUIA §1)

### **MÉDIO PRAZO**
5. **Análise de Robustez** → Especificações alternativas
6. **Event Study** → Impacto temporal de inaugurações (seu projeto pode inovar!)
7. **Spillovers espaciais** → Externalidades (você já tem vizinhos_esp!)

### **LONGO PRAZO**
8. **Heterogeneidade Espacial** → Impactos por região
9. **Mecanismos** → Canais de transmissão (comércio, migração)
10. **Integração PIB sectorial** → Seu projeto é mais rico que replication!

---

## ⚠️ Considerações Importantes

### **Força do Instrumento**
A rede sintética (LCP) deve ter F > 10 para ser considerada forte. Se F < 5, os resultados são enviesados.

### **Especificação**
- Efeitos fixos de estado controlam heterogeneidade regional
- Restrição de distância (≤200km) evita causalidade reversa
- Exclusão de pontas evita outliers em extremidades

### **Identificação**
- Pressuposição: rede sintética é exógena (histórica e não correlacionada com choques atuais)
- Rede real pode ser endógena (investimentos direcionados a áreas específicas)

---

## 📞 Referências Rápidas

**Stock & Yogo (2005):**
- Crítica de F > 10 para instrumentos fortes
- Cálculo de viés relativo

**Wooldridge (2010):**
- Econometria de cross-section
- Testes de endogeneidade

**Baum, Schaffer & Stillman (2007):**
- Comando `ivreg2` (Stata) / `fixest` (R)
- Diagnósticos IV

---

## 📚 Análise de Replication Package (14 maio 2026)

**Benchmark encontrado:** "Old But Gold: Colonial Roads and Persistence of Agglomeration in Brazil" (Journal of Urban Economics)

**Compatibilidade:** ALTA ✅
- Mesmo método IV/2SLS
- Mesmo software fixest
- Múltiplas amostras (seu projeto melhor: 4 vs. 2)
- PIB como outcome (seu projeto mais rico)

**Documentação gerada (4 arquivos):**
1. `RELATORIO_REPLICATION_PACKAGE.md` (20 min) - Visão geral
2. `GUIA_PRATICO_INTEGRACAO.md` (60 min) - Implementação passo-a-passo
3. `TABELA_COMPARATIVA.md` (10 min) - Quick reference
4. `INDICE_REPLICATION_PACKAGE.md` (5 min) - Navigation

**Localização dados:** `C:\Users\André Elias\Documents\replication-package`

**Recomendações:**
- Implementar melhorias (8-12h): polinômio espacial, fake IV, F-stats
- Seu projeto está metodologicamente correto!
- Tempo bem investido: validação + publicabilidade

---

## 📝 Última Atualização

- **Data:** 27 maio 2026
- **Status:** ✅ Projeto sólido + Novas análises de interpolação, variáveis sintéticas por ano e persistência
- **Versão:** 2.2 (expansão de análises temporais)
- **Próxima revisão:** Após validação dos novos scripts (1-2 semanas)

---

## 📖 Dicionário de Dados

Ver arquivo completo em: `04-documentacao/DATA_DICTIONARIES.md`

Resumo das principais bases:

### **base_completa_integrada.***
- Variáveis principais para análise IV/2SLS tradicional
- ~1700 colunas incluindo distâncias, dummies, densidades reais e sintéticas (time-invariant)
- Outcomes: população 2003, 2010
- Controles: clima, solo, rios, estado

### **outcomes_amc_ne_interpolado.* (NOVO)**
- PIB e outros outcomes interpolados para anos históricos (1920-2010)
- Inclui variáveis como: pib_1920, pib_1939, pib_1949, pib_1959, pibi_*, pibag_*, pibse_*, pibg_*
- Valores faltantes preenchidos usando interpolação inversa da distância ponderada (IDW)
- Base para análises de PIB ao longo do tempo

### **base_sintetica_cronologica.* (NOVO)**
- Variáveis sintéticas por ano de inauguração (1858-2003)
- Para cada ano: dist_rail_sintetica_YYYY, dummy_atendida_sintetica_YYYY, densidade_sintetica_YYYY, comprimento_sintetico_YYYY
- Permite analisar o efeito instrumental ao longo do tempo
- Criada a partir de Rotas_LCP_OD_Real.gpkg

### **first_stage_sintetica_vs_real_por_ano.csv (NOVO)**
- Resultados da primeira etapa: real_Y ~ sintético + controles | estado
- Mostra F-statistic para cada ano e tratamento (distância, dummy, densidade)
- Indica em quais anos o instrumento sintético é forte o suficiente

### **second_stage_pib_tratamentos_sinteticos_por_ano.csv (NOVO)**
- Resultados da segunda etapa: PIB_Y ~ tratamento sintético_Y + controles | estado
- Efeitos dos tratamentos sintéticos anuais no PIB do mesmo ano
- Disponível para dummy e densidade

### **second_stage_persistencia_pib2010_sem_pontas.csv (NOVO)**
- Análise de persistência: log(pib_2010) ~ tratamento sintético_Y + controles | estado
- Para cada ano Y, mostra o efeito histórico do tratamento sintético no PIB de 2010
- Remove AMCs das pontas (como nas análises SELIMIARES.R)
- Permite ver se efeitos históricos de ferrovias persistem até 2010

---