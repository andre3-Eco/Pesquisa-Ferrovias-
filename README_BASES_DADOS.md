# Criação de Bases de Dados Analíticas para Análise IV

## 📋 Visão Geral

Este conjunto de scripts cria **4 bases de dados analíticas** para análises econométricas sobre infraestrutura ferroviária no Nordeste do Brasil:

1. **Base de Distâncias** - Distância de cada AMC até ferrovias
2. **Base de Dummy** - Indicador binário de atendimento por ferrovia
3. **Base de Densidade** - Comprimento de ferrovia por unidade de área
4. **Base Integrada** - Todas as três bases unidas em uma única tabela

---

## 🚀 Como Usar

### Opção 1: Executar Tudo Automaticamente (Recomendado)

```r
# Execute este script único:
source("0_MASTER_Criar_Todas_Bases.R")

# Aguarde a conclusão (tempo: ~30-60 minutos, dependendo do processamento de densidade)
```

O script master irá:
- ✅ Executar os 4 scripts de criação sequencialmente
- ✅ Criar 8 arquivos de saída
- ✅ Reportar tempo de processamento
- ✅ Listar todos os arquivos gerados

### Opção 2: Executar Scripts Individualmente

Se preferir executar manualmente, na ordem:

```r
# 1. Criar base de distâncias (~5 minutos)
source("1_Criar_Base_Distancias.R")

# 2. Criar base de dummy (~10 minutos)
source("2_Criar_Base_Dummy_Atendimento.R")

# 3. Criar base de densidade (~30-40 minutos - é a mais pesada)
source("3_Criar_Base_Densidade_Ferrovias.R")

# 4. Integrar tudo (~1 minuto)
source("4_Integrar_Bases_Completas.R")
```

---

## 📊 Descrição das Bases

### 1️⃣ Base de Distâncias: `base_distancias_amcs_nordeste_semmar.csv`

**Propósito:** Medir proximidade de cada AMC à infraestrutura ferroviária

| Variável | Tipo | Descrição |
|----------|------|-----------|
| `code_amc` | int | Identificador único da AMC |
| `dist_rail_sintetica_km` | float | Distância (km) até rede sintética LCP |
| `dist_rail_real_YYYY` | float | Distância (km) até rede real acumulada até ano YYYY |

**Características:**
- Uma linha por AMC
- Coluna sintética é **estática** (não muda ao longo do tempo)
- Colunas reais são **cronológicas** (acumulam conforme ferrovias são inauguradas)
- Anos representados: 1858 a 2003 (todos os anos com inaugurações registradas)

**Exemplo de uso:**
```r
base_dist <- read.csv("base_distancias_amcs_nordeste_semmar.csv")
head(base_dist)
# Visualizar evolução da cobertura
plot(as.numeric(gsub("dist_rail_real_", "", 
     grep("dist_rail_real", names(base_dist), value = TRUE))),
     colMeans(base_dist[, grep("dist_rail_real", names(base_dist))]))
```

---

### 2️⃣ Base de Dummy: `base_dummy_atendimento_ferrovias.csv`

**Propósito:** Indicador binário (0/1) de se uma AMC é "atendida" por ferrovia

| Variável | Tipo | Descrição |
|----------|------|-----------|
| `code_amc` | int | Identificador único da AMC |
| `dummy_atendida_sintetica` | int | 1 se distância ≤ 25 km (sintética) |
| `cobertura_continua_sintetica` | float | Inverso da distância (medida contínua) |
| `dummy_atendida_real_YYYY` | int | 1 se distância ≤ 25 km (real, até YYYY) |
| `cobertura_continua_real_YYYY` | float | Inverso da distância (real, até YYYY) |

**Características:**
- Limiar de atendimento: **25 km** (ajustável)
- Inclui medida contínua alternativa (inversa da distância)
- Dois arquivos:
  - `base_dummy_atendimento_ferrovias.csv` (completo, com medidas contínuas)
  - `base_dummy_atendimento_simples.csv` (apenas dummies)

**Interpretação:**
```
dummy = 1: AMC está a ≤ 25 km de ferrovia (atendida)
dummy = 0: AMC está a > 25 km de ferrovia (não atendida)
```

**Exemplo de uso:**
```r
# Para análise causal simples:
base_dummy <- read.csv("base_dummy_atendimento_simples.csv")
lm(log(y_2003) ~ dummy_atendida_real_2003, data = base_dummy)

# Para análise com medida contínua:
base_dummy_cont <- read.csv("base_dummy_atendimento_ferrovias.csv")
lm(log(y_2003) ~ cobertura_continua_real_2003, data = base_dummy_cont)
```

---

### 3️⃣ Base de Densidade: `base_densidade_ferrovias.csv`

**Propósito:** Medir intensidade de infraestrutura ferroviária em cada AMC

| Variável | Tipo | Descrição |
|----------|------|-----------|
| `code_amc` | int | Identificador único da AMC |
| `area_km2` | float | Área da AMC em km² |
| `comprimento_sintetico_km` | float | km de ferrovia sintética na AMC |
| `densidade_sintetica` | float | km sintética por 1000 km² |
| `comprimento_real_YYYY` | float | km de ferrovia real (até YYYY) na AMC |
| `densidade_real_YYYY` | float | km real por 1000 km² (até YYYY) |

**Características:**
- Medidas em **valores absolutos** (km) e **normalizados** (por 1000 km²)
- Normalização permite comparação entre AMCs de tamanhos diferentes
- Dois arquivos:
  - `base_densidade_ferrovias.csv` (completo, com comprimentos)
  - `base_densidade_simplificada.csv` (apenas densidades)

**Interpretação:**
```
densidade = (comprimento em km / área em km²) × 1000

Exemplo:
- Densidade = 0: Nenhuma ferrovia na AMC
- Densidade = 50: 50 km de ferrovia por cada 1000 km² de área
- Densidade = 100: 100 km de ferrovia por cada 1000 km² de área
```

**Exemplo de uso:**
```r
# Para análise de densidade (causalidade inversa):
base_dens <- read.csv("base_densidade_simplificada.csv")
lm(log(y_2003) ~ densidade_real_2003, data = base_dens)

# Comparar sintética com real:
summary(base_dens$densidade_sintetica)
summary(base_dens$densidade_real_2003)
```

---

### 4️⃣ Base Integrada: `base_completa_integrada.csv`

**Propósito:** Única tabela com todas as variáveis, pronta para análises

**Estrutura:**
```
code_amc | area_km2 | dist/dummy/densidade_sintetica | 
dist/dummy/densidade_real_1858 | dist/dummy/densidade_real_1860 | ... | 
dist/dummy/densidade_real_2003
```

**Características:**
- **1 linha por AMC** × **múltiplas colunas**
- Contém:
  - Identificador (code_amc)
  - Área (controle)
  - 3 variáveis sintéticas
  - 3 variáveis × N períodos reais
- Sem valores ausentes
- Dimensões: ~700 AMCs × ~1.700 colunas

**Exemplo de uso:**
```r
# Carregar
base <- read.csv("base_completa_integrada.csv")
# ou
base <- readRDS("base_completa_integrada.rds")

# Inspecionar
dim(base)  # linhas e colunas
head(base[, 1:10])

# Usar em análises IV
library(fixest)
# Primeiro estágio: instrumentar com sintética
fs <- lm(dist_rail_real_2003 ~ dist_rail_sintetica_km, data = base)
# Segundo estágio
ss <- feols(log(y_2003) ~ 1 | dist_rail_real_2003 ~ dist_rail_sintetica_km, data = base)
```

---

## 🔍 Validações Realizadas

Todos os scripts incluem validações automáticas:

✅ **Verificação de dados ausentes (NAs)**
✅ **Verificação de duplicatas**
✅ **Validação de relações lógicas** (ex: dummy consistente com distância)
✅ **Estatísticas descritivas** (média, mediana, máximo)

---

## ⚙️ Parâmetros Ajustáveis

### Limiar de Atendimento (Base de Dummy)
Localizado em `2_Criar_Base_Dummy_Atendimento.R`, linha ~20:

```r
LIMIAR_KM <- 25  # Ajuste para 10, 50, etc.
```

**Impacto:** Altera quantas AMCs são consideradas "atendidas"

---

## 📁 Estrutura de Arquivos

```
seu_diretorio/
├── 0_MASTER_Criar_Todas_Bases.R          (🔴 execute este primeiro)
├── 1_Criar_Base_Distancias.R
├── 2_Criar_Base_Dummy_Atendimento.R
├── 3_Criar_Base_Densidade_Ferrovias.R
├── 4_Integrar_Bases_Completas.R
├── README_BASES_DADOS.md                 (este arquivo)
│
├── [SAÍDAS - arquivos gerados]
├── base_distancias_amcs_nordeste_semmar.csv
├── base_dummy_atendimento_ferrovias.csv
├── base_dummy_atendimento_simples.csv
├── base_densidade_ferrovias.csv
├── base_densidade_simplificada.csv
├── base_completa_integrada.csv
├── base_completa_integrada.rds
└── base_completa_data_dictionary.csv
```

---

## 🔗 Integração com Análises Existentes

### Para usar com `IV_Analise_Completa_SemMar.R`:

```r
# Carregar a base integrada
source("0_MASTER_Criar_Todas_Bases.R")  # ou use a base já criada

# A base está disponível como `base_completa_integrada` ou
base_iv_sf <- read.csv("base_completa_integrada.csv")

# Continuar com análises IV...
source("IV_Analise_Completa_SemMar.R")
```

---

## 📈 Exemplos de Análises Possíveis

### 1. Análise IV Clássica
```r
# Variável instrumental: distância até rede sintética
# Tratamento: atendimento por rede real
base <- read.csv("base_completa_integrada.csv")

library(fixest)
feols(log(y_2003) ~ 1 | 
      dist_rail_real_2003 ~ dist_rail_sintetica_km, 
      data = base)
```

### 2. Event Study: Impacto de Inaugurações
```r
# Usar mudanças no dummy ao longo do tempo
base <- read.csv("base_completa_integrada.csv")

# Criar um painel longo
base_long <- base |> 
  pivot_longer(starts_with("dummy_atendida_real_"),
               names_to = "ano", values_to = "atendida") |>
  mutate(ano = as.numeric(gsub("dummy_atendida_real_", "", ano)))

# Usar para event study...
```

### 3. Análise de Densidade Espacial
```r
base <- read.csv("base_completa_integrada.csv")

# Adicionar vizinhança (ex: sf)
base_sf <- st_as_sf(...)  # converter para geoespacial
vizinhos <- poly2nb(base_sf, queen = TRUE)
pesos <- nb2listw(vizinhos)

# Regredir com lag espacial
```

---

## ⏱️ Tempo de Execução Estimado

| Script | Tempo | Operação Principal |
|--------|-------|-------------------|
| 1_Distancias | 5 min | Cálculo de distâncias ponto-linha |
| 2_Dummy | 10 min | Criação de dummies cronológicas |
| 3_Densidade | 30-40 min | Intersecção polígono-linha (pesada!) |
| 4_Integração | 1 min | Merge de tabelas |
| **TOTAL** | **45-60 min** | - |

> ⚠️ O script 3 é o mais pesado. Se tiver timeout, considere reduzir o número de anos ou usar um computador mais potente.

---

## 🐛 Troubleshooting

### Erro: "arquivo não encontrado"
- Verifique se todos os arquivos de entrada estão no diretório
- Verifique se `data.wd` está apontando para o diretório correto

### Erro: "não há memória suficiente"
- O script 3 é muito pesado em computadores com pouca RAM
- Solução: Executar separadamente ou reduzir o número de períodos

### Valores ausentes inesperados
- Verificar se ferrovias/AMCs têm geometria válida
- Considerar usar `st_make_valid()` nas camadas

### Resultados parecem estranhos
- Verificar CRS consistente (deve ser 31984 - UTM 24S)
- Verificar se limiar de 25 km é apropriado para seu caso

---

## 📞 Suporte

Para problemas ou dúvidas:
1. Verificar console output (mensagens de log)
2. Revisar `base_completa_data_dictionary.csv` para variáveis
3. Checar estatísticas em cada script (últimas linhas)

---

## 📝 Changelog

**Versão 1.0** (2026-05)
- ✅ Base de distâncias
- ✅ Base de dummy de atendimento
- ✅ Base de densidade
- ✅ Base integrada
- ✅ Documentação completa

---

## 🎯 Próximas Etapas Recomendadas

1. ✅ Executar `0_MASTER_Criar_Todas_Bases.R`
2. ✅ Verificar saída em `base_completa_integrada.csv`
3. ✅ Executar análises com IV_Analise_Completa_SemMar.R
4. ✅ Documentar resultados

---

**Última atualização:** 2026-05-10  
**Autor:** Scripts de processamento de dados geoespaciais
