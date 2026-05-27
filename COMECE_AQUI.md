# 🚀 COMECE AQUI

## Bem-vindo! Seu projeto está organizado e pronto para rodar.

---

## 📋 Em 5 Minutos

1. **Abra RStudio** e defina o diretório:
    ```r
    setwd("C:\\Users\\André Elias\\Documents\\Pesquisa (Ferrovias)")
    ```

2. **Carregue o arquivo RDS** (mais rápido que CSV):
    ```r
    base <- readRDS("01-dados/processados/base_completa_integrada.rds")
    dim(base)  # Ver dimensões
    ```

3. **Rode a análise rápida**:
    ```r
    source("02-scripts/02-analise/QUICK_START_BATERIA_IV.R")
    # Espere 30-40 minutos
    ```

4. **Veja os resultados**:
    ```r
    resultados <- read.csv("03-resultados/csv/resultados_bateria_iv_pib_pop.csv")
    head(resultados)  # Primeiras linhas
    ```

5. **Gere gráficos**:
    ```r
    source("02-scripts/03-visualizacao/7_Visualizar_Resultados_IV.R")
    ```

---

## 📚 Próximo Passo: Leia Documentação

### Se você tem **5 minutos:**
- Leia `README.md` (visão geral do projeto)

### Se você tem **10 minutos:**
- Leia `INDEX.md` (atalhos e FAQ)
- Consulte `ESTRUTURA_VISUAL.txt` (guia visual)

### Se você tem **30 minutos:**
- Leia `04-documentacao/README_BATERIA_TESTES_IV.md`
- Entenda como funciona a análise IV/2SLS

### Se você tem **60 minutos** (novas análises):
- Execute os scripts de interpolação e variáveis sintéticas por ano:
  ```r
  source("02-scripts/exploratoria/SPATIAL_INTERPOLACAO_OUTCOMES.R")
  source("02-scripts/exploratoria/CRIAR_BASE_SINTETICA_CRONOLOGICA.R")
  ```
- Depois rode as análises de primeiro e segundo estágio por ano:
  ```r
  source("02-scripts/exploratoria/FIRST_STAGE_SYNTHETIC_VS_REAL_BY_YEAR.R")
  source("02-scripts/exploratoria/SECOND_STAGE_PIB_YEARLY_TREATMENT.R")
  ```

---

## 🎯 O Que Cada Pasta Contém

| Pasta | Contém | Quando Usar |
|-------|--------|-------------|
| `01-dados/brutos/` | Excel originais (população, PIB) | Se dados mudam |
| `01-dados/processados/` | **Base integrada** (USE ESTA!) + **Novas bases interpoladas e sintéticas** | Sempre |
| `02-scripts/01-preparacao/` | Scripts para criar bases | Se dados brutos mudam |
| `02-scripts/02-analise/` | **Scripts IV** (RODE AQUI!) | Sempre |
| `02-scripts/03-visualizacao/` | Gráficos e tabelas + **Mapas de interpolação** | Após rodar análise |
| `02-scripts/exploratoria/` | **Testes e desenvolvimento - NOVAS ANÁLISES** | Para análises avançadas |
| `03-resultados/` | **Saídas finais** + **Novos resultados por ano** | Para ler resultados |
| `04-documentacao/` | Guias e referências + **Dicionários de dados** | Para entender |
| `05-geometrias/` | Dados geoespaciais (GeoPackage) | Para mapas |

---

## 🔥 Guia Rápido de Execução

### **OPÇÃO A: Super Rápido** (30 minutos)
```r
source("02-scripts/02-analise/QUICK_START_BATERIA_IV.R")
```
✅ Melhor para: Testes rápidos, verificar se tudo funciona  
⏱️ Tempo: 30-40 minutos  
📊 Saída: Gráficos automáticos + coeficientes

---

### **OPÇÃO B: Do Zero** (90 minutos)
```r
# Preparar dados do zero
source("02-scripts/01-preparacao/0_MASTER_Criar_Todas_Bases.R")

# Rodar análise
source("02-scripts/02-analise/6_Bateria_Testes_Etapas_I_II.R")

# Visualizar
source("02-scripts/03-visualizacao/7_Visualizar_Resultados_IV.R")
```
✅ Melhor para: Reprodução completa, cambios em dados brutos  
⏱️ Tempo: 60-90 minutos  
📊 Saída: Tudo do zero

---

### **OPÇÃO C: Manual** (Flexível)
```r
# Carregar base
base <- readRDS("01-dados/processados/base_completa_integrada.rds")

# Explorar
head(base)
dim(base)
colnames(base)[1:20]

# Rodar regressão customizada (exemplo)
library(fixest)

reg <- feols(
  `2010` ~ dist_rail_real_2003 | state_abbr,
  data = base,
  IV = dist_rail_real_2003 ~ dist_rail_sintetica_km
)
summary(reg)
```
✅ Melhor para: Customizar análises, exploração  
⏱️ Tempo: Variável  
📊 Saída: Conforme sua necessidade

---

### **OPÇÃO D: Análises Avançadas** (Novas Funcionalidades) ⭐
```r
# 1. Interpolar outcomes históricos faltantes (IDW)
source("02-scripts/exploratoria/SPATIAL_INTERPOLACAO_OUTCOMES.R")
# → Gera: 01-dados/processados/outcomes/interpolados/outcomes_amc_ne_interpolado.*

# 2. Criar variáveis sintéticas por ano
source("02-scripts/exploratoria/CRIAR_BASE_SINTETICA_CRONOLOGICA.R")
# → Gera: 01-dados/processados/base_sintetica_cronologica.*

# 3. Testar força do instrumento por ano (primeiro estágio)
source("02-scripts/exploratoria/FIRST_STAGE_SYNTHETIC_VS_REAL_BY_YEAR.R")
# → Gera: 03-resultados/csv/first_stage_sintetica_vs_real_por_ano.csv

# 4. Analisar efeito dos tratamentos sintéticos no PIB por ano (segundo estágio)
source("02-scripts/exploratoria/SECOND_STAGE_PIB_YEARLY_TREATMENT.R")
# → Gera: 03-resultados/csv/second_stage_pib_tratamentos_sinteticos_por_ano.csv

# 5. Análise de persistência histórica (sem pontas)
source("02-scripts/exploratoria/PERSISTENCIA_SEM_PONTAS.R")
# → Gera: 03-resultados/csv/second_stage_persistencia_pib2010_sem_pontas.csv
```
✅ Melhor para: Análises temporais, persistência histórica, validação do instrumento  
⏱️ Tempo: 40-60 minutos (dependendo do seu hardware)  
📊 Saída: Múltiplos arquivos CSV com análises por ano + mapas de interpolação  

---

## 🤔 Dúvidas Frequentes

### **P: Por onde começo?**
R: Execute `QUICK_START_BATERIA_IV.R` (30 min, sem perguntas) para a análise tradicional, ou os scripts da OPÇÃO D para as novas análises temporais.

### **P: Quanto tempo leva tudo?**
R: 
- Quick Start tradicional: 30-40 min
- Full pipeline tradicional: 60-90 min
- Novas análises de interpolação e variáveis sintéticas: 40-60 min
- Manual: Variável

### **P: Preciso rodar preparação de dados?**
R: NÃO. A base já está pronta em `01-dados/processados/`

### **P: Que pacotes R preciso?**
R: Instale com:
```r
pacotes <- c("tidyverse", "sf", "fixest", "readxl", "broom", "purrr", "spdep", "gstat", "viridis", "patchwork")
install.packages(pacotes)
```

### **P: Como interpreto F > 10?**
R: É a "força do instrumento". Quanto maior, melhor. Ver `04-documentacao/README_BATERIA_TESTES_IV.md`

### **P: O que é coef_ss?**
R: Coeficiente do segundo estágio. A estimativa causal principal.

### **P: O que são os novos arquivos em outcomes/interpolados/ e base_sintetica_cronologica.*?**
R: 
- `outcomes_amc_ne_interpolado.*`: Contém valores de PIB e outros outcomes interpolados para anos históricos (1920-2010) usando interpolação inversa da distância ponderada (IDW) para preencher dados faltantes
- `base_sintetica_cronologica.*`: Contém variáveis sintéticas por ano de inauguração (distância, dummy, densidade, comprimento) para cada ano de 1858 a 2003, permitindo análises temporais do efeito instrumental

### **P: Como faço para ver se o instrumento sintético é forte em cada ano?**
R: Após rodar `FIRST_STAGE_SYNTHETIC_VS_REAL_BY_YEAR.R`, veja o arquivo `03-resultados/csv/first_stage_sintetica_vs_real_por_ano.csv` e verifique a coluna `F_estatistica` - valores > 10 indicam instrumento forte.

### **P: Como adiciono novos controles?**
R: Edite `02-scripts/01-preparacao/4_Integrar_Bases_Completas.R` e reprocesse.

---

## 📊 Entender os Resultados

### **Resultados Tradicionais**
Os resultados estão em: `03-resultados/csv/resultados_bateria_iv_pib_pop.csv`

**Colunas principais:**
```
especificacao      → Qual amostra (completa, com FE, etc)
tratamento         → Qual variável (distância, dummy, densidade)
outcome            → Qual desfecho (população 2003 ou 2010)
coef_ss            → O coeficiente (impacto estimado)
p_value            → Significância (< 0.05 = significante)
f_stat             → Força do instrumento (> 10 = bom)
n_obs              → Tamanho da amostra
```

**Exemplo de leitura:**
```
Distância → População 2003
coef = 0.15, p_value = 0.032, f_stat = 18.5

"Cada km a menos de distância = +0.15% na população
Significante a 5% e instrumento forte"
```

### **Resultados das Novas Análises**

**Primeiro Estágio por Ano** (`first_stage_sintetica_vs_real_por_ano.csv`):
- `ano`: Ano do tratamento
- `tratamento`: distância/dummy/densidade
- `F_estatistica`: Força do instrumento sintético naquele ano
- `p_valor`: Significância do coeficiente do instrumento
- `n_observacoes`: Número de AMCs usadas

**Segundo Estágio por Ano** (`second_stage_pib_tratamentos_sinteticos_por_ano.csv`):
- `ano`: Ano do tratamento e outcome
- `tratamento`: dummy/densidade
- `coeficiente`: Efeito do tratamento sintético no PIB daquele ano
- `p_valor`: Significância do efeito
- `r2`: R² do modelo
- `n_observacoes`: Número de observações (AMCs)

**Análise de Persistência** (`second_stage_persistencia_pib2010_sem_pontas.csv`):
- `ano_tratamento`: Ano em que o tratamento sintético foi medido
- `tratamento_tipo`: dummy/densidade
- `coeficiente`: Efeito histórico do tratamento naquele ano no PIB de 2010
- `p_valor`: Significância do efeito histórico
- `r2`: R² do modelo
- `n_observacoes`: Número de AMCs usadas

---

## 🛠️ Troubleshooting

### **Erro: "File not found"**
```r
# Verifique o diretório
getwd()

# Se não estiver certo, ajuste:
setwd("C:\\Users\\André Elias\\Documents\\Pesquisa (Ferrovias)")
```

### **Erro: "Package not found"**
```r
# Instale o pacote que falta
install.packages("nome_do_pacote")
```

### **Script lentíssimo?**
- Verifique RAM disponível
- Feche outros programas
- Use `.rds` em vez de `.csv` (mais rápido)
- Para os novos scripts de interpolação, considere reduzir a resolução da grade no script SPATIAL_INTERPOLACAO_OUTCOMES.R

### **Gráficos não aparecem?**
```r
# Tente isto antes de rodar script
Sys.setenv(RSTUDIO_CONSOLE_WIDTH = 200)
```

### **Memória insuficiente na interpolação?**
No script SPATIAL_INTERPOLACAO_OUTCOMES.R, reduza a resolução da grade alterando:
```r
grid <- expand.grid(
  x = seq(x_range[1] - x_pad, x_range[2] + x_pad, length.out = 100),  # Reduzido de 200
  y = seq(y_range[1] - y_pad, y_range[2] + y_pad, length.out = 100)   # Reduzido de 200
)
```

---

## 💡 Dicas Profissionais

### **Dica 1: Use RDS, não CSV**
```r
# Lento:
base <- read.csv("01-dados/processados/base_completa_integrada.csv")

# Rápido:
base <- readRDS("01-dados/processados/base_completa_integrada.rds")
```

### **Dica 2: Verifique força do instrumento PRIMEIRO**
```r
# Antes de acreditar nos resultados das análises por ano, rode:
source("02-scripts/exploratoria/FIRST_STAGE_SYNTHETIC_VS_REAL_BY_YEAR.R")

# E checke: f_stat > 10? Sim → confie nos resultados
```

### **Dica 3: Salve seus gráficos**
```r
# No final de um script de visualização:
ggsave("03-resultados/graficos/meu_grafico.png", width = 10, height = 6)
```

### **Dica 4: Explore antes de rodear IV**
```r
# Sempre faça EDA primeiro:
hist(base$dist_rail_real_2003)
plot(base$dist_rail_sintetica_km, base$dist_rail_real_2003)
cor(base$dist_rail_sintetica_km, base$dist_rail_real_2003, use = "complete.obs")
```

### **Dica 5: Comece interpolar outcomes antes de variáveis sintéticas**
```r
# Primeiro interpolar os outcomes faltantes:
source("02-scripts/exploratoria/SPATIAL_INTERPOLACAO_OUTCOMES.R")

# Depois criar as variáveis sintéticas por ano:
source("02-scripts/exploratoria/CRIAR_BASE_SINTETICA_CRONOLOGICA.R")
```

### **Dica 6: Valide seu instrumento antes das análises estruturais**
```r
# Verifique em quais anos seu instrumento é forte:
fst_results <- read.csv("03-resultados/csv/first_stage_sintetica_vs_real_por_ano.csv")
strong_years <- fst_results %>% 
  filter(F_estatistica > 10) %>% 
  pull(ano) %>% 
  unique()

# Então rode apenas os segundos estágios para esses anos fortes:
source("02-scripts/exploratoria/SECOND_STAGE_PIB_YEARLY_TREATMENT.R")
# E depois filtre os resultados pelos anos fortes
```

---

## 🤔 Dúvidas Frequentes (Novas Análises)

### **P: Por que interpolar os outcomes históricos?**
R: Muitos valores de PIB e outros outcomes estão faltando para anos antes de 1970. A interpolação IDW usa informações geográficas dos municípios vizinhos para estimar esses valores faltantes, permitindo análises de longo prazo.

### **P: O que é IDW (Inverse Distance Weighting)?**
R: É um método de interpolação espacial que estima valores em locais não amostrados baseado em uma média ponderada de valores amostrados próximos, onde o peso é inversamente proporcional à distância.

### **P: Por que criar variáveis sintéticas por ano?**
R: A rede sintética LCP é construída ano a ano (acumulativa). Ter variáveis por ano permite analisar como o efeito instrumental evolui ao longo do tempo e fazer análises de primeiro e segundo estágio por ano específico.

### **P: Como interpretar o resultado da persistência histórica?**
R: Mostra se ferrovias construídas em um determinado ano histórico ainda têm efeito mensurável no PIB de 2010, controlando por efeitos fixos de estado e outras variáveis. Um coeficiente significativo indica efeito de longo prazo.

### **P: Qual a diferença entre PERSISTÊNCIA HISTÓRICA.R e PERSISTENCIA_SEM_PONTAS.R?**
R: PERSISTENCIA_SEM_PONTAS.R é uma versão que remove as AMCs das pontas (como feito no SELIMIARES.R) para reduzir viés potencial de outliers, enquanto PERSISTÊNCIA HISTÓRICA.R mantém todas as AMCs.

### **P: Como escolher quais análises rodar primeiro?**
R: 
1. Sempre comece com a análise tradicional (`QUICK_START_BATERIA_IV.R`)
2. Depois valide seu instrumento com `FIRST_STAGE_SYNTHETIC_VS_REAL_BY_YEAR.R`
3. Se o instrumento for forte em suficientes anos, prossiga com as análises de segundo estágio por ano
4. Finalmente, explore a persistência histórica com `PERSISTENCIA_SEM_PONTAS.R`

---

## 🤔 Dúvidas Frequentes

### **P: Por onde começo?**
R: Execute `QUICK_START_BATERIA_IV.R` (30 min, sem perguntas)

### **P: Quanto tempo leva tudo?**
R: 
- Quick Start: 30-40 min
- Full pipeline: 60-90 min
- Manual: Variável

### **P: Preciso rodar preparação de dados?**
R: NÃO. A base já está pronta em `01-dados/processados/`

### **P: Que pacotes R preciso?**
R: Instale com:
```r
pacotes <- c("tidyverse", "sf", "fixest", "readxl", "broom", "purrr")
install.packages(pacotes)
```

### **P: Como interpreto F > 10?**
R: É a "força do instrumento". Quanto maior, melhor. Ver `04-documentacao/README_BATERIA_TESTES_IV.md`

### **P: O que é coef_ss?**
R: Coeficiente do segundo estágio. A estimativa causal principal.

### **P: Como adiciono novos controles?**
R: Edite `02-scripts/01-preparacao/4_Integrar_Bases_Completas.R` e reprocesse.

---

## 📈 Entender os Resultados

Os resultados estão em: `03-resultados/csv/resultados_bateria_iv_pib_pop.csv`

**Colunas principais:**
```
especificacao      → Qual amostra (completa, com FE, etc)
tratamento         → Qual variável (distância, dummy, densidade)
outcome            → Qual desfecho (população 2003 ou 2010)
coef_ss            → O coeficiente (impacto estimado)
p_value            → Significância (< 0.05 = significante)
f_stat             → Força do instrumento (> 10 = bom)
n_obs              → Tamanho da amostra
```

**Exemplo de leitura:**
```
Distância → População 2003
coef = 0.15, p_value = 0.032, f_stat = 18.5

"Cada km a menos de distância = +0.15% na população
Significante a 5% e instrumento forte"
```

---

## 🛠️ Troubleshooting

### **Erro: "File not found"**
```r
# Verifique o diretório
getwd()

# Se não estiver certo, ajuste:
setwd("C:\\Users\\André Elias\\Documents\\Pesquisa (Ferrovias)")
```

### **Erro: "Package not found"**
```r
# Instale o pacote que falta
install.packages("nome_do_pacote")
```

### **Script lentíssimo?**
- Verifique RAM disponível
- Feche outros programas
- Use `.rds` em vez de `.csv` (mais rápido)

### **Gráficos não aparecem?**
```r
# Tente isto antes de rodar script
Sys.setenv(RSTUDIO_CONSOLE_WIDTH = 200)
```

---

## 💡 Dicas Profissionais

### **Dica 1: Use RDS, não CSV**
```r
# Lento:
base <- read.csv("01-dados/processados/base_completa_integrada.csv")

# Rápido:
base <- readRDS("01-dados/processados/base_completa_integrada.rds")
```

### **Dica 2: Verifique força do instrumento PRIMEIRO**
```r
# Antes de acreditar nos resultados, rode:
source("02-scripts/02-analise/QUICK_START_BATERIA_IV.R")

# E checke: f_stat > 10? Sim → confie nos resultados
```

### **Dica 3: Salve seus gráficos**
```r
# No final de um script de visualização:
ggsave("03-resultados/graficos/meu_grafico.png", width = 10, height = 6)
```

### **Dica 4: Explore antes de rodear IV**
```r
# Sempre faça EDA primeiro:
hist(base$dist_rail_real_2003)
plot(base$dist_rail_sintetica_km, base$dist_rail_real_2003)
cor(base$dist_rail_sintetica_km, base$dist_rail_real_2003, use = "complete.obs")
```

---

## 🤔 Dúvidas Frequentes

### **P: Por onde começo?**
R: Execute `QUICK_START_BATERIA_IV.R`

### **P: Quanto tempo leva tudo?**
R: Quick Start = 30-40 min. Full pipeline = 60 min.

### **P: Preciso rodar preparação de dados?**
R: Não, se `01-dados/processados/base_completa_integrada.csv` existe.

### **P: Como interpreto F-statístico?**
R: F > 10 = bom. F < 5 = fraco. Ver `04-documentacao/README_BATERIA_TESTES_IV.md`.

### **P: Que variáveis usar como outcomes?**
R: `2003` ou `2010` (população em censos). PIB também disponível.

### **P: Como adicionar novos controles?**
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
│  └─ processados/          ← Outputs de preparação + Novas bases interpoladas/sintéticas
│
├─ 02-scripts/
│  ├─ 01-preparacao/        ← Limpeza e prep de dados
│  ├─ 02-analise/           ← 🚀 RODAR AQUI PRIMEIRO
│  ├─ 03-visualizacao/      ← Gráficos e tabelas
│  └─ exploratoria/         ← Testes e desenvolvimento (NOVAS ANÁLISES)
│
├─ 03-resultados/
│  ├─ csv/                  ← Coeficientes e testes + Novos resultados por ano
│  ├─ graficos/             ← PNG (box-plot, scatter, etc) + Mapas de interpolação
│  └─ tabelas/              ← HTML e XLSX formatados
│
├─ 04-documentacao/         ← Ler quando tiver dúvidas + Dicionários de dados
├─ 05-geometrias/           ← Dados geoespaciais (GeoPackage)
└─ 06-anexos/               ← Histórico e logs
```

---

## 📎 Leitura Sugerida (em ordem)

1. **Este arquivo** (5 min) ← Você está aqui
2. `README.md` (5 min)
3. `INDEX.md` (5 min)
4. `AGENTS.md` (10 min) - Visão técnica
5. `04-documentacao/README_BATERIA_TESTES_IV.md` (15 min) - Detalhes econométricos
6. `04-documentacao/README_BASES_DADOS.md` (10 min) - Estrutura de dados
7. **Novas:** `04-documentacao/DATA_DICTIONARIES.md` (15 min) - Dicionário completo das variáveis

---

## ✅ Checklist Rápido

- [ ] Arquivos na pasta? `ls` para ver
- [ ] RData carregado? Sim (variáveis em memória)
- [ ] Pronto para rodar script? Sim!
- [ ] Pacotes avançados instalados? (spdep, gstat, viridis, patchwork) - Para novas análises

```r
# Teste rápido (análise tradicional):
setwd("seu_caminho/Pesquisa (Ferrovias)")
source("02-scripts/02-analise/QUICK_START_BATERIA_IV.R")

# Teste avançado (após instalar pacotes extras):
source("02-scripts/exploratoria/SPATIAL_INTERPOLACAO_OUTCOMES.R")
source("02-scripts/exploratoria/CRIAR_BASE_SINTETICA_CRONOLOGICA.R")
source("02-scripts/exploratoria/FIRST_STAGE_SYNTHETIC_VS_REAL_BY_YEAR.R")
```

---

## 🎓 Próximos Passos Após Primeira Análise

1. **Revisar coeficientes** → Fazem sentido?
2. **Checar p-values** → Significância aceitável?
3. **Validar F-stat** → Instrumento forte (> 10)?
4. **Testar robustez** → Mudar especificação?
5. **Documentar achados** → Escrever resultados?
6. **Fazer mapas** → Usar `05-geometrias/` para visualizar espacialmente?
7. **Explorar novas análises** → Interpolação, variáveis sintéticas por ano, persistência histórica

---

## 📞 Recursos

| Preciso de... | Veja... |
|---------------|---------|
| Visão geral do projeto | `README.md` |
| Atalhos rápidos | `INDEX.md` |
| Estrutura visual | `ESTRUTURA_VISUAL.txt` |
| Guia técnico detalhado | `AGENTS.md` |
| Detalhes das bases | `04-documentacao/README_BASES_DADOS.md` |
| Detalhes dos testes IV | `04-documentacao/README_BATERIA_TESTES_IV.md` |
| Referência completa | `04-documentacao/INDICE_COMPLETO.md` |
| **Dicionário completo das variáveis** | `04-documentacao/DATA_DICTIONARIES.md` |
| Lista de variáveis | `04-documentacao/Dicionário*.txt` |

---

## 🎉 Tudo Pronto!

```r
# Execute isto AGORA (análise tradicional):
source("02-scripts/02-analise/QUICK_START_BATERIA_IV.R")

# Espere 30-40 minutos
# Veja resultados em: 03-resultados/

# Depois execute as novas análises (passo a passo):
source("02-scripts/exploratoria/SPATIAL_INTERPOLACAO_OUTCOMES.R")
source("02-scripts/exploratoria/CRIAR_BASE_SINTETICA_CRONOLOGICA.R")
source("02-scripts/exploratoria/FIRST_STAGE_SYNTHETIC_VS_REAL_BY_YEAR.R")
source("02-scripts/exploratoria/SECOND_STAGE_PIB_YEARLY_TREATMENT.R")
source("02-scripts/exploratoria/PERSISTENCIA_SEM_PONTAS.R")
```

---

**Boa análise! 🚀**

Qualquer dúvida, consulte a documentação acima.