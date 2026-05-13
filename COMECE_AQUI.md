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

---

## 🎯 O Que Cada Pasta Contém

| Pasta | Contém | Quando Usar |
|-------|--------|------------|
| `01-dados/brutos/` | Excel originais (população, PIB) | Se dados mudam |
| `01-dados/processados/` | **Base integrada** (USE ESTA!) | Sempre |
| `02-scripts/01-preparacao/` | Scripts para criar bases | Se dados brutos mudam |
| `02-scripts/02-analise/` | **Scripts IV** (RODE AQUI!) | Sempre |
| `02-scripts/03-visualizacao/` | Gráficos e tabelas | Após rodar análise |
| `03-resultados/` | **Saídas finais** | Para ler resultados |
| `04-documentacao/` | Guias e referências | Para entender |
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

## 📊 Entender os Resultados

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

## ✅ Checklist Antes de Começar

- [ ] RStudio aberto?
- [ ] Diretório correto? (`setwd(...)`)
- [ ] Pacotes instalados? (`tidyverse`, `fixest`, `readxl`)
- [ ] Arquivo `01-dados/processados/base_completa_integrada.rds` existe?
- [ ] Pronto para `source("02-scripts/02-analise/QUICK_START_BATERIA_IV.R")`?

---

## 🎓 Próximos Passos Após Primeira Análise

1. **Revisar coeficientes** → Fazem sentido?
2. **Checar p-values** → Significância aceitável?
3. **Validar F-stat** → Instrumento forte (> 10)?
4. **Testar robustez** → Mudar especificação?
5. **Documentar achados** → Escrever resultados?
6. **Fazer mapas** → Usar `05-geometrias/` para visualizar espacialmente?

---

## 📞 Recursos

| Preciso de... | Veja... |
|---------------|---------|
| Visão geral do projeto | `README.md` |
| Atalhos rápidos | `INDEX.md` |
| Estrutura visual | `ESTRUTURA_VISUAL.txt` |
| Detalhes técnicos | `AGENTS.md` |
| Info sobre dados | `04-documentacao/README_BASES_DADOS.md` |
| Info sobre IV/2SLS | `04-documentacao/README_BATERIA_TESTES_IV.md` |
| Lista de variáveis | `04-documentacao/Dicionário*.txt` |

---

## 🎉 Tudo Pronto!

```r
# Execute isto AGORA:
source("02-scripts/02-analise/QUICK_START_BATERIA_IV.R")

# Espere 30-40 minutos
# Veja resultados em: 03-resultados/
```

---

**Boa análise! 🚀**

Qualquer dúvida, consulte a documentação acima.
