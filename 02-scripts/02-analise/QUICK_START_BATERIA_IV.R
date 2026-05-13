# ==============================================================================
# QUICK START: BATERIA DE TESTES IV
# ==============================================================================
# Execute este script para rodar a análise IV completa em 2 passos
# Tempo total: ~30-40 minutos
# ==============================================================================

cat("\n", strrep("=", 80), "\n")
cat("QUICK START: BATERIA COMPLETA DE TESTES IV\n")
cat("Pesquisa sobre Impacto de Ferrovias no Desenvolvimento Regional\n")
cat("Data:", format(Sys.time(), "%d/%m/%Y %H:%M:%S"), "\n")
cat(strrep("=", 80), "\n\n")

# ==============================================================================
# PRÉ-REQUISITOS
# ==============================================================================

cat("VERIFICANDO PRÉ-REQUISITOS...\n\n")

# Verificar arquivo de base integrada
if (!file.exists("base_completa_integrada.csv")) {
  stop(
    "❌ Erro: 'base_completa_integrada.csv' não encontrado!\n",
    "   Execute primeiro: source('0_MASTER_Criar_Todas_Bases.R')"
  )
}
cat("✓ Base integrada encontrada\n")

# Verificar ferrovias
if (!file.exists("ferrovias_cronologicas.gpkg")) {
  stop("❌ Erro: 'ferrovias_cronologicas.gpkg' não encontrado!")
}
cat("✓ Arquivo de ferrovias encontrado\n")

# Verificar população
if (!file.exists("população.xlsx")) {
  warning("⚠️ Aviso: 'população.xlsx' não encontrado. Tentando carregar de outro local...")
} else {
  cat("✓ Arquivo de população encontrado\n")
}

# Carregar objeto população se necessário
if (!exists("população")) {
  cat("   Carregando objeto 'população'...\n")
  library(readxl)
  população <- read_excel("população.xlsx")
  cat("   ✓ Objeto carregado\n")
}

cat("\n")

# ==============================================================================
# PASSO 1: EXECUTAR BATERIA DE TESTES
# ==============================================================================

cat(strrep("-", 80), "\n")
cat("PASSO 1: Executar Bateria de Testes IV\n")
cat(strrep("-", 80), "\n\n")

cat("Iniciando análise IV completa...\n")
cat("Isto pode levar 10-30 minutos.\n")
cat("Você verá atualizações de progresso no console.\n\n")

tempo_inicio <- Sys.time()

source("6_Bateria_Testes_Etapas_I_II.R")

tempo_1 <- difftime(Sys.time(), tempo_inicio, units = "mins")

cat(sprintf("\n✅ PASSO 1 CONCLUÍDO EM %.1f MINUTOS\n\n", tempo_1))

# ==============================================================================
# PASSO 2: VISUALIZAR E ANALISAR RESULTADOS
# ==============================================================================

cat(strrep("-", 80), "\n")
cat("PASSO 2: Visualizar e Analisar Resultados\n")
cat(strrep("-", 80), "\n\n")

cat("Criando gráficos, tabelas e relatórios...\n")
cat("Isto pode levar 2-5 minutos.\n\n")

tempo_inicio_2 <- Sys.time()

source("7_Visualizar_Resultados_IV.R")

tempo_2 <- difftime(Sys.time(), tempo_inicio_2, units = "mins")

cat(sprintf("\n✅ PASSO 2 CONCLUÍDO EM %.1f MINUTOS\n\n", tempo_2))

# ==============================================================================
# RESUMO FINAL
# ==============================================================================

tempo_total <- tempo_1 + tempo_2

cat(strrep("=", 80), "\n")
cat("🎉 ANÁLISE COMPLETA FINALIZADA COM SUCESSO!\n")
cat(strrep("=", 80), "\n\n")

cat(sprintf("TEMPO TOTAL: %.1f MINUTOS\n\n", tempo_total))

cat("ARQUIVOS GERADOS:\n\n")

cat("📊 RESULTADOS PRINCIPAIS:\n")
cat("  • resultados_bateria_iv.csv\n")
cat("    └─ Todos os coeficientes, p-values, F-stats\n\n")

cat("📈 GRÁFICOS:\n")
cat("  • grafico_coeficientes_ss.png\n")
cat("  • grafico_f_stat.png\n")
cat("  • grafico_p_values.png\n")
cat("  • grafico_f_vs_coef.png\n\n")

cat("📋 TABELAS HTML (para abrir no navegador):\n")
cat("  • tabela_resultados_por_outcome.html\n")
cat("  • tabela_resultados_por_tratamento.html\n")
cat("  • tabela_f_estatistico.html\n\n")

cat("📌 RESUMOS EM CSV:\n")
cat("  • resumo_por_especificacao.csv\n")
cat("  • resumo_por_tratamento.csv\n\n")

# ==============================================================================
# PRÓXIMOS PASSOS
# ==============================================================================

cat(strrep("-", 80), "\n")
cat("PRÓXIMOS PASSOS:\n")
cat(strrep("-", 80), "\n\n")

cat("1. REVISAR GRÁFICOS:\n")
cat("   Os gráficos PNG foram salvos no seu diretório de trabalho.\n")
cat("   Abra-os para visualizar padrões nos dados.\n\n")

cat("2. ABRIR TABELAS HTML:\n")
cat("   Use um navegador para abrir os arquivos .html\n")
cat("   Eles contêm tabelas formatadas e prontas para publicação.\n\n")

cat("3. ANALISAR FORÇA DO INSTRUMENTO:\n")
cat("   Procure pela coluna 'f_stat' em resultados_bateria_iv.csv\n")
cat("   F > 10:  instrumento forte ✓\n")
cat("   F < 10:  instrumento fraco ⚠️\n\n")

cat("4. DOCUMENTAR ACHADOS:\n")
cat("   Compare coeficientes entre especificações\n")
cat("   Verifique robustez (efeitos fixos, exclusão de pontas)\n")
cat("   Documente os resultados estatisticamente significativos\n\n")

cat("5. (OPCIONAL) PERSONALIZAÇÕES:\n")
cat("   Ver 'README_BATERIA_TESTES_IV.md' para:\n")
cat("   • Adicionar novos outcomes\n")
cat("   • Adicionar novas especificações amostrais\n")
cat("   • Modificar limiares de atendimento\n\n")

# ==============================================================================
# QUICK REFERENCE
# ==============================================================================

cat(strrep("=", 80), "\n")
cat("QUICK REFERENCE - O QUE FOI TESTADO\n")
cat(strrep("=", 80), "\n\n")

cat("ESPECIFICAÇÕES AMOSTRAIS:\n")
cat("  1. Amostra completa\n")
cat("  2. Amostra completa + Efeitos Fixos de Estado\n")
cat("  3. Distância ≤200km + Efeitos Fixos de Estado\n")
cat("  4. Distância ≤200km + Excluindo Pontas + Efeitos Fixos\n\n")

cat("TIPOS DE TRATAMENTO:\n")
cat("  1. Distância até ferrovia (km)\n")
cat("  2. Dummy de atendimento (1 se ≤25 km)\n")
cat("  3. Densidade de ferrovias (km/1000km²)\n\n")

cat("OUTCOMES ANALISADOS:\n")
cat("  1. População 2003\n")
cat("  2. População 2010\n")
cat("  (PIB - se arquivo disponível)\n\n")

cat("TOTAL DE ESPECIFICAÇÕES: ", "4 especificações × 3 tratamentos × 2 outcomes = 24 regressões\n\n")

# ==============================================================================
# DÚVIDAS FREQUENTES
# ==============================================================================

cat(strrep("-", 80), "\n")
cat("DÚVIDAS FREQUENTES (FAQ)\n")
cat(strrep("-", 80), "\n\n")

cat("P: Quanto tempo leva para executar?\n")
cat("R: 30-40 minutos no total (depende da máquina e tamanho dos dados)\n\n")

cat("P: O que significa 'F-stat < 10'?\n")
cat("R: Significa instrumento fraco. Ver Stock & Yogo (2005).\n")
cat("   Isso pode enviesar os estimadores. Seja cauteloso na interpretação.\n\n")

cat("P: Posso modificar as análises?\n")
cat("R: Sim! Ver 'README_BATERIA_TESTES_IV.md' para personalizações.\n")
cat("   Você pode adicionar outcomes, especificações, mudar limiares, etc.\n\n")

cat("P: Como interpreto os coeficientes?\n")
cat("R: log(outcome) está na regressão, então coef = elástica.\n")
cat("   Ex: coef = 0.15 significa 15% de aumento no outcome.\n\n")

cat("P: Quais são as principais preocupações econométricas?\n")
cat("R: 1. Força do instrumento (F-stat > 10 ideal)\n")
cat("   2. Causalidade reversa (rede sintética resolve isso)\n")
cat("   3. Variáveis omitidas (efeitos fixos ajudam)\n")
cat("   4. Heterogeneidade (testar por subgrupos)\n\n")

# ==============================================================================
# CONTATO E SUPORTE
# ==============================================================================

cat(strrep("=", 80), "\n")
cat("Para dúvidas ou problemas:\n")
cat(strrep("=", 80), "\n\n")

cat("1. Consulte 'README_BASES_DADOS.md' (estrutura das bases)\n")
cat("2. Consulte 'README_BATERIA_TESTES_IV.md' (especificações)\n")
cat("3. Revisar arquivos de log no console (scroll para cima)\n\n")

cat(strrep("=", 80), "\n")
cat("Análise finalizada em:", format(Sys.time(), "%d/%m/%Y %H:%M:%S"), "\n")
cat(strrep("=", 80), "\n\n")
