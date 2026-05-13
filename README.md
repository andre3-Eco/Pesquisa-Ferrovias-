# Pesquisa: Impacto de Ferrovias no Desenvolvimento Regional (Nordeste)

## 📂 Estrutura do Projeto

```
Pesquisa (Ferrovias)/
│
├── 01-dados/
│   ├── brutos/                          # Dados originais (não processados)
│   │   ├── população.xlsx               # Dados de população por município
│   │   ├── tabelaspib.xlsx              # Dados de PIB setorial
│   │   └── ...
│   │
│   └── processados/                     # Outputs de scripts de preparação
│       ├── base_completa_integrada.*    # Base principal integrada (CSV + RDS)
│       ├── base_distancias_*.csv        # Bases de distância até ferrovias
│       ├── base_dummy_atendimento_*.csv # Indicadores binários de atendimento
│       ├── base_densidade_*.csv         # Densidade de ferrovias
│       ├── controles_*.csv/.rds         # Controles geográficos (clima, solo, rios)
│       └── ...
│
├── 02-scripts/
│   ├── 01-preparacao/                   # Scripts de limpeza e processamento
│   │   ├── 0_MASTER_Criar_Todas_Bases.R        # ⭐ COMECE AQUI
│   │   ├── 1_Criar_Base_Distancias.R
│   │   ├── 2_Criar_Base_Dummy_Atendimento.R
│   │   ├── 3_Criar_Base_Densidade_Ferrovias.R
│   │   ├── 4_Integrar_Bases_Completas.R
│   │   └── 5_Adicionar_State_Abbr.R
│   │
│   ├── 02-analise/                      # Scripts de modelagem econométrica
│   │   ├── QUICK_START_BATERIA_IV.R     # 🚀 Rápido (30-40 min)
│   │   ├── 6_Bateria_Testes_Etapas_I_II.R
│   │   └── 8_Bateria_Completa_PIB_Pop.R
│   │
│   ├── 03-visualizacao/                 # Scripts de gráficos e tabelas
│   │   └── 7_Visualizar_Resultados_IV.R
│   │
│   └── exploratoria/                    # Scripts de desenvolvimento (EDA, testes)
│       ├── API opentopography01.R
│       ├── IV_Analise_Completa_SemMar.R
│       └── ... (outros scripts de testes)
│
├── 03-resultados/
│   ├── csv/                             # Saídas em CSV
│   │   └── resultados_bateria_iv_pib_pop.csv
│   │
│   ├── graficos/                        # Gráficos (PNG)
│   │   └── event_study_did.png
│   │
│   └── tabelas/                         # Tabelas formatadas (HTML, XLSX)
│       ├── Tabela1_PrimeirosEstagios.html
│       ├── Tabela2_ResultadosPrincipais.html
│       ├── Tabela3_Robustez.html
│       └── Resultados_Regressoes_Ferrovias.xlsx
│
├── 04-documentacao/
│   ├── README_BASES_DADOS.md            # Estrutura e schema das bases
│   ├── README_BATERIA_TESTES_IV.md      # Detalhes dos testes IV
│   ├── INDICE_COMPLETO.md               # Índice completo de referência
│   ├── Dicionário de Dados Projeto Ferrovi.txt
│   └── ... (guias e checklists)
│
├── 05-geometrias/                       # Dados geoespaciais (GeoPackage)
│   ├── ferrovias_cronologicas.gpkg      # Rede ferroviária com datas
│   ├── Variavel_Instrumental_LCP_*.gpkg # Redes sintéticas LCP
│   └── Rotas_*.gpkg                     # Rotas O-D (real e sintética)
│
├── 06-anexos/                           # Arquivos temporários, logs, conversas
│   ├── conversation-export*.md
│   └── ... (histórico e backups)
│
├── AGENTS.md                            # 📌 Guia do projeto (v2 - atual)
├── README.md                            # Este arquivo
└── Pesquisa (Ferrovias).Rproj           # Projeto RStudio
```

---

## 🚀 Como Começar

### Opção 1: Quick Start (Recomendado - 30-40 minutos)

```r
# No RStudio, execute:
setwd("seu_caminho/Pesquisa (Ferrovias)")
source("02-scripts/02-analise/QUICK_START_BATERIA_IV.R")
```

**O que faz:**
1. Carrega a base integrada (dados já processados)
2. Executa bateria de testes IV (2SLS)
3. Gera tabelas e gráficos de resultados

---

### Opção 2: Passo a Passo (Completo)

#### **Passo 1: Preparar dados** (~20 min)
```r
source("02-scripts/01-preparacao/0_MASTER_Criar_Todas_Bases.R")
```
Cria:
- `base_distancias_amcs_nordeste_semmar.csv`
- `base_dummy_atendimento_ferrovias.csv`
- `base_densidade_ferrovias.csv`
- `base_completa_integrada.csv` ← Base principal

#### **Passo 2: Rodar análise IV** (~15 min)
```r
source("02-scripts/02-analise/6_Bateria_Testes_Etapas_I_II.R")
```
Cria:
- `03-resultados/csv/resultados_bateria_iv.csv`

#### **Passo 3: Visualizar resultados** (~5 min)
```r
source("02-scripts/03-visualizacao/7_Visualizar_Resultados_IV.R")
```
Cria:
- Gráficos em `03-resultados/graficos/`
- Tabelas em `03-resultados/tabelas/`

---

## 📊 Dados Principais

### Base Integrada
- **Arquivo:** `01-dados/processados/base_completa_integrada.csv`
- **Dimensões:** ~700 AMCs × ~1700 colunas
- **Variáveis chave:**
  - Tratamentos: `dist_rail_real_*`, `dummy_atendida_real_*`, `densidade_real_*`
  - Instrumentos: `dist_rail_sintetica_km`, `dummy_atendida_sintetica`, `densidade_sintetica`
  - Outcomes: `2003`, `2010` (população em censos)
  - Controles: clima, solo, rios, estado

### Métodologia
- **Abordagem:** Variáveis Instrumentais (2SLS)
- **Instrumento:** Rede ferroviária sintética (LCP - Least-Cost Path)
- **Período:** 1858-2003 (foco em 2003, 2010)
- **Unidade:** AMCs do Nordeste

---

## 📈 Interpretação dos Resultados

Veja `03-resultados/csv/resultados_bateria_iv_pib_pop.csv`:

```
Exemplo:
coef_ss = 0.15
p_value = 0.032
f_stat = 18.5

Interpretação:
→ Aumento de 1 km de ferrovia ≈ +15% na população local
→ Significativo a p < 5%
→ Instrumento forte (F >> 10)
```

**Leitura detalhada:** `04-documentacao/README_BATERIA_TESTES_IV.md`

---

## 📚 Documentação

| Arquivo | Conteúdo |
|---------|----------|
| `04-documentacao/README_BASES_DADOS.md` | Schema e estrutura das bases |
| `04-documentacao/README_BATERIA_TESTES_IV.md` | Detalhe técnico dos testes |
| `04-documentacao/INDICE_COMPLETO.md` | Referência completa |
| `AGENTS.md` | Guia do projeto (projeto atual) |

---

## 🔍 Estrutura de Testes

Bateria executa **24 regressões**:

```
4 Especificações (amostrais) ×
3 Tratamentos (distância/dummy/densidade) ×
2 Outcomes (população 2003, 2010)
```

### Especificações
1. Amostra Completa
2. Amostra Completa + FE Estado
3. Distância ≤200km + FE Estado
4. Distância ≤200km + Excluindo Pontas + FE

### Tratamentos
- **Distância:** km até ferrovia
- **Dummy:** 1 se ≤25km
- **Densidade:** km de ferrovia / 1000 km²

---

## ⚙️ Configurações Técnicas

### R Packages Necessários
```r
tidyverse, sf, fixest, tictoc, readxl, 
ggplot2, broom, purrr, stringr
```

### Estimações
- **1º Estágio:** Regressão da variável endógena no instrumento
- **2º Estágio:** Regressão do outcome na variável endógena predita
- **Teste F:** Força do instrumento (Stock & Yogo 2005)

---

## 💡 Próximas Análises Sugeridas

1. ✅ **Robustez** → Diferentes especificações (já feito)
2. ⏳ **Heterogeneidade** → Impactos por região/período
3. ⏳ **Event Study** → Impacto temporal de inaugurações
4. ⏳ **Mecanismos** → Por qual canal (comércio, migração, etc)?
5. ⏳ **Externalidades espaciais** → Spillovers para municípios vizinhos

---

## 📞 Contato / Suporte

Para dúvidas sobre:
- **Dados:** Ver `01-dados/` e `04-documentacao/`
- **Scripts:** Ver comentários nos arquivos `.R`
- **Resultados:** Ver `03-resultados/` e `AGENTS.md`

---

**Última atualização:** 13 maio 2026  
**Status:** ✅ Projeto estruturado e pronto para uso  
**Versão:** 2.0 (estrutura reorganizada)
