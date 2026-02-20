# Análise de Fluxo de Potência no SIN Comparação de Formulações Não-Lineares e Relaxadas

## Estudo de Caso: Carga Máxima Noturna - Dez/2025

Data: 5 de fevereiro de 2026

## Resumo

Este relatório apresenta os resultados da execução do fluxo de potência no Sis-
tema Interligado Nacional (SIN) utilizando a biblioteca PowerModels.jl. Foram
comparadas quatro formulações matemáticas: ACP (Polar), ACR (Retangular),
DCP (Linear) e SOCWR (Relaxação Cônica). Os resultados evidenciam os desafios
numéricos de sistemas de grande porte sob carga pesada, demonstrando divergências
significativas entre as formulações exatas e relaxadas quanto à viabilidade física das
soluções encontradas.

## Introdução

A operação de sistemas complexos como o SIN exige ferramentas robustas de cálculo
de fluxo de potência. O objetivo deste estudo é avaliar o comportamento de diferentes
formulações matemáticas disponíveis no pacote PowerModels.jl ao processar o caso `01
MAXIMA NOTURNA_DEZ25.PWF`, focando em convergência, perfil de tensão e coerência dos
dados de geração.

## Metodologia

As simulações foram realizadas em linguagem Julia, utilizando o solver Ipopt. O processo
consistiu na leitura do arquivo PWF, conversão para dicionário de dados e execução da
função run_pf para os seguintes modelos:

- ACPPowerModel: Modelo AC exato em coordenadas polares (|V |, θ).
- ACRPowerModel: Modelo AC exato em coordenadas retangulares (Vre, Vim).
- SOCWRPowerModel: Relaxação convexa de segunda ordem (Second-Order Cone).
- DCPPowerModel: Aproximação linear DC (Lossless, V = 1.0).

## Resultados e Discussão

A Tabela 1 sumariza os indicadores globais extraídos das simulações.

Tabela 1: Comparativo dos Resultados de Convergência

| Modelo | V Mín (pu) | Perdas Ativas (Total pu) | Geração Ativa (Total pu) | Geração Reativa (Total pu) | Status Físico  |
| :----- | :--------- | :----------------------- | :----------------------- | :------------------------- | :------------- |
| ACP    | -1.915\*   | 168.46                   | 1092.95                  | 191.73                     | Inválido       |
| ACR    | 0.741      | 949.41                   | 1122.74                  | 225.10                     | Crítico        |
| SOCWR  | 0.741      | 949.41                   | 2380.43                  | -21320.30                  | Relaxado (Gap) |
| DCP    | 0.956      | 1258.76                  | 1061.94                  | -23.92                     | Simplificado   |

(\*) Tensão negativa indica convergência para mínimo local matemático sem sentido físico.

### Análise de Tensão e Perdas

O modelo **ACP (Polar)** convergiu para uma solução com tensões negativas, um pro-
blema conhecido em formulações não-convexas polares quando a inicialização não é pró-
xima da solução real.

O modelo **ACR (Retangular)** convergiu para uma solução fisicamente viável (ten-
sões positivas), porém indicando um sistema em estado de colapso de tensão. O valor
Vmin = 0.74 pu é extremamente baixo, resultando em perdas de transmissão massivas
(949 pu), sugerindo que quase toda a geração está sendo consumida nas linhas de trans-
missão.

### Análise de Geração (O Paradoxo SOCWR)

Aqui observamos a maior discrepância.

- No modelo **ACR**, a geração total foi de apenas 1122 pu. Como as perdas foram
  de 949 pu, isso implica que a carga atendida foi muito baixa (≈ 173 pu). Isso ocorre
  porque as cargas no arquivo PWF provavelmente são dependentes da tensão; com
  a tensão em 0.74 pu, a demanda "caiu"drasticamente.
- No modelo **SOCWR**, embora o perfil de tensão tenha sido idêntico ao ACR,
  a geração ativa saltou para 2380 pu e a reativa para um valor absurdo de -21.320
  pu. Isso indica que a relaxação não foi exata (non-tight). O modelo cônico
  "criou"fluxos de potência reativa fictícios para satisfazer as restrições matemáticas,
  permitindo "atender"uma carga maior (fictícia) que o modelo físico (ACR) não
  conseguiria.
