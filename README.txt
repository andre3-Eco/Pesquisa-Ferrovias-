# Motores a Vapor no Sertão: Infraestrutura de Transporte e Adoção Tecnológica de Longo Prazo no Nordeste Brasileiro (1870–2010)

**Autores:** André Elias Lopes (PIMES-UFPE) e Diego Firmino Costa da Silva (DE-UFRPE/PIMES-UFPE)  
**Data:** 25 de junho de 2026  
**Área:** Economia Regional  

---

## Visão geral do projeto
Este projeto estima os efeitos de longo prazo da exposição ferroviária histórica sobre desenvolvimento econômico, população, estrutura produtiva, urbanização e indicadores sociais no Nordeste brasileiro. Adota a estratégia de densidade histórica de infraestrutura de Baerlocher et al. (2026), medindo a fração de cada Área Mínima Comparável (AMC) coberta por um buffer de 5 km ao redor da malha ferroviária real acumulada e instrumentando essa exposição pela densidade análoga de uma malha sintética construída por caminhos de menor custo (LCP) baseada em topografia.

---

## Referencial teórico
- **Infraestrutura como motor de desenvolvimento:** Redução de custos de transporte aumenta o acesso a mercados, favorece a adoção de tecnologia pesada (máquinas, caldeiras) e gera economias de aglomeração.  
- **Mecanismos causais:** Acesso ferroviário reduz custos de frete, amplia o acesso ao mercado, atraí capital e trabalho, e cria centralidades urbanas persistentes por meio de sunk costs e complementaridades locais.  
- **Endogeneidade e identificação:** A localização não aleatória das ferrovias é abordada usando instrumentos exógenos (LCP sintético) que capturam apenas a variação topográfica, isolando o efeito causal da infraestrutura.  
- **Efeitos espaciais e heterogeneidade:** Os impactos variam conforme as condições iniciais (isolamento, necessidade de transporte) e podem gerar tanto crescimento genuíno quanto realocação espacial; a análise utiliza modelos espaciais (SDM) e estratificação por raios de buffer.  
- **Contexto do Nordeste:** Região de histórico atraso, baixa integração e escassez de investimentos ferroviários, onde os efeitos da infraestrutura são potencialmente maiores devido à alta elasticidade da demanda em áreas com custos prévios elevados de transporte.

---

## Estratégia empírica
- **Variável de tratamento:** Densidade de buffer ferroviário real (`densidade_buffer_real_t`) = fração da área da AMC dentro de um buffer de 5 km da malha ferroviária acumulada até o ano *t*.  
- **Instrumento:** Densidade de buffer sintético por LCP (`densidade_buffer_sintetica_t`), construído análogamente usando uma malha ferroviária hipotética que minimiza o custo de construção com base apenas em declividade e barreiras naturais (DEM/SRTM).  
- **Controles:** Efeitos fixos de estado (UF), variáveis climáticas (WorldClim: bio_1, bio_12, bio_15), hidrográficas (distância ao rio, densidade hidrológica) e pedológicas (proporções de latossolos e neossolos).  
- **Outcomes:** PIB total e per capita, PIB setorial (agropecuário, industrial, serviços), população, taxa de urbanização, IDHM geral e sua componente de renda.  
- **Estimativa:** Modelo de variáveis instrumentais em dois estágios (2SLS) com erros-padrão robustos à heterocedasticidade. O primeiro estágio regressa a densidade real sobre o sintético e controles; o segundo estágio substitui a densidade real pela sua componente prevista.  
- **Análise de persistência:** Combina tratamentos históricos (ex.: 1858, 1969) com outcomes contemporâneos fixos (PIB 2010, população 2010) para testar efeitos de longo prazo.  
- **Robustez:** Testes com inferência espacial (erros clusterizados por microrregião e Conley com cortes de 50–200 km) e placebo temporal (densidade ferroviária futura não prediz outcomes passados).  

---

## Dados
- **`01-dados/brutos/`**: Dados brutos (IBGE, IPEADATA, SIDRA, rasters topográficos).  
- **`01-dados/processados/`**: Dados processados pelos scripts de preparação. Arquivos-chave:  
  - `base_completa_integrada_buffer.csv/.rds`: mesa mestra (tratamento, controles, outcomes).  
  - `outcomes/outcomes_amc_wide.csv/.rds`: outcomes harmonizados por AMC e ano.  
  - `base_densidade_buffer_*.csv`: densidade de buffer real e sintético por raio e ano.  
- **`05-geometrias/`**: GeoPackages com malhas ferroviárias (real, sintética por LCP), AMCs, hidrografia.  
- **`04-documentacao/`**: Metodologia e dicionários:  
  - `GUIA_INFERENCIA_ESPACIAL_ROBUSTA.md` – boas práticas para modelos espaciais.  
  - `DOCUMENTACAO_BATERIA_9.md` – descrição dos testes de robustez.  
  - `DICIONARIO_OUTCOMES.md` – definições e fontes das variáveis de outcome.  
  - `Dicionário de Dados Projeto Ferrovi.txt` – dicionário completo da base processada.  

---

## Scripts
- **`02-scripts/01-preparacao/`**: Preparação dos dados.  
  - `0_MASTER_Criar_Base_Buffer_Unificada.R`: orquestra a criação da base final (chama os scripts abaixo).  
  - `base_buffer.R`: gera densidade de buffer (real/sintético) para múltiplos raios.  
  - `8_controles_clima.R`, `9_controles_solo.R`, `10_controles_rios.R`: extrai controles ambientais.  
  - `7_Extrair_Outcomes_Desenvolvimento.R`: harmoniza outcomes (PIB, população, IDH, PAM) ao nível AMC.  
- **`02-scripts/02-analise/`**: Análise econométrica.  
  - `second_stage_multiraio.R`: 2SLS com múltiplos raios de buffer (saída: `03-resultados/csv/second_stage_multiraio.csv`).  
  - Scripts de primeiro estágio, placebo temporal, modelos espaciais e event study estão disponíveis no mesmo diretório.  
- **`02-scripts/exploratoria/`**: scripts exploratórios (cálculo de LCP, superfícies de custos).  

---

## Como reproduzir
1. Abra o projeto RStudio (`Pesquisa (Ferrovias).Rproj`).  
2. Instale os pacotes necessários (se ainda não instalados):  
   ```R
   install.packages(c("tidyverse","sf","geobr","fixest","ipeadatar","sidrar","readr","stringr","spdep","spml","rgdal","raster"))
   ```  
3. Gere a base de dados processada:  
   ```R
   source("02-scripts/01-preparacao/0_MASTER_Criar_Base_Buffer_Unificada.R")
   ```  
   Isso cria `01-dados/processados/base_completa_integrada_buffer.csv` e o arquivo de outcomes.  
4. Execute a estimativa principal (exemplo: 2SLS multi‑raio):  
   ```R
   source("02-scripts/02-analise/second_stage_multiraio.R")
   ```  
   Os resultados aparecerão em `03-resultados/csv/second_stage_multiraio.csv`.  
5. Para outras análises (placebo, event study, SDM), sourceie os scripts correspondentes em `02-scripts/02-analise/`.  

---

## Saídas esperadas
- **Tabelas de regressão** (CSV) com coeficientes IV, erros-padrão, estatísticas F do primeiro estágio e R² para cada combinação de raio/ano/outcome.  
- **Mapas** (PNG) em `03-resultados/mapas/` mostrando redes ferroviárias reais/sintéticas, intensidade de tratamento e heterogeneidade espacial dos efeitos.  
- **Diagnósticos de robustez**: resultados de inferência espacial e placebo temporal.  

---

## Documentação adicional
Consulte a pasta `04-documentacao/` para:  
- Orientações sobre modelagem espacial robusta.  
- Descrição detalhada dos nove testes de robustez realizados.  
- Dicionário de variáveis de outcomes e da base processada.  

---

## Contato
**André Elias Lopes** – andre.elias@ufpe.com  
**Diego Firmino Costa da Silva** – diego.firmino@ufrpe.br  
Telefones: André (87) 9 9197-5842 | Diego (81) 9 8228-7013  
*Instituições: PIMES-UFPE, DE-UFRPE*  
25 de junho de 2026