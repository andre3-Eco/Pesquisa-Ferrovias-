# ==============================================================================
# COMECE AQUI: CRIAR E USAR AS BASES DE DADOS
# ==============================================================================
# Este script mostra exatamente o que fazer para criar e usar as bases
# ==============================================================================

# Se é a PRIMEIRA VEZ que está criando as bases, execute este bloco inteiro:

# ============================================================================
# 🔴 PRIMEIRA EXECUÇÃO: CRIAR TODAS AS BASES (execute tudo abaixo)
# ============================================================================

# PASSO 1: Defina o diretório de trabalho (se necessário)
# setwd("C:/Users/André Elias/Documents")  # Descomente se precisar

# PASSO 2: Execute o MASTER script que cria tudo
# ⏱️ Isso vai levar ~60 minutos. NÃO INTERROMPA!
source("0_MASTER_Criar_Todas_Bases.R")

# PASSO 3: Quando terminar, valide as bases criadas
# ⏱️ Isso vai levar ~2 minutos
source("5_Validar_Bases_Criadas.R")

# Se viu "✅ TUDO OK!" no resultado, parabéns! Siga para próximas etapas.
# Se viu ❌, revise erros e execute novamente.

# ============================================================================
# 🟢 AGORA VOCÊ TEM AS BASES! USE-AS EM SUAS ANÁLISES
# ============================================================================

# Opção A: Usar a base CSV (mais lenta)
base <- read.csv("base_completa_integrada.csv")

# Opção B: Usar a base RDS (mais rápida) - RECOMENDADO
base <- readRDS("base_completa_integrada.rds")

# Pronto! Agora você tem uma base com ~730 AMCs × ~1700 variáveis

# ============================================================================
# 📊 EXEMPLOS DE USO RÁPIDO
# ============================================================================

# Ver estrutura
head(base[, 1:10])  # Primeiras linhas e colunas
dim(base)           # Dimensões
names(base)[1:20]   # Nomes das colunas

# Estatísticas
summary(base$dist_rail_sintetica_km)
summary(base$dist_rail_real_2003)
summary(base$densidade_sintetica)
summary(base$dummy_atendida_sintetica)

# ============================================================================
# 🔬 ANÁLISES SIMPLES
# ============================================================================

library(tidyverse)
library(fixest)  # Para regressões com IV

# Regressão simples: efeito de atendimento na população
lm(log(pop_2003) ~ dummy_atendida_real_2003, data = base)

# Regressão com densidade
lm(log(pop_2003) ~ densidade_real_2003, data = base)

# IV: usar sintética como instrumento para real
feols(log(pop_2003) ~ 1 | 
      dist_rail_real_2003 ~ dist_rail_sintetica_km, 
      data = base)

# ============================================================================
# 📁 O QUE FOI CRIADO?
# ============================================================================

# 8 ARQUIVOS PRINCIPAIS:
# 1. base_distancias_amcs_nordeste_semmar.csv      ← Distâncias
# 2. base_dummy_atendimento_simples.csv             ← Dummies
# 3. base_densidade_simplificada.csv                ← Densidade
# 4. base_completa_integrada.csv                    ← TUDO JUNTO (use isto)
# 5. base_completa_integrada.rds                    ← Versão R (use isto)
# 6. base_completa_data_dictionary.csv              ← Dicionário de variáveis
# 7. README_BASES_DADOS.md                          ← Documentação completa
# 8. GUIA_RAPIDO.txt                                ← Referência rápida

# ============================================================================
# 🔍 SE JÁ CRIOU AS BASES ANTES...
# ============================================================================

# Apenas carregue e use:

base <- readRDS("base_completa_integrada.rds")

# Pronto! Comece a analisar.

# ============================================================================
# 📚 DOCUMENTAÇÃO
# ============================================================================

# Para ENTENDER as variáveis:
# → Abra: README_BASES_DADOS.md
# → Ou: base_completa_data_dictionary.csv

# Para REFERÊNCIA RÁPIDA:
# → Abra: GUIA_RAPIDO.txt

# Para TROUBLESHOOTING:
# → Abra: GUIA_RAPIDO.txt (seção Problemas Comuns)

# ============================================================================
# ❓ VARIÁVEIS PRINCIPAIS
# ============================================================================

# Cada AMC tem:

# SINTÉTICA (estática):
# - dist_rail_sintetica_km          Distância até rede sintética
# - dummy_atendida_sintetica        1 se atendida (≤25 km)
# - densidade_sintetica             km de ferrovia por 1000 km²

# REAL (cronológica, para cada ano de 1858 a 2003):
# - dist_rail_real_YYYY             Distância até rede até ano YYYY
# - dummy_atendida_real_YYYY        1 se atendida até ano YYYY
# - densidade_real_YYYY             Densidade de ferrovia até YYYY

# Exemplo de nomes:
# dist_rail_real_1880, dist_rail_real_1900, ..., dist_rail_real_2003
# dummy_atendida_real_1880, ..., dummy_atendida_real_2003
# densidade_real_1880, ..., densidade_real_2003

# ============================================================================
# 🚀 PRÓXIMAS ANÁLISES
# ============================================================================

# 1. EXECUTAR IV_Analise_Completa_SemMar.R com esta base:
source("IV_Analise_Completa_SemMar.R")

# 2. Ou fazer suas próprias análises:
library(fixest)
library(tidyverse)

base <- readRDS("base_completa_integrada.rds")

# Análise por período
resultados <- base %>%
  select(code_amc, starts_with("dummy_atendida_real_")) %>%
  pivot_longer(-code_amc) %>%
  mutate(ano = as.numeric(gsub("dummy_atendida_real_", "", name)))

# Event study, painel, spatial... o que você quiser!

# ============================================================================
# ✅ CHECKLIST FINAL
# ============================================================================

# Antes de começar análises definitivas:
# 
# □ Executei 0_MASTER_Criar_Todas_Bases.R?
# □ Executei 5_Validar_Bases_Criadas.R e viu ✅?
# □ Carreguei a base com readRDS("base_completa_integrada.rds")?
# □ Verifiquei dim(base), head(base), summary(base)?
# □ Li o README_BASES_DADOS.md para entender as variáveis?
# □ Testei uma regressão simples para garantir que funciona?
#
# Se SIM em todas: você está pronto! 🎉

# ============================================================================
# 🔥 DÚVIDAS FREQUENTES
# ============================================================================

# P: Quanto tempo leva para criar as bases?
# R: ~60 minutos (Script 3 é pesado). NÃO INTERROMPA.

# P: Preciso criar novamente toda vez que abro o R?
# R: NÃO! Crie uma única vez. Depois apenas carregue com readRDS.

# P: Qual base usar?
# R: Sempre use: base_completa_integrada.rds ou .csv (já integra tudo)

# P: Posso alterar o limiar de 25 km?
# R: Sim! Edit o script 2_Criar_Base_Dummy_Atendimento.R, linha ~20

# P: Os dados são de que período?
# R: Real: 1858-2003 (cronológico). Sintética: estática.

# P: As distâncias são em linha reta ou pela rede?
# R: Real: pela rede (distância mais próxima). Sintética: também pela rede.

# P: Posso usar para análises de impacto?
# R: SIM! Use dummy_atendida_real_YYYY como tratamento.
#    Use dist_rail_sintetica_km como instrumento.

# ============================================================================
# 💾 ÚLTIMA DICA: SALVE SEUS RESULTADOS
# ============================================================================

# Depois de fazer análises, salve em novo arquivo:

# meus_resultados <- tibble(...)
# write.csv(meus_resultados, "meus_resultados_2026_05.csv")

# Não sobrescreva os arquivos originais!

# ============================================================================
# Tudo pronto! Comece a analisar! 🚀
# ============================================================================
