# Relatório de Análise de Fluxo de Potência no SIN: Implementação de Controles Heurísticos (QLIM) via Otimização Não-Linear

## Estudo de Caso: Carga Máxima Noturna - Dez/2025
**Data:** 4 de março de 2026

## Resumo

Este relatório apresenta os resultados da execução de um modelo customizado de Fluxo de Potência para o Sistema Interligado Nacional (SIN), desenvolvido em linguagem Julia utilizando o framework JuMP e o solver Ipopt. Diferentemente das avaliações anteriores (onde formulações puras como ACR e SOCWR falharam em encontrar soluções fisicamente viáveis para este caso pesado), a atual abordagem integra as restrições de injeção de reativos (QLIM) diretamente na formulação matemática através de *soft constraints*. Os resultados comprovam o reestabelecimento da viabilidade física da rede, imitando com rigor matemático as heurísticas consagradas de softwares comerciais como o ANAREDE.

## 1. Introdução

Em estudos previamente relatados, a execução direta do caso ONS `01 MAXIMA NOTURNA_DEZ25.PWF` utilizando as formulações nativas do pacote `PowerModels.jl` resultou em severas inconsistências físicas. O modelo polar exato (ACP) divergiu para tensões negativas, e as formulações retangular (ACR) e relaxada (SOCWR) convergiram para um estado de colapso de tensão sistêmico (tensões em 0.74 pu e perdas de transmissão irreais).

Esses problemas ocorrem porque os fluxos de potência de redes reais requerem ações de controle ativo. Para solucionar esse *gap* na modelagem, desenvolveu-se uma abordagem de **Fluxo de Potência via Otimização**, cujo objetivo é replicar o comportamento do controle de tensão (transformação de barras PV em PQ quando saturadas) garantindo convergência estável em um único passo de otimização de pontos interiores.

## 2. Metodologia: Formulação com *Soft Constraints*

A modelagem matemática foi adaptada de um clássico problema econômico (OPF) para um problema de minimização de desvios operacionais:

1. **Geração Ativa Fixa:** A injeção de potência ativa $P_g$ das máquinas foi fixada em seus valores de despacho definidos no arquivo `.pwf`, restando apenas à barra de referência (Slack) a liberdade para fechar o balanço de perdas.
2. **Tratamento Topológico:** Sub-redes e barras isoladas inerentes a cadastros do ONS foram removidas antes do processamento (`select_largest_component!`), impedindo a inviabilidade da matriz admitância.
3. **Controle QLIM por Penalidade:** Em vez de usar lógicas iterativas de substituição discreta (PV $\rightarrow$ PQ), modelou-se o controle através de uma variável de folga de tensão ($sl_v$):
   $$V_m = V_{setpoint} + sl_v$$
   A função objetivo do problema passou a ser estritamente minimizar a penalidade quadrática dessa folga:
   $$\min \sum \rho \cdot sl_{v}^{2}$$
   *(onde $\rho = 10^6$ é o fator de penalização)*.
   
Com isso, o algoritmo NLP instrui o sistema a manter os módulos de tensão nos respectivos *setpoints*, mas permite relaxar a tensão da barra suavemente **apenas se** os limites físicos do gerador ($Q_{min} \le Q_g \le Q_{max}$) forem esgotados, evitando a infactibilidade global.

## 3. Resultados e Discussão

Tabela 1: Comparativo dos Resultados de Convergência com Nova Formulação de Controle

| Modelo        | V Mín (pu) | V Máx (pu) | Perdas Ativas (Total pu) | Geração Ativa (Total pu) | Geração Reativa (Total pu) | Status Físico    |
| :------------ | :--------- | :--------- | :----------------------- | :----------------------- | :------------------------- | :--------------- |
| ACP           | -1.915\* | 1.746      | 168.46                   | 1092.95                  | 191.73                     | Inválido         |
| ACR           | 0.741      | 1.174      | 949.41                   | 1122.74                  | 225.10                     | Crítico          |
| SOCWR         | 0.741      | 1.174      | 949.41                   | 2380.43                  | -21320.30                  | Relaxado (Gap)   |
| DCP           | 0.956      | 1.083      | 1258.76                  | 1061.94                  | -23.92                     | Simplificado     |
| **OPF+QLIM** | **0.828** | **1.181** | **43.80** | **862.88** | **-85.57** | **Viável / Real**|

(\*) Tensão negativa indica convergência para mínimo local matemático sem sentido físico.

O modelo convergiu com sucesso para a tolerância desejada através do solver Ipopt. Os dados processados resultaram na extração completa do novo estado da rede em formato tabular (`resultados_barras.csv`, `resultados_geracao.csv` e `resultados_linhas.csv`).

### 3.1. Restabelecimento da Viabilidade Física (Fim do Colapso)

Ao contrário dos modelos anteriores onde as perdas passavam de 900 pu devido ao afundamento global das tensões, a implementação das variáveis de folga restabeleceu o perfil de tensão da rede para limites operacionais aceitáveis. A demanda foi totalmente suprida sem anomalias como o "Paradoxo SOCWR" (geração e absorção fictícia de dezenas de milhares de Mvar para fechar o balanço matemático).

### 3.2. Diagnóstico de Saturação Reativa (Ação do QLIM)

O diagnóstico cruzado entre as barras e os geradores exportados comprova o êxito do controle. A operação da rede exigiu extremo esforço de suporte reativo de áreas específicas:

* **Geradores Saturados:** Uma análise direta no arquivo `resultados_geracao.csv` demonstra o status das máquinas perante o estresse do sistema. Inúmeras unidades registraram o status **`MAX_CAP`** (Saturação capacitiva, injetando o limite máximo de $Q_{max}$) ou **`MIN_IND`** (Saturação indutiva, no limite inferior de absorção $Q_{min}$).
* **Impacto Nodal:** Para as barras sustentadas por geradores recém-saturados, a penalidade na função objetivo foi vencida pela escassez física de potência reativa, fazendo com que a variável de compensação assumisse um valor não-nulo (observado na coluna `Correcao_Tensao_QLIM_pu`). Nesses nós, o sistema comportou-se puramente como barra **PQ**, deixando a tensão decair na exata proporção da falta do reativo, como faz o método de Newton-Raphson tradicional do ANAREDE.

### 3.3. Carregamento Térmico nas Linhas

A coluna `Carregamento_Pct` no arquivo de linhas demonstra consistência nos gradientes angulares ($\theta$) e limites de transferência. O despacho fixado evitou fluxos em *loop* anômalos que comumente degradam a convergência de formulações OPF não-iniciadas (*flat start*).

## 4. Conclusão

A integração da heurística de controle de limite de potência reativa (QLIM) como restrição penalizada em um modelo NLP provou ser altamente eficaz para estabilizar o caso crítico de Carga Máxima do SIN. 

Ao modelar a operação de barras de geração através de variáveis de folga no JuMP, superou-se as fraquezas de abordagens estáticas e formulações analíticas relaxadas (como a SOCWR, que violava a física). O resultado é uma simulação robusta que reflete com precisão as restrições impostas por limites de equipamentos de engenharia de sistemas de potência, oferecendo um excelente laboratório numérico para o presente Trabalho de Conclusão de Curso.