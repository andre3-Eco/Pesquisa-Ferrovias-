# 📑 Índice Completo - Criação de Bases de Dados Analíticas

**Data de Criação:** 2026-05-10  
**Status:** ✅ Concluído  
**Última Atualização:** 2026-05-10

---

## 🎯 Índice Rápido

### Para Iniciantes
1. Leia: [COMECE_AQUI.R](COMECE_AQUI.R) (instruções diretas)
2. Execute: `source("0_MASTER_Criar_Todas_Bases.R")`
3. Valide: `source("5_Validar_Bases_Criadas.R")`
4. Use a base: `base <- readRDS("base_completa_integrada.rds")`

### Para Referência Técnica
- [README_BASES_DADOS.md](README_BASES_DADOS.md) - Documentação completa
- [GUIA_RAPIDO.txt](GUIA_RAPIDO.txt) - Referência e troubleshooting
- [base_completa_data_dictionary.csv](base_completa_data_dictionary.csv) - Dicionário de variáveis

---

## 📁 Estrutura de Arquivos

### 🟢 SCRIPTS DE CRIAÇÃO (Execute nesta ordem)

| # | Arquivo | Descrição | Tempo |
|-|-|-|-|
| 0 | [0_MASTER_Criar_Todas_Bases.R](0_MASTER_Criar_Todas_Bases.R) | **EXECUTE ESTE PRIMEIRO** - Orquestra tudo | 45-60 min |
| 1 | [1_Criar_Base_Distancias.R](1_Criar_Base_Distancias.R) | Cria distâncias (km) de cada AMC até ferrovias | 5 min |
| 2 | [2_Criar_Base_Dummy_Atendimento.R](2_Criar_Base_Dummy_Atendimento.R) | Cria dummies 0/1 (atendida/não atendida) | 10 min |
| 3 | [3_Criar_Base_Densidade_Ferrovias.R](3_Criar_Base_Densidade_Ferrovias.R) | Cria densidade (km/1000km²) de ferrovias | 30-40 min |
| 4 | [4_Integrar_Bases_Completas.R](4_Integrar_Bases_Completas.R) | Integra as 3 bases em uma única tabela | 1 min |
| 5 | [5_Validar_Bases_Criadas.R](5_Validar_Bases_Criadas.R) | Testa integridade e qualidade das bases | 2 min |

### 📊 BASES DE DADOS CRIADAS (Saídas)

#### Principais (Use Estas!)
| Arquivo | Linhas | Colunas | Descrição |
|-|-|-|-|
| 📌 `base_completa_integrada.csv` | ~730 | ~1700 | **INTEGRADA - USE ESTA (CSV)** |
| 📌 `base_completa_integrada.rds` | ~730 | ~1700 | **INTEGRADA - USE ESTA (R object, mais rápida)** |

#### Componentes (Para Referência)
| Arquivo | Linhas | Colunas | Descrição |
|-|-|-|-|
| `base_distancias_amcs_nordeste_semmar.csv` | ~730 | 78 | Distâncias até ferrovias |
| `base_dummy_atendimento_simples.csv` | ~730 | 78 | Atendimento binário (0/1) |
| `base_densidade_simplificada.csv` | ~730 | 78 | Densidade de ferrovias |
| `base_dummy_atendimento_ferrovias.csv` | ~730 | 155 | Dummy + medidas contínuas |
| `base_densidade_ferrovias.csv` | ~730 | 155 | Densidade + comprimentos |

#### Complementares
| Arquivo | Descrição |
|-|-|
| `base_completa_data_dictionary.csv` | Dicionário automático de todas as variáveis |

### 📚 DOCUMENTAÇÃO

| Arquivo | Descrição | Para Quem |
|-|-|-|
| [COMECE_AQUI.R](COMECE_AQUI.R) | Instruções diretas com exemplos | Iniciantes |
| [GUIA_RAPIDO.txt](GUIA_RAPIDO.txt) | Referência rápida e troubleshooting | Todos |
| [README_BASES_DADOS.md](README_BASES_DADOS.md) | Documentação técnica completa | Técnicos |
| [INDICE_COMPLETO.md](INDICE_COMPLETO.md) | Este arquivo | Navegação |

---

## 🔍 O Que Cada Base Contém

### 1️⃣ Base de Distâncias
**Arquivo:** `base_distancias_amcs_nordeste_semmar.csv`

Mede a proximidade de cada AMC até infraestrutura ferroviária.

```
Colunas:
├── code_amc (identificador)
├── dist_rail_sintetica_km (ESTÁTICO)
└── dist_rail_real_YYYY (CRONOLÓGICO, 1858-2003)
    ├── dist_rail_real_1858
    ├── dist_rail_real_1880
    ├── ...
    └── dist_rail_real_2003

Interpretação:
• Valor = X km: AMC está a X quilômetros de ferrovia
• Valores menores = proximidade maior = possível maior impacto
```

**Uso em Análises:**
- Variável instrumental (sintética como instrumento para real)
- Controle de proximidade
- Análise de gradiente espacial

---

### 2️⃣ Base de Dummy Atendimento
**Arquivo:** `base_dummy_atendimento_simples.csv`

Indicador binário de se uma AMC é atendida por ferrovia.

```
Colunas:
├── code_amc (identificador)
├── dummy_atendida_sintetica (ESTÁTICO)
└── dummy_atendida_real_YYYY (CRONOLÓGICO)
    ├── dummy_atendida_real_1858
    ├── dummy_atendida_real_1880
    ├── ...
    └── dummy_atendida_real_2003

Valores:
• 1 = Atendida (distância ≤ 25 km)
• 0 = Não atendida (distância > 25 km)

Nota: Limiar de 25 km é ajustável
```

**Uso em Análises:**
- Variável de tratamento em análises causal
- Event study (explorar mudanças 0→1 ao longo do tempo)
- Modelo de diferenças-em-diferenças

---

### 3️⃣ Base de Densidade
**Arquivo:** `base_densidade_simplificada.csv`

Intensidade de infraestrutura ferroviária em cada AMC.

```
Colunas:
├── code_amc (identificador)
├── area_km2 (área da AMC)
├── densidade_sintetica (ESTÁTICO)
└── densidade_real_YYYY (CRONOLÓGICO)
    ├── densidade_real_1858
    ├── densidade_real_1880
    ├── ...
    └── densidade_real_2003

Fórmula:
densidade = (comprimento_em_km / area_km2) × 1000

Interpretação:
• Densidade = 0: Sem ferrovia
• Densidade = 50: 50 km de ferrovia por 1000 km²
• Densidade = 100: 100 km de ferrovia por 1000 km²

Vantagem: Normaliza por tamanho da AMC (comparável)
```

**Uso em Análises:**
- Medida contínua de infraestrutura
- Análise de efeito dose-resposta
- Controle de infraestrutura sintética

---

### 4️⃣ Base Integrada (USE ESTA!)
**Arquivo:** `base_completa_integrada.csv` ou `.rds`

Uma única tabela com TUDO (distâncias + dummies + densidades).

```
Estrutura:
code_amc | area_km2 | 
dist/dummy/densidade_sintetica |
dist/dummy/densidade_real_1858 |
dist/dummy/densidade_real_1880 |
... |
dist/dummy/densidade_real_2003

Dimensões: ~730 linhas × ~1700 colunas

Pronta para análises econométricas sem processamento adicional
```

**Vantagens:**
- Uma única fonte de dados
- Todas as variáveis sincronizadas
- Sem risco de misalinhamento

---

## 📊 Variáveis Disponíveis

### Sintéticas (Estáticas - não mudam no tempo)

```
dist_rail_sintetica_km
dummy_atendida_sintetica
densidade_sintetica
cobertura_continua_sintetica (apenas na base detalhada)
```

### Reais Cronológicas (Mudam ao longo do tempo)

```
Para cada ano YYYY de 1858 a 2003:

dist_rail_real_YYYY
dummy_atendida_real_YYYY
densidade_real_YYYY
cobertura_continua_real_YYYY (apenas na base detalhada)
```

**Exemplo de anos disponíveis:**
1858, 1860, 1862, 1863, 1873, 1875, 1876, 1880, 1881, 1882, ..., 1996, 2003

Total de ~77 períodos diferentes

---

## 🚀 Como Começar

### Passo 1: Criar as Bases (Uma única vez)

```r
# Abra RStudio e execute:
source("0_MASTER_Criar_Todas_Bases.R")

# ⏱️ Vai levar ~60 minutos
# ⚠️ NÃO INTERROMPA!
```

### Passo 2: Validar

```r
source("5_Validar_Bases_Criadas.R")

# Deve retornar: ✅ TUDO OK!
```

### Passo 3: Carregar e Usar

```r
# Carregar (RECOMENDADO - mais rápido)
base <- readRDS("base_completa_integrada.rds")

# Ou carregar CSV
base <- read.csv("base_completa_integrada.csv")

# Pronto! Você tem 730 AMCs × ~1700 variáveis
```

### Passo 4: Analisar

```r
# Exemplo simples: regressão
lm(log(y_2003) ~ dummy_atendida_real_2003, data = base)

# Ou IV com a sintética como instrumento
library(fixest)
feols(log(y_2003) ~ 1 | 
      dist_rail_real_2003 ~ dist_rail_sintetica_km, 
      data = base)
```

---

## 📖 Leitura Recomendada

### Por Objetivo

**"Quero começar rapidinho"**
→ Leia: [COMECE_AQUI.R](COMECE_AQUI.R)

**"Preciso entender as variáveis"**
→ Leia: [README_BASES_DADOS.md](README_BASES_DADOS.md)

**"Tenho uma dúvida específica"**
→ Busque em: [GUIA_RAPIDO.txt](GUIA_RAPIDO.txt) (seção "Problemas Comuns")

**"Preciso de referência técnica"**
→ Veja: `base_completa_data_dictionary.csv`

---

## ⚙️ Configurações e Customizações

### Limiar de Atendimento
**Arquivo:** `2_Criar_Base_Dummy_Atendimento.R`  
**Linha:** ~20

```r
LIMIAR_KM <- 25  # Altere para 10, 50, etc.
```

**Impacto:** Determina quantas AMCs são consideradas "atendidas"

### Sistema de Coordenadas
**Padrão:** 31984 (UTM 24S)  
**Localização:** Todos os scripts (não altere)

### Período de Análise
**Padrão:** 1858 a 2003  
**Alteração:** Editar scripts 1, 2, 3 (não recomendado)

---

## ✅ Validações Automáticas

Todos os scripts incluem:

- ✓ Verificação de valores ausentes (NAs)
- ✓ Detecção de duplicatas
- ✓ Validação de relações lógicas
- ✓ Cálculo de estatísticas descritivas
- ✓ Testes de consistência

Execute [5_Validar_Bases_Criadas.R](5_Validar_Bases_Criadas.R) para verificar tudo.

---

## 🔗 Integração com Análises Existentes

### IV_Analise_Completa_SemMar.R

```r
# Após criar bases, execute:
source("0_MASTER_Criar_Todas_Bases.R")

# Depois use:
source("IV_Analise_Completa_SemMar.R")

# A base integrada será usada automaticamente
```

---

## 📈 Exemplos de Análises Possíveis

### 1. Análise IV Clássica
```r
base <- readRDS("base_completa_integrada.rds")
library(fixest)

feols(log(y_2003) ~ 1 | 
      dist_rail_real_2003 ~ dist_rail_sintetica_km, 
      data = base)
```

### 2. Event Study
```r
base_long <- base |>
  pivot_longer(starts_with("dummy_atendida_real_"),
               names_to = "ano", values_to = "atendida") |>
  mutate(ano = as.numeric(gsub("dummy_atendida_real_", "", ano)))

# Explorar mudanças 0→1 ao longo do tempo
```

### 3. Análise de Densidade
```r
lm(log(y_2003) ~ densidade_real_2003, data = base)
```

---

## 📞 FAQ (Perguntas Frequentes)

### P: Por quanto tempo as bases levam para ser criadas?
**R:** ~60 minutos. Script 3 (Densidade) é o mais pesado.

### P: Preciso criar novamente toda vez que abro R?
**R:** Não! Crie uma única vez. Depois apenas carregue.

### P: Qual base usar para análises?
**R:** Sempre a integrada (`base_completa_integrada.rds` ou `.csv`)

### P: Posso mudar o limiar de 25 km?
**R:** Sim! Edit `2_Criar_Base_Dummy_Atendimento.R`, linha ~20

### P: Qual a diferença entre CSV e RDS?
**R:** RDS é mais rápido e preserva tipos. CSV é mais portável.

### P: Quanto de memória RAM preciso?
**R:** ~4 GB recomendado. Script 3 é pesado em memória.

---

## 🐛 Troubleshooting

### Erro: "Arquivo não encontrado"
→ Verifique `data.wd` com `getwd()`  
→ Mude para diretório correto com `setwd(...)`

### Erro: "Memória insuficiente"
→ Execute scripts individualmente  
→ Feche outros programas  
→ Considere computador mais potente para script 3

### Processo muito lento
→ Normal! Script 3 processa ~1.7 mil colunas  
→ Não interrompa, aguarde conclusão

---

## 📝 Changelog

**v1.0** (2026-05-10)
- ✅ Scripts 0-5 criados
- ✅ Documentação completa
- ✅ Validação automática
- ✅ Base integrada

---

## 🎓 Para Aprender Mais

- **Sobre Variáveis Instrumentais:** Ver `IV_Analise_Completa_SemMar.R`
- **Sobre Dados Geoespaciais:** Ver scripts com `st_intersection`, `st_distance`
- **Sobre Processamento de Painel:** Ver base em formato longo

---

## 📬 Contato / Suporte

Para dúvidas:
1. Consult GUIA_RAPIDO.txt
2. Abra README_BASES_DADOS.md
3. Revise console output dos scripts
4. Verifique base_completa_data_dictionary.csv

---

**Última atualização:** 2026-05-10  
**Status:** ✅ Completo e testado  
**Pronto para uso:** Sim!
