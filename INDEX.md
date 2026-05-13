# Índice Rápido do Projeto

## 🎯 Para Iniciantes: Comece por AQUI

1. Leia `README.md` (visão geral de 5 min)
2. Execute `02-scripts/02-analise/QUICK_START_BATERIA_IV.R` (30 min)
3. Veja resultados em `03-resultados/`

---

## 📋 Localização Rápida

### Encontrar Dados
| O que? | Onde? |
|--------|-------|
| Dados de população/PIB originais | `01-dados/brutos/` |
| Base processada (principal) | `01-dados/processados/base_completa_integrada.*` |
| Distâncias até ferrovias | `01-dados/processados/base_distancias_*.csv` |
| Geometrias (shapefiles) | `05-geometrias/` |

### Encontrar Scripts
| O que fazer? | Script? | Tempo |
|-------------|---------|-------|
| Processar dados brutos | `02-scripts/01-preparacao/0_MASTER_*.R` | 20 min |
| Rodar análise IV rápido | `02-scripts/02-analise/QUICK_START_*.R` | 30 min |
| Análise completa | `02-scripts/02-analise/6_Bateria_*.R` | 15 min |
| Gráficos e tabelas | `02-scripts/03-visualizacao/7_Visualizar_*.R` | 5 min |

### Encontrar Documentação
| Dúvida? | Arquivo? |
|---------|----------|
| O que há em cada base? | `04-documentacao/README_BASES_DADOS.md` |
| Como funcionam os testes IV? | `04-documentacao/README_BATERIA_TESTES_IV.md` |
| Lista completa de variáveis? | `04-documentacao/Dicionário_de_Dados_*.txt` |
| Guia visual do projeto? | `AGENTS.md` |

### Encontrar Resultados
| Que resultado? | Arquivo? |
|---------------|----------|
| Coeficientes e p-values | `03-resultados/csv/resultados_bateria_iv_*.csv` |
| Tabelas HTML formatadas | `03-resultados/tabelas/*.html` |
| Gráficos (PNG) | `03-resultados/graficos/` |

---

## 🚀 Fluxos de Trabalho

### Workflow 1: Quick Analysis (Ideal para testes rápidos)
```
source("02-scripts/02-analise/QUICK_START_BATERIA_IV.R")
# ↓
# Abre resultados em 01-dados/processados/base_completa_integrada.csv
# Roda 2SLS
# Gera gráficos automáticamente
# DONE em ~30-40 min
```

### Workflow 2: Full Pipeline (Ideal para reprodução completa)
```
1. source("02-scripts/01-preparacao/0_MASTER_Criar_Todas_Bases.R")
   ↓ [cria bases processadas]
2. source("02-scripts/02-analise/6_Bateria_Testes_Etapas_I_II.R")
   ↓ [roda regressões]
3. source("02-scripts/03-visualizacao/7_Visualizar_Resultados_IV.R")
   ↓ [gera visualizações]
   DONE
```

### Workflow 3: Exploração Manual
```
# No console R:
base <- readRDS("01-dados/processados/base_completa_integrada.rds")
# Explorar, testar novas especificações, etc.
```

---

## 📊 Atalhos para Entender Resultados

### Arquivo Principal de Resultados
**`03-resultados/csv/resultados_bateria_iv_pib_pop.csv`**

Colunas importantes:
- `coef_ss` → Coeficiente (2º estágio)
- `p_value` → Significância
- `f_stat` → Força do instrumento
- `n_obs` → Tamanho da amostra
- `especificacao` → Qual amostra
- `tratamento` → Qual variável endógena
- `outcome` → População 2003 ou 2010

### Como Ler um Resultado
```
Linha: distância | amostra completa | população 2003
coef_ss = 0.15, p_value = 0.032, f_stat = 18.5

↓ Tradução: ↓
"Uma redução de 1 km na distância até ferrovia está
associada a +0.15% na população local (2003)"
+ "Significativo a 5% (p < 0.05)"
+ "Instrumento forte (F > 10)"
```

---

## 🔗 Conectando Partes

```
população.xlsx, tabelaspib.xlsx (dados brutos)
        ↓
0_MASTER_Criar_Todas_Bases.R
        ↓
base_completa_integrada.csv (dados processados)
        ↓
QUICK_START_BATERIA_IV.R  OU  6_Bateria_Testes_Etapas_I_II.R
        ↓
resultados_bateria_iv_*.csv
        ↓
7_Visualizar_Resultados_IV.R
        ↓
Gráficos + Tabelas HTML
```

---

## ❓ FAQ Rápido

**P: Por onde começo?**  
R: `02-scripts/02-analise/QUICK_START_BATERIA_IV.R`

**P: Quanto tempo leva?**  
R: Quick Start = 30-40 min. Full pipeline = 60 min.

**P: Preciso reprocessar dados brutos?**  
R: Não, se `01-dados/processados/base_completa_integrada.csv` existe.

**P: Como interpreto F-statístico?**  
R: F > 10 = bom. F < 5 = fraco. Ver `04-documentacao/README_BATERIA_TESTES_IV.md`.

**P: Que variáveis usar como outcomes?**  
R: `2003` ou `2010` (população em censos). PIB também disponível.

**P: Como adicionar novos controles?**  
R: Edite `02-scripts/01-preparacao/4_Integrar_Bases_Completas.R`

---

## 📁 Árvore Visual da Pasta

```
Pesquisa (Ferrovias)/
├─ README.md                ← Comece aqui (visão geral)
├─ INDEX.md                 ← Você está aqui (atalhos rápidos)
├─ AGENTS.md                ← Guia técnico detalhado
│
├─ 01-dados/
│  ├─ brutos/               ← Inputs originais
│  └─ processados/          ← Outputs de preparação
│
├─ 02-scripts/
│  ├─ 01-preparacao/        ← Limpeza e prep de dados
│  ├─ 02-analise/           ← 🚀 RODAR AQUI PRIMEIRO
│  ├─ 03-visualizacao/      ← Gráficos e tabelas
│  └─ exploratoria/         ← Testes e desenvolvimento
│
├─ 03-resultados/
│  ├─ csv/                  ← Coeficientes e testes
│  ├─ graficos/             ← PNG (box-plot, scatter, etc)
│  └─ tabelas/              ← HTML e XLSX formatados
│
├─ 04-documentacao/         ← Ler quando tiver dúvidas
├─ 05-geometrias/           ← Dados geoespaciais (GeoPackage)
└─ 06-anexos/               ← Histórico e logs
```

---

## 🎓 Leitura Sugerida (em ordem)

1. **Este arquivo** (5 min) ← Você está aqui
2. `README.md` (5 min)
3. `AGENTS.md` (10 min) - Visão técnica
4. `04-documentacao/README_BATERIA_TESTES_IV.md` (15 min) - Detalhes econométricos
5. `04-documentacao/README_BASES_DADOS.md` (10 min) - Estrutura de dados

---

## ✅ Checklist Rápido

- [ ] Arquivos na pasta? `ls` para ver
- [ ] RData carregado? Sim (variáveis em memória)
- [ ] Pronto para rodar script? Sim!

```r
# Teste rápido:
setwd("seu_caminho/Pesquisa (Ferrovias)")
source("02-scripts/02-analise/QUICK_START_BATERIA_IV.R")
```

---

**Última atualização:** 13 maio 2026
