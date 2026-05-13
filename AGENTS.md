# Pesquisa: Impacto de Ferrovias no Desenvolvimento Regional (Nordeste)

**Status:** ✅ Projeto organizado em estrutura clara e pronto para análise

---

## 🎯 Visão Geral

**Objetivo:** Analisar o impacto causal de infraestrutura ferroviária na população e PIB do Nordeste brasileiro

**Abordagem:** Variáveis Instrumentais (IV/2SLS) com instrumento exógeno (rede sintética LCP)

**Período:** 1858-2003 (foco em censos 2003, 2010)

**Unidade:** AMCs do Nordeste (~700)

**Metodologia:** 24 regressões (4 especificações × 3 tratamentos × 2 outcomes)

---

## 📁 Estrutura do Projeto (Reorganizada 13/05/2026)

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
│   └── processados/          (19 arquivos: bases integradas, controles)
│
├── 02-scripts/
│   ├── 01-preparacao/        (9 scripts: criar bases)
│   ├── 02-analise/           (3 scripts: 2SLS, análise IV)
│   ├── 03-visualizacao/      (1 script: gráficos e tabelas)
│   └── exploratoria/         (19 scripts: testes e desenvolvimento)
│
├── 03-resultados/
│   ├── csv/                  (resultados_bateria_iv_pib_pop.csv)
│   ├── graficos/             (event_study_did.png)
│   └── tabelas/              (HTML + XLSX formatados)
│
├── 04-documentacao/          (README, guias, dicionários)
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
- `dist_rail_sintetica_km` - Distância até rede sintética LCP
- `dummy_atendida_sintetica` - Dummy baseado em rede sintética
- `densidade_sintetica` - Densidade baseada em rede sintética

### **Outcomes**
- `2003` - População no censo 2003
- `2010` - População no censo 2010

### **Controles**
- `dist_sintetica_vizinhos` - Lag espacial (vizinhança Queen)
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

**Total:** 4 × 3 × 2 = **24 regressões**

---

## 📊 Interpretação dos Resultados

**Arquivo:** `03-resultados/csv/resultados_bateria_iv_pib_pop.csv`

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

---

## 💡 Próximos Passos Sugeridos

1. **Executar Quick Start** → Resultados preliminares (30 min)
2. **Revisar Force do Instrumento** → Garantir F > 10
3. **Análise de Robustez** → Testar especificações alternativas
4. **Heterogeneidade Espacial** → Impactos por região
5. **Event Study** → Impacto temporal de inaugurações ferroviárias
6. **Mecanismos** → Canais de transmissão (comércio, migração)
7. **Externalidades Espaciais** → Spillovers para vizinhos

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

## 📝 Última Atualização

- **Data:** 13 maio 2026
- **Status:** ✅ Projeto reorganizado em estrutura clara
- **Versão:** 2.0 (estrutura de pastas atualizada)
- **Próxima revisão:** Após primeira bateria de análises

---

**Para iniciar:** Abra `README.md` ou execute `QUICK_START_BATERIA_IV.R`
