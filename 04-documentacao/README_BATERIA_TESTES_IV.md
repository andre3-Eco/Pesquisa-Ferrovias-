# 🚀 Bateria Completa de Testes IV (Primeiro e Segundo Estágio)

## 📋 Visão Geral

Estes scripts executam uma **bateria abrangente de análises econométricas IV (2SLS)** para sua pesquisa sobre ferrovias, testando diferentes:

- **Tipos de tratamento**: distância, dummy de atendimento, densidade
- **Outcomes**: população (2003, 2010), PIB (se disponível)
- **Especificações**: amostra completa, com efeitos fixos, com restrições espaciais
- **Restrições amostrais**: excluindo extremidades de ferrovias

---

## 📁 Estrutura dos Scripts

### 1. `6_Bateria_Testes_Etapas_I_II.R` — **SCRIPT PRINCIPAL**

Executa toda a análise IV. O que faz:

✅ Carrega bases integradas (distância, dummy, densidade)  
✅ Prepara dados de outcomes (população, PIB)  
✅ Identifica extremidades das ferrovias  
✅ Executa 1º estágio (forma reduzida) para cada combinação  
✅ Executa 2º estágio (2SLS) com instrumentos  
✅ Exporta resultados em CSV  

**Tempo estimado:** 10-30 minutos (depende da quantidade de dados e outcomes)

**Resultado principal:** `resultados_bateria_iv.csv`

---

### 2. `7_Visualizar_Resultados_IV.R` — **ANÁLISE PÓS-ESTIMAÇÃO**

Cria tabelas, gráficos e análises de robustez com base nos resultados.

O que faz:

✅ Carrega resultados da bateria  
✅ Cria tabelas resumidas por especificação/tratamento  
✅ Gera 4 gráficos principais  
✅ Calcula robustez (efeitos fixos, exclusão de pontas)  
✅ Exporta relatórios HTML  

**Tempo estimado:** 2-5 minutos

**Resultados:**
- `tabela_resultados_por_outcome.html`
- `tabela_resultados_por_tratamento.html`
- `grafico_coeficientes_ss.png`
- `grafico_f_stat.png`
- etc.

---

## 🚀 Como Executar

### Pré-requisitos

Antes de rodar os scripts, execute a preparação de bases:

```r
# Se ainda não criou as bases integradas:
source("0_MASTER_Criar_Todas_Bases.R")
```

Verifique que os seguintes arquivos existem:
- `base_completa_integrada.csv` ← Base com distância, dummy, densidade
- `ferrovias_cronologicas.gpkg` ← Geometria das ferrovias
- `população.xlsx` ← Dados de população
- `tabelaspib.xlsx` ← (Opcional) Dados de PIB

---

### Execução Básica (Recomendado)

```r
# PASSO 1: Executar bateria de testes
source("6_Bateria_Testes_Etapas_I_II.R")

# Aguarde a conclusão (verá feedback no console)
# Isso cria: resultados_bateria_iv.csv
```

```r
# PASSO 2: Analisar e visualizar resultados
source("7_Visualizar_Resultados_IV.R")

# Cria gráficos e tabelas HTML
```

---

## 📊 Entendendo os Resultados

### Arquivo: `resultados_bateria_iv.csv`

Cada linha representa um teste. Colunas principais:

| Coluna | Descrição |
|--------|-----------|
| `especificacao` | Amostra usada (amostra completa, com FE, etc) |
| `tratamento` | Descrição do tratamento (distância, dummy, densidade) |
| `outcome` | Variável dependente (população 2003, etc) |
| `n_obs` | Número de AMCs na regressão |
| `coef_fs` | Coef. do 1º estágio (forma reduzida) |
| `se_fs` | Erro padrão do 1º estágio |
| `f_stat` | F-statístico do 1º estágio ← **Força do instrumento** |
| `r2_fs` | R² do 1º estágio |
| `coef_ss` | **Coeficiente do 2º estágio (efeito causal estimado)** |
| `se_ss` | Erro padrão do 2º estágio |
| `t_stat` | t-estatístico do coeficiente |
| `p_value` | P-value do coeficiente |

---

### Interpretação dos Resultados

#### 1️⃣ **Força do Instrumento** (Coluna `f_stat`)

```
F > 10        : Instrumento forte (OK) ✓
10 ≥ F > 5    : Instrumento moderado (Cuidado) ⚠️
F ≤ 5         : Instrumento fraco (Problemático) ❌
```

Se houver muitos instrumentos fracos, considere:
- Respecificar o instrumento (rede sintética)
- Testar alternativas (dummy, densidade)
- Usar testes robustos como Anderson-Rubin

#### 2️⃣ **Coeficiente do 2º Estágio** (Coluna `coef_ss`)

O efeito causal estimado. Interpretação:

```
coef_ss = 0.15, p_value = 0.023

Interpretação: Um aumento de 1 unidade no tratamento
está associado a um aumento de 15% na população
(significativo a 2.3%)
```

#### 3️⃣ **Robustez dos Resultados**

Compare:
- **Amostra completa** vs **com FE Estado** → efeitos fixos importam?
- **Amostra com ≤200km** vs **excluindo pontas** → seleção amostral importa?

Mudanças grandes = resultado não robusto 🚩

---

## 📈 Especificações Testadas

### Amostra 1: Completa
- Usa todas as ~700 AMCs do Nordeste
- Nenhuma restrição espacial

### Amostra 2: Completa + FE Estado
- Mesma amostra
- Controla por efeitos fixos de estado
- **Recomendado para captar heterogeneidade estadual**

### Amostra 3: ≤200km + FE Estado
- Restringe a AMCs distância ≤ 200 km das ferrovias reais
- Com efeitos fixos
- **Evita AMCs "muito longe" (causalidade duvidosa)**

### Amostra 4: ≤200km + Excluindo Pontas + FE Estado
- Mesma restrição de distância
- **Remove AMCs nas extremidades das ferrovias**
- Com efeitos fixos
- **Mais seletiva, mas evita outliers nas pontas**

---

## 🎯 Tipos de Tratamento

### 1. Distância (km)
```
Variável endógena:  dist_rail_real_2003
Instrumento:        dist_rail_sintetica_km
Descrição:          Distância até ferrovia (km)
Interpretação:      "Um aumento de 1 km de distância reduz população em X%"
```

### 2. Dummy de Atendimento
```
Variável endógena:  dummy_atendida_real_2003
Instrumento:        dummy_atendida_sintetica
Descrição:          1 se ≤25km de ferrovia, 0 caso contrário
Interpretação:      "Estar atendido por ferrovia aumenta população em X%"
```

### 3. Densidade de Ferrovias
```
Variável endógena:  densidade_real_2003
Instrumento:        densidade_sintetica
Descrição:          km de ferrovia por 1000 km² de área
Interpretação:      "Cada 10 km/1000km² de densidade aumenta população em X%"
```

---

## 📊 Outcomes Testados

### Obrigatório
- **População 2003**
- **População 2010**

### Opcional (se arquivo `tabelaspib.xlsx` existir)
- **PIB Total**
- **PIB por setor** (primário, secundário, terciário)

---

## 🔧 Personalizações Possíveis

### Adicionar novo outcome

Abra `6_Bateria_Testes_Etapas_I_II.R` e procure pela seção "outcomes":

```r
outcomes <- list(
  list(
    nome = "populacao_2003",
    variavel = "2003",
    descricao = "População (2003)"
  ),
  
  # ADICIONE AQUI:
  list(
    nome = "densidad_populacional",
    variavel = "densidade_pop",  # nome da coluna na sua base
    descricao = "Densidade populacional"
  )
)
```

### Adicionar nova especificação amostral

Procure pela seção "especificacoes":

```r
especificacoes <- list(
  # ... existentes ...
  
  list(
    nome = "Amostra customizada",
    filtro = "area_km2 > 5000 & dist_rail_real_2003 <= 150",
    efeito_fixo = TRUE,
    label_efeito = " + state_abbr"
  )
)
```

### Mudar limiar de atendimento para dummy

A dummy usa limiar de 25 km. Se quiser mudar (ex: 30 km), edite a base de dummy *antes*:

```r
# Em 2_Criar_Base_Dummy_Atendimento.R, procure:
LIMIAR_KM <- 25  # Mude para 30, 50, etc.
source("2_Criar_Base_Dummy_Atendimento.R")
source("4_Integrar_Bases_Completas.R")  # Re-integrar
source("6_Bateria_Testes_Etapas_I_II.R")  # Re-rodar análises
```

---

## 🐛 Troubleshooting

### Erro: "object 'população' not found"

O objeto 'população' deve estar carregado na sessão. Faça:

```r
library(readxl)
população <- read_excel("população.xlsx")
source("6_Bateria_Testes_Etapas_I_II.R")
```

### Erro: "file not found"

Verifique se está no diretório correto:

```r
getwd()  # Deve apontar para a pasta "Pesquisa (Ferrovias)"
```

Se não, defina manualmente:

```r
data.wd <- "C:/Users/André Elias/Documents/Pesquisa (Ferrovias)"
setwd(data.wd)
```

### Erro: "no columns named"

Significa que a base integrada não tem a coluna esperada. Verifique:

```r
base_completa <- read_csv("base_completa_integrada.csv")
names(base_completa)  # Liste todas as colunas

# Se faltam colunas de dummy ou densidade, re-rode:
source("0_MASTER_Criar_Todas_Bases.R")
```

### Análises lentas

Se o script demora muito:
- Reduzir número de outcomes testados
- Reduzir número de especificações
- Usar amostra menor (ex: filtro mais restritivo)

---

## 📈 Interpretação Econômica

### Exemplo de resultado

```
Especificação: Distância ≤ 200km + FE Estado
Tratamento:    Distância até ferrovia (km)
Outcome:       População (2003)
Resultado:     coef = -0.025, p-value = 0.032, F = 18.5

Interpretação econômica:
- Um aumento de 1 km de distância está associado
  a uma redução de 2.5% na população (significativo a 5%)
- O instrumento (rede sintética) é forte (F = 18.5 >> 10)
- Efeito é robusto e teoricamente plausível
```

---

## 📋 Checklist de Execução

- [ ] Confirmou que `base_completa_integrada.csv` existe
- [ ] Confirmou que `população.xlsx` está no diretório
- [ ] Carregou objeto `população` na sessão (se necessário)
- [ ] Rodou `6_Bateria_Testes_Etapas_I_II.R` com sucesso
- [ ] Gerou arquivo `resultados_bateria_iv.csv`
- [ ] Rodou `7_Visualizar_Resultados_IV.R`
- [ ] Revisou gráficos em PNG
- [ ] Revisou tabelas em HTML
- [ ] Identificou instrumentos fracos (F < 10)
- [ ] Documentou principais achados

---

## 📞 Próximos Passos

1. **Análise de Hetereogeneidade**: Testar efeitos por região/período
2. **Event Study**: Analisar impacto cronológico de inaugurações
3. **Espacial**: Incluir defasagens espaciais do outcome
4. **Dinâmica**: Testar com dados em painel (incluir anos múltiplos)

---

## 📝 Referências

- **IV/2SLS**: Wooldridge (2010) - "Econometric Analysis of Cross Section and Panel Data"
- **Instrumentos Fracos**: Stock & Yogo (2005)
- **Efeitos Fixos Espaciais**: Arbia & Petrarca (2011)

---

**Data de criação:** 2026-05-11  
**Versão:** 1.0  
**Status:** ✅ Pronto para uso
