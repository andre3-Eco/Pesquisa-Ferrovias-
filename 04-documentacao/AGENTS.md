# Pesquisa sobre Impacto de Ferrovias no Desenvolvimento Regional (Nordeste)

## 📋 Informações do Projeto

**Objetivo:** Analisar o impacto causal de infraestrutura ferroviária na população e PIB do Nordeste brasileiro

**Abordagem:** Variáveis Instrumentais (IV/2SLS) com instrumento exógeno (rede sintética LCP)

**Período analisado:** 1858-2003 (com foco em anos censitários 2003, 2010)

**Unidade de análise:** AMCs (Áreas Comparáveis do IBGE) do Nordeste (~700)

---

## 📁 Estrutura das Bases de Dados

### Bases Integradas Principais

1. **`base_completa_integrada.csv`** (Saída principal)
   - Contém: distância, dummy, densidade, outcomes
   - Dimensões: ~700 AMCs × ~1700 colunas
   - Formato: CSV e RDS

2. **Componentes (também disponíveis separadamente):**
   - `base_distancias_amcs_nordeste_semmar.csv` - Distância até ferrovias
   - `base_dummy_atendimento_ferrovias.csv` - Indicador binário de atendimento
   - `base_densidade_ferrovias.csv` - Comprimento de ferrovia por área

### Dados de Outcomes

- `população.xlsx` - Dados municipais agregados para AMC
- `tabelaspib.xlsx` - PIB por setor (opcional)

### Dados Geoespaciais

- `ferrovias_cronologicas.gpkg` - Geometria das ferrovias com datas
- Geometria das AMCs: obtida dinamicamente via `geobr`

---

## 🚀 Scripts de Análise Criados

### 1. `QUICK_START_BATERIA_IV.R` ⭐ **COMECE AQUI**
- Quick start com 2 passos simples
- Executa tudo automaticamente
- ~30-40 minutos

### 2. `6_Bateria_Testes_Etapas_I_II.R` **ANÁLISE PRINCIPAL**
- Executa bateria completa de testes IV
- Testa 4 especificações × 3 tratamentos × 2 outcomes = 24 regressões
- Gera `resultados_bateria_iv.csv`

### 3. `7_Visualizar_Resultados_IV.R` **PÓS-ESTIMAÇÃO**
- Cria tabelas resumidas
- Gera 4 gráficos principais (PNG)
- Exporta tabelas HTML formatadas
- Análise de robustez

---

## 📊 Configurações de Testes

### Especificações Amostrais

1. **Amostra Completa** - Todas as ~700 AMCs
2. **Amostra Completa + FE Estado** - Com efeitos fixos estaduais
3. **Distância ≤200km + FE Estado** - Amostra restrita + FE
4. **Distância ≤200km + Excluindo Pontas + FE** - Mais seletiva

### Tipos de Tratamento

| Tratamento | Variável Endógena | Instrumento | Descrição |
|-----------|-------------------|------------|-----------|
| Distância | `dist_rail_real_2003` | `dist_rail_sintetica_km` | km até ferrovia |
| Dummy | `dummy_atendida_real_2003` | `dummy_atendida_sintetica` | 1 se ≤25km |
| Densidade | `densidade_real_2003` | `densidade_sintetica` | km/1000km² |

### Outcomes

- `2003` - População (2003)
- `2010` - População (2010)
- (PIB - se disponível)

---

## 🔍 Variáveis Principais

### Tratamentos (Endógenos)

- `dist_rail_real_YYYY` - Distância até rede real no ano YYYY
- `dummy_atendida_real_YYYY` - Dummy de atendimento (≤25km)
- `densidade_real_YYYY` - Densidade de ferrovias (km/1000km²)

### Instrumentos (Exógenos)

- `dist_rail_sintetica_km` - Distância até rede sintética LCP (exógena)
- `dummy_atendida_sintetica` - Dummy baseado em rede sintética
- `densidade_sintetica` - Densidade baseada em rede sintética

### Controles Espaciais

- `dist_sintetica_vizinhos` - Lag espacial da distância sintética (vizinhança Queen)
- `state_abbr` - UF (para efeitos fixos)
- `code_amc` - Identificador da AMC

### Outcomes

- `2003`, `2010` - População em censos
- PIB total e setorial (se disponível)

---

## 📈 Interpretação dos Resultados

### Arquivo: `resultados_bateria_iv.csv`

Colunas-chave:

- **`f_stat`** - Força do instrumento (deve ser > 10)
- **`coef_ss`** - Coeficiente causal estimado (2º estágio)
- **`p_value`** - Significância estatística
- **`r2_ss`** - Qualidade do ajuste

### Como Ler

```
coef_ss = 0.15, p_value = 0.032, f_stat = 18.5

→ Aumento de 1 unidade no tratamento = +15% no outcome
→ Significativo a 3.2% (5% é padrão)
→ Instrumento forte (F >> 10)
```

---

## 🛠️ Como Usar os Scripts

### Execução Rápida (Recomendado)

```r
# Tudo em um comando
source("QUICK_START_BATERIA_IV.R")
```

### Execução Manual (Passo a Passo)

```r
# Passo 1: Carregar população
library(readxl)
população <- read_excel("população.xlsx")

# Passo 2: Rodar bateria
source("6_Bateria_Testes_Etapas_I_II.R")

# Passo 3: Visualizar
source("7_Visualizar_Resultados_IV.R")
```

---

## 📊 Saídas Geradas

### CSVs
- `resultados_bateria_iv.csv` - Todos os coeficientes e testes
- `resumo_por_especificacao.csv` - Sumário por amostra
- `resumo_por_tratamento.csv` - Sumário por tipo de tratamento

### Gráficos (PNG)
- `grafico_coeficientes_ss.png` - Box-plot de coeficientes
- `grafico_f_stat.png` - F-statísticos por especificação
- `grafico_p_values.png` - Distribuição de p-values
- `grafico_f_vs_coef.png` - Relação instrumento vs coeficiente

### Tabelas (HTML)
- `tabela_resultados_por_outcome.html`
- `tabela_resultados_por_tratamento.html`
- `tabela_f_estatistico.html`

---

## ⚠️ Considerações Econométricas

### Força do Instrumento
- F > 10: ✓ Forte (recomendado Stock & Yogo 2005)
- 5 ≤ F ≤ 10: ⚠️ Moderado (cuidado)
- F < 5: ❌ Fraco (não confiável)

### Especificação
- Efeitos fixos de estado controlam heterogeneidade regional
- Exclusão de pontas evita outliers em extremidades de ferrovias
- Restrição de distância (≤200km) evita causalidade reversa

### Robustez
- Testar múltiplas especificações
- Comparar com/sem efeitos fixos
- Analisar heterogeneidade

---

## 🔗 Relação com Outros Scripts

### Pré-requisitos
- `0_MASTER_Criar_Todas_Bases.R` ← Gera a base integrada
- Carregamento de `população` ← Necessário na sessão

### Produz
- `resultados_bateria_iv.csv` ← Entrada para `7_Visualizar_Resultados_IV.R`

---

## 📚 Documentação Associada

- `README_BATERIA_TESTES_IV.md` - Documentação completa
- `README_BASES_DADOS.md` - Estrutura das bases
- `Dicionário de Dados Projeto Ferrovi.txt` - Metadados

---

## 🎯 Próximas Etapas Sugeridas

1. **Executar Quick Start** → Obter resultados preliminares
2. **Revisar Força do Instrumento** → Garantir F > 10
3. **Documentar Achados** → Coeficientes significativos
4. **Análise de Robustez** → Verificar estabilidade
5. **Heterogeneidade** → Analisar por subgrupos (região, período)
6. **Event Study** → Impacto cronológico de inaugurações

---

**Última atualização:** 2026-05-11  
**Status:** ✅ Pronto para uso
