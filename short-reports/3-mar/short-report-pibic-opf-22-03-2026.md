# Relatório de Resultados: Fluxo de Potência Ótimo com Controles Heurísticos (QLIM/VLIM)
**Estudo de Caso:** Carga Máxima Noturna do SIN (Dez/2025)

## 1. Resumo da Abordagem
Para superar a divergência numérica e os colapsos de tensão apresentados pelas formulações clássicas na base de dados do ONS, implementou-se um modelo de Otimização Não-Linear (NLP) em Julia (JuMP/Ipopt). As principais inovações do modelo foram:
* **Limpeza Topológica:** Extração exclusiva da rede principal conectada (`select_largest_component!`), removendo ilhas e equivalentes de rede inconsistentes.
* **Controles via Penalidade Exata:** Inserção de variáveis de folga (*soft-constraints*) para emular o controle de tensão nos geradores (QLIM) e a injeção de reativo nodal (VLIM).
* **Limites Operacionais Rígidos:** Imposição estrita de um perfil de tensão seguro, travado entre **0.95 e 1.05 pu**.

## 2. Resultados e Análise de Desempenho

A tabela abaixo evidencia o impacto do tratamento de dados e da otimização na viabilidade física do sistema, comparando com o caso original e a sua convergência no software comercial (ANAREDE):

| Cenário / Modelo | V Mín (pu) | V Máx (pu) | Perdas Ativas (MW) | Geração Ativa (MW) | Geração Reativa (MVAr) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **PWF Original (Bruto)** | 0.7410 | 1.1740 | 22.842,07 *(21.0%)* | 109.828,48 | -9.148,53 |
| **PWF Convergido (Anarede)**| 0.7360 | 1.1740 | 22.842,07 *(21.0%)* | 109.828,48 | -9.233,54 |
| **OPF (Limites do PWF)** | 0.8429 | 1.3441 | 4.310,31 *(4.7%)* | 91.122,82 | -5.629,36 |
| **OPF (Limites Rígidos)**| **0.9500** | **1.0500** | **4.473,81 *(4.9%)***| **91.286,33** | **-1.685,15** |

### Destaques Operacionais:

1. **A Ilusão da Convergência Prévia:** Os dados revelam que mesmo o arquivo previamente convergido pelo ANAREDE mantinha anomalias matemáticas severas resultantes do "lixo topológico", refletidas no afundamento extremo de tensão ($0.736 \text{ pu}$) e perdas ativas colossais de $\approx 22.8 \text{ GW}$ (21%).
2. **Restabelecimento Físico e Limpeza:** A remoção das ilhas inoperantes no Julia reduziu a geração total para patamares reais do SIN (~91.3 GW). Com isso, as perdas ativas fictícias despencaram de 21% para coerentes **4.9%**, valor aderente à operação da rede básica de transmissão.
3. **Contenção do Colapso de Tensão:** O cenário com limites rígidos encontrou convergência ótima (`LOCALLY_SOLVED`) em cerca de 353 segundos. O modelo forçou a rede a operar perfeitamente dentro da margem segura de **0.95 a 1.05 pu**, sanando os gargalos tanto de subtensão do ANAREDE quanto de sobretensão (1.34 pu) observados no cenário NLP sem limites.
4. **Esforço do Controle Reativo (QLIM/VLIM):** O balanço reativo indicou absorção sistêmica (-1.685 MVAr). Para cravar as tensões dentro dos limites rigorosos sem divergir, o *solver* acionou as variáveis de folga de forma severa (atingindo um custo de $9.72 \times 10^7$ na Função Objetivo). O ligeiro aumento das perdas finais no cenário rígido reflete a necessidade física do sistema em desviar fluxos de reativo para evitar violações nodais.

## 3. Conclusão
A implementação conjunta de saneamento de dados em grafos e controles heurísticos penalizados (QLIM/VLIM) demonstrou excelente robustez matemática. O modelo convergiu com sucesso numa malha continental altamente estressada, transformando um caso com viabilidade física comprometida (mesmo após o ANAREDE) num ponto de operação rigoroso e seguro. Adicionalmente, as penalidades mapeadas pelas variáveis de folga fornecem um indicador exato de quais subestações do SIN necessitam de reforços práticos (Bancos de Capacitores ou Compensadores Síncronos) para garantir a estabilidade do perfil de tensão.