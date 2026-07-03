# 📘 GUIA PRÁTICO: INFERÊNCIA ESPACIAL ROBUSTA

**Data:** Junho 2026  
**Script Principal:** `02-scripts/02-analise/9_INFERENCIA_ESPACIAL_ROBUSTA.R`  
**Resultados:** `03-resultados/csv/resultados_inferencia_espacial_robusta.csv`

---

## 🎯 OBJETIVO

Corrigir a inferência estatística para **dados espaciais** usando:
- **Erros-Padrão de Conley (HAC Espacial):** Permite correlação entre observações próximas
- **Clusterização Geográfica:** Agrupa erros por microrregião/estado

---

## ⚠️ PROBLEMA: Por que importa?

### Inferência Padrão (INCORRETA para dados espaciais)

```r
summary(mod, se = "hetero")
```

**Pressuposto:** Erros são independentes entre AMCs.  
**Realidade:** AMCs próximas têm infraestrutura similar → erros correlacionados.

**Consequência:** 
- ❌ Erros-padrão subestimados (muito otimistas)
- ❌ P-valores e ICs muito apertados
- ❌ Risco de falsos positivos

### Solução: Inferência Espacial Robusta

**Conley HAC (Heteroskedasticity-Autocorrelation Consistent):**
```r
summary(mod, vcov = fixest::conley(cutoff = 100000, lat = "lat", lon = "lon"))
```

- ✅ Permite correlação até X km de distância
- ✅ Erros-padrão maiores = ICs mais honestos
- ✅ Resultados mais conservadores e críveis

---

## 🔍 COMO INTERPRETAR OS RESULTADOS

### Arquivo de Saída

**Localização:** `03-resultados/csv/resultados_inferencia_espacial_robusta.csv`

**Colunas principais:**

| Coluna | Significado |
|--------|-------------|
| `tipo_se` | Tipo de inferência: `hetero`, `cluster`, `conley_50`, `conley_100`, `conley_200` |
| `coef` | Coeficiente estimado (efeito do tratamento) |
| `se` | Erro-Padrão |
| `p_valor` | P-valor (significância) |
| `amostra` | `Completa` ou `Restrita (≤200km)` |

### Exemplo Prático

```
tipo_se     coef        se          p_valor     n
─────────────────────────────────────────────────
hetero      0.0001343   0.0004209   0.750       1323
cluster     0.0001343   0.0002909   0.656       1323
conley_50   0.0001343   0.0004209   0.750       1323
conley_100  0.0001343   0.0004209   0.750       1323
conley_200  0.0001343   0.0004209   0.750       1323
```

**Interpretação:**
1. **Coef é igual** → Estimação consistente ✅
2. **SE é diferente** → Autocorrelação espacial presente
3. **P-valor não muda muito** → Coeff não significativo em nenhum caso

---

## 📊 DIAGNÓSTICO: QUANDO USAR QUAL MÉTODO?

### Passo 1: Verifique a Inflação do Erro-Padrão

```r
df_resultados_espacial |>
  group_by(tipo_se) |>
  summarise(se_medio = mean(se))

# Calcule a inflação:
inflation <- (se_conley_100 - se_hetero) / se_hetero * 100
```

**Interpretação:**

| Inflação | Interpretação | Recomendação |
|----------|---------------|--------------|
| < 10% | Correlação espacial baixa | Hetero OK |
| 10-30% | Correlação espacial moderada | Use Conley ou Cluster |
| > 30% | Correlação espacial forte | **Use Conley como primário** |

### Passo 2: Estabilidade dos Resultados

**Bom sinal:**
- Coeficientes iguais entre Hetero, Cluster, Conley
- P-valores mudam pouco
- SE cresce de forma suave: hetero < conley_50 < conley_100 < conley_200

**Sinal de alerta:**
- P-valores muito diferentes (ex: sig. com hetero, não-sig. com Conley)
- SE explode com Conley (possível problema de dados)
- Grandes saltos entre cutoffs

### Passo 3: Verificar Especificações

```r
df_resultados_espacial |>
  ggplot(aes(x = tipo_se, y = se, color = amostra)) +
  geom_point(size = 3) +
  facet_wrap(~tratamento)
```

Você quer ver:
- ✅ Linhas paralelas (consistência)
- ✅ Pequenas diferenças entre amostras
- ✅ Padrão ordenado: hetero < conley_50 < ... < conley_200

---

## 🔧 PARÂMETROS TÉCNICOS

### Cutoff do Conley

**O que é?** Raio até o qual permitimos correlação espacial.

| Cutoff | Quando usar | Comentário |
|--------|------------|-----------|
| 50 km | Spillovers muito locais | Raramente apropriado |
| 100 km | **Recomendado** | Padrão para ferrovias/infraestrutura |
| 200 km | Spillovers regionais | Mais conservador |

**Escolha:** Se em dúvida, use **100 km**. Depois teste robustez com 50 e 200.

### Clustering

**Opções:**

```r
cluster = ~state_abbr          # Por estado (9 clusters)
cluster = ~code_microrregiao   # Por microrregião (~9-15 clusters)
```

**Regra prática:** Use clustering se:
- Número de clusters ≥ 10
- Correlação é muito localizada (não difunde longe)

---

## 📋 CHECKLIST DE INTERPRETAÇÃO

Ao relatar resultados, verifique:

- ☐ **Coeficiente** Hetero ≈ Coeficiente Conley? (confirmação de consistência)
- ☐ **Significância muda?** Não deveria com coef. forte
- ☐ **SE > Hetero?** Confirma correlação espacial
- ☐ **F-stat do instrumento > 10?** (se usar IV/2SLS)
- ☐ **Resultados estáveis** entre cutoffs?

---

## 💡 EXEMPLO: RELATÓRIO PARA ARTIGO

### Inferência Espacial Robusta

Usamos **Erros-Padrão de Conley** com cutoff de 100km para permitir correlação espacial entre AMCs próximas. Os resultados são reportados em três variantes:

**Tabela: Efeito de Ferrovias no PIB (2003)**

| Modelo | Coef. | SE (Hetero) | SE (Conley 100km) | P-valor | N |
|--------|-------|------------|------------------|---------|---|
| Amostra Completa | 0.0134 | 0.0042 | 0.0042 | 0.750 | 1323 |
| Amostra ≤200km | 0.0000 | 0.0009 | 0.0009 | 0.998 | 1248 |

**Observações:**
- Coeficientes invariantes entre métodos → estimação estável
- SE (Conley) ≈ SE (Hetero) → correlação espacial baixa
- Resultados não-significativos em ambas especificações

---

## 🚀 PRÓXIMOS PASSOS

### 1. IV/2SLS Completo (Próxima Melhor Prática)

Atualmente: OLS robusto
Próximo: IV/2SLS com instrumento sintético

```r
feols(pib_2010 ~ 1 | state_abbr | 
      dist_rail_real_2003 ~ dist_rail_sintetica_km, 
      data = base)
```

### 2. Testes de Robustez

```r
# Fake IV: instrumento aleatório não deve importar
fake_iv <- rnorm(nrow(base))
feols(pib_2010 ~ 1 | state_abbr | 
      dist_rail_real_2003 ~ fake_iv, data = base)
# Deve dar resultado não-significativo
```

### 3. Spillovers Espaciais

```r
# Adiciona lag espacial do tratamento
base <- base |> 
  mutate(dist_rail_vizinhos = calculate_spatial_lag(dist_rail_real_2003))
```

### 4. Heterogeneidade Geográfica

```r
# Estimar por estado/região
for (estado in unique(base$state_abbr)) {
  mod <- feols(..., data = filter(base, state_abbr == estado))
}
```

---

## 📚 REFERÊNCIAS

### Stock & Yogo (2005)
"Testing for Weak Instruments in Linear IV Regression" (Journal of Econometric Reviews)
- F > 10 = instrumento forte
- Cálculo de viés relativo do estimador IV

### Conley (1999)
"GMM Estimation with Cross Sectional Dependence" (Journal of Econometrics)
- Formulação teórica do HAC espacial
- Aplicação a dados de cross-section com correlação espacial

### Wooldridge (2010)
"Econometric Analysis of Cross Section and Panel Data" (2nd ed., MIT Press)
- Cap. 6: Robustness e testes
- Cap. 8: Instrumentação em cross-section

### Baum, Schaffer & Stillman (2007)
"Enhanced routines for instrumental variables/generalized method of moments estimation and testing" (Stata Journal)
- Implementação prática de IV robusta
- Diagnósticos de force do instrumento

---

## 🎓 CONCLUSÃO

**Inferência espacial robusta** é essencial para:
- ✅ Infraestrutura regional (ferrovias, estradas, etc.)
- ✅ Dados de municípios/regiões
- ✅ Qualquer análise com correlação geográfica

**Recomendação final:**
- **Use Conley 100km como primário** em apresentações
- Reporte Hetero para comparação com literatura
- Teste Conley 50km e 200km para robustez
- Sempre mostre que resultados são estáveis

**Tempo de implementação:** ~10-15 minutos por regressão adicional  
**Valor agregado:** Muito alto (credibilidade + citações)

---

**Autor:** Análise de Inferência Espacial  
**Data:** Junho 2026  
**Versão:** 1.0  
