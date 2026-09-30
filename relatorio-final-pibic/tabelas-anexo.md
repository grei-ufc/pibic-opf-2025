---
title: "Anexo — Tabelas de Resultados Experimentais"
subtitle:
  "Projeto PIBIC 13439: Aplicação de Técnicas de Otimização Convexa em Fluxo de
  Potência Ótimo"
author:
  - "Bolsista: Gabriel Rufino Montenegro (Graduação em Engenharia Elétrica)"
  - "Orientador: Prof. Dr. Lucas Silveira Melo (Departamento de Engenharia
    Elétrica / CT)"
date: "Setembro de 2026"
geometry: "margin=1.5cm, landscape"
papersize: a4
lang: pt-BR
fontsize: 10pt
mainfont: EB Garamond
linestretch: 1.15
documentclass: article
header-includes:
  - \usepackage{booktabs}
  - \usepackage{longtable}
  - \usepackage{amsmath}
  - \usepackage{amssymb}
  - \usepackage{microtype}
  - \usepackage{fancyhdr}
  - \pagestyle{fancy}
  - \fancyhf{}
  - \fancyhead[L]{\small PIBIC UFC 2025/2026 — Anexo de Tabelas}
  - \fancyhead[R]{\small FPO em Julia / JuMP}
  - \fancyfoot[C]{\thepage}
---

# Apresentação do Anexo Técnico

Este documento reúne o conjunto consolidado de tabelas geradas a partir da
bateria experimental de simulações do projeto de pesquisa PIBIC (Edital Nº
02/2025, Projeto 13439), intitulado _Aplicação de Técnicas de Otimização Convexa
em Fluxo de Potência Ótimo_. As simulações comparam as seis formulações de fluxo
de potência em corrente alternada (F0 a F5) e a formulação linearizada auxiliar
(FDC) sobre 27 sistemas elétricos no formato PWF, abrangendo redes pedagógicas,
sistemas IEEE, recortes reais do subsistema Nordeste e o cenário integral do
Sistema Interligado Nacional (SIN).

---

## Tabela 1: Resumo numérico global de status de convergência das formulações

Síntese do desempenho global das seis formulações AC sobre o universo de 27
casos de teste avaliados, quantificando ocorrências de convergência factível
(OK), infactibilidade local (INF), interrupção por tempo limite (KIL), modelo
inválido (INV) e erros de sintaxe no _parser_ de dados PWF (ERR).

| Indicador Operacional        | F0 (OPF-PM) | F1 (PF-PM) | F2 (QLIM+VLIM) | F3 (+CSCA) | F4 (+CTAP) | F5 (+DERA) |
| :--------------------------- | :---------: | :--------: | :------------: | :--------: | :--------: | :--------: |
| Casos Convergidos (OK)       | 15 (55,6%)  | 18 (66,7%) |   23 (85,2%)   | 23 (85,2%) | 23 (85,2%) | 23 (85,2%) |
| Infactibilidade Local (INF)  |  6 (22,2%)  | 5 (18,5%)  |    0 (0,0%)    |  1 (3,7%)  |  0 (0,0%)  |  1 (3,7%)  |
| Tempo Limite Excedido (KIL)  |  1 (3,7%)   |  0 (0,0%)  |    1 (3,7%)    |  0 (0,0%)  |  1 (3,7%)  |  0 (0,0%)  |
| Modelo Inválido (INV)        |  1 (3,7%)   |  0 (0,0%)  |    0 (0,0%)    |  0 (0,0%)  |  0 (0,0%)  |  0 (0,0%)  |
| Erro de Leitura/Parser (ERR) |  4 (14,8%)  | 4 (14,8%)  |   3 (11,1%)    | 3 (11,1%)  | 3 (11,1%)  | 3 (11,1%)  |
| Total de Casos Avaliados     |  27 (100%)  | 27 (100%)  |   27 (100%)    | 27 (100%)  | 27 (100%)  | 27 (100%)  |

\newpage

## Tabela 2: Mapeamento de convergência e particionamento de clusters por sistema testado

Status individualizado de cada sistema e particionamento em _clusters_ de
equivalência operativa entre as formulações que convergiram. Critério de
equivalência: desvio máximo $|\Delta| \le 10^{-4}$ p.u. simultaneamente em
tensão ($V$), ângulo ($\theta$), geração ativa e reativa ($P^g, Q^g$) e fluxos
de ramo. A notação $\{A,B\} \cdot \{C\}$ indica que $A$ e $B$ atingiram a mesma
solução, enquanto $C$ atingiu ponto operativo numericamente distinto.

| Caso de Teste (.pwf)         | Barras |  F0  | F1  | F2  | F3  | F4  | F5  | Particionamento em Clusters Operativos                                                  |
| :--------------------------- | :----: | :--: | :-: | :-: | :-: | :-: | :-: | :-------------------------------------------------------------------------------------- |
| `3bus`                       |   3    |  OK  | OK  | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F1,F2}\}\cdot\{\text{F3,F4,F5}\}$                            |
| `3bus_DBSH`                  |   3    |  OK  | OK  | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F1,F2}\}\cdot\{\text{F3,F4,F5}\}$                            |
| `3bus_DCER`                  |   3    |  OK  | OK  | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F1,F2}\}\cdot\{\text{F3,F4,F5}\}$                            |
| `3bus_DCSC`                  |   3    |  OK  | OK  | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F1}\}\cdot\{\text{F2}\}\cdot\{\text{F3,F4,F5}\}$             |
| `3bus_DCline`                |   3    |  OK  | INF | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F2,F3,F4,F5}\}$                                              |
| `3bus_DSHL`                  |   3    | INF  | OK  | OK  | OK  | OK  | OK  | $\{\text{F1}\}\cdot\{\text{F2}\}\cdot\{\text{F3,F4,F5}\}$                               |
| `3bus_corrections`           |   3    | ERR  | ERR | ERR | ERR | ERR | ERR | Sem convergência (erro de leitura de sintaxe PWF)                                       |
| `3bus_shunt_fields`          |   3    |  OK  | OK  | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F1}\}\cdot\{\text{F2}\}\cdot\{\text{F3,F4,F5}\}$             |
| `3busfrank`                  |   3    |  OK  | OK  | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F1,F2}\}\cdot\{\text{F3,F4,F5}\}$                            |
| `3busfrank_continuous_shunt` |   3    |  OK  | OK  | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F1,F2}\}\cdot\{\text{F3,F4,F5}\}$                            |
| `3busfrank_qlim`             |   3    |  OK  | OK  | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F1}\}\cdot\{\text{F2}\}\cdot\{\text{F3,F4,F5}\}$             |
| `4busfrank_vlim`             |   4    | INF  | INF | OK  | OK  | OK  | OK  | $\{\text{F2}\}\cdot\{\text{F3,F4}\}\cdot\{\text{F5}\}$                                  |
| `5busfrank`                  |   5    |  OK  | OK  | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F1,F2}\}\cdot\{\text{F3,F4,F5}\}$                            |
| `5busfrank_cphs`             |   5    |  OK  | OK  | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F1,F2}\}\cdot\{\text{F3,F4,F5}\}$                            |
| `5busfrank_csca`             |   5    | INF  | INF | OK  | OK  | OK  | OK  | $\{\text{F2}\}\cdot\{\text{F3,F4,F5}\}$                                                 |
| `5busfrank_ctaf`             |   5    |  OK  | OK  | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F1,F2}\}\cdot\{\text{F3}\}\cdot\{\text{F4,F5}\}$             |
| `5busfrank_ctap`             |   5    |  OK  | OK  | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F1,F2}\}\cdot\{\text{F3}\}\cdot\{\text{F4,F5}\}$             |
| `9bus`                       |   9    |  OK  | OK  | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F1,F2}\}\cdot\{\text{F3,F4,F5}\}$                            |
| `9bus_transformer_fields`    |   9    |  OK  | OK  | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F1,F2}\}\cdot\{\text{F3}\}\cdot\{\text{F4,F5}\}$             |
| `300bus`                     |  300   | INV  | OK  | OK  | OK  | OK  | OK  | $\{\text{F1}\}\cdot\{\text{F2}\}\cdot\{\text{F3}\}\cdot\{\text{F4}\}\cdot\{\text{F5}\}$ |
| `500bus`                     |  500   | INF  | OK  | OK  | OK  | OK  | OK  | $\{\text{F1}\}\cdot\{\text{F2}\}\cdot\{\text{F3,F4}\}\cdot\{\text{F5}\}$                |
| `caso_red`                   | 2.599  | INF* | OK  | OK  | OK  | OK  | OK  | $\{\text{F1}\}\cdot\{\text{F2}\}\cdot\{\text{F3}\}\cdot\{\text{F4}\}\cdot\{\text{F5}\}$ |
| `caso_red2`                  | 1.033  | INF  | INF | OK  | OK  | OK  | OK  | $\{\text{F2}\}\cdot\{\text{F3}\}\cdot\{\text{F4}\}\cdot\{\text{F5}\}$                   |
| `CASO_VER_MAXDIU`            | 13.338 | KIL  | INF | KIL | INF | KIL | INF | Sem convergência AC (limite de tempo KIL ou infactibilidade INF)                        |
| `test_defaults`              |   3    | ERR  | ERR | ERR | ERR | ERR | ERR | Sem convergência (erro de validação de sintaxe PWF)                                     |
| `test_line_shunt`            |   3    | ERR  | ERR | ERR | ERR | ERR | ERR | Sem convergência (erro de validação de sintaxe PWF)                                     |
| `test_system`                |   3    | ERR  | ERR | OK  | OK  | OK  | OK  | $\{\text{F2}\}\cdot\{\text{F3,F4,F5}\}$                                                 |

_Legenda: OK (Locally Solved), INF (Infeasible), KIL (Timeout), INV (Invalid
Model), ERR (Parser Error). No caso_red, F0_ encerrou no Ipopt em
LOCALLY_INFEASIBLE e interrompeu na exportação por divergência de barras
desativadas.*

\newpage

## Tabela 3: Desempenho numérico e variáveis operativas agregadas sobre os recortes reduzidos do SIN

Resultados comparativos das formulações F0 a F5 sobre os recortes do subsistema
Nordeste (`caso_red` e `caso_red2`), derivados do cenário Verão 2027/2028 Máxima
Diurna do ONS (PAR/PEL 2027-2031). Grandezas em p.u. sobre base 100 MVA.

| Caso (.pwf)                | Form. | Status | Tempo (s) |    Função Objetivo    | $V_{\min}$ (p.u.) | $V_{\max}$ (p.u.) | $P^g$ (p.u.) | $Q^g$ (p.u.) | Perdas (p.u.) |
| :------------------------- | :---: | :----: | :-------: | :-------------------: | :---------------: | :---------------: | :----------: | :----------: | :-----------: |
| `caso_red` (2.599 barras)  |  F0   |  INF*  |   56,1    | $3,58 \times 10^{3}$  |        n/a        |        n/a        |     n/a      |     n/a      |      n/a      |
|                            |  F1   |   OK   |    1,2    |         0,00          |       0,943       |       1,247       |    34,25     |    -16,02    |     6,97      |
|                            |  F2   |   OK   |   14,7    | $9,06 \times 10^{4}$  |       0,935       |       1,226       |    34,46     |    -8,29     |     7,17      |
|                            |  F3   |   OK   |   15,0    | $1,20 \times 10^{4}$  |       0,920       |       1,225       |    34,55     |    -6,19     |     7,27      |
|                            |  F4   |   OK   |   180,1   | $4,78 \times 10^{2}$  |       0,499       |       1,269       |    34,78     |    +8,78     |     7,49      |
|                            |  F5   |   OK   |   39,2    |          n/a          |       0,523       |       1,269       |    34,67     |    +6,23     |     7,38      |
| `caso_red2` (1.033 barras) |  F0   |  INF   |    7,1    | $2,87 \times 10^{2}$  |       0,950       |       1,218       |     2,87     |    +0,33     |     1,82      |
|                            |  F1   |  INF   |    7,3    |         0,00          |      -0,431       |       1,935       |     5,78     |    +3,92     |     8,12      |
|                            |  F2   |   OK   |    3,1    | $4,94 \times 10^{2}$  |       0,950       |       1,231       |     2,89     |    +0,12     |     1,83      |
|                            |  F3   |   OK   |    4,0    | $2,16 \times 10^{2}$  |       0,950       |       1,228       |     2,90     |    +0,17     |     1,84      |
|                            |  F4   |   OK   |   125,3   | $9,56 \times 10^{-2}$ |       0,950       |       1,269       |     2,86     |    +2,40     |     1,80      |
|                            |  F5   |   OK   |    5,6    |          n/a          |       0,950       |       1,269       |     2,87     |    +2,19     |     1,81      |

---

## Tabela 4: Métricas do fluxo de potência linearizado FDC sobre o cenário SIN de 13.338 barras

Métricas operacionais globais obtidas na convergência da formulação auxiliar
linearizada FDC (`solve_dc_pf`) sobre o arquivo integral do SIN
(`CASO_VER_MAXDIU.PWF`).

| Grandeza Operacional do Sistema         | Valor Numérico Apurado                  |
| :-------------------------------------- | :-------------------------------------- |
| Status de Resolução Numérica            | LOCALLY_SOLVED                          |
| Barras retidas (após componente conexa) | 13.283                                  |
| Ramos de transmissão exportados         | 16.743                                  |
| Geradores em operação ($P^g > 0$)       | 346                                     |
| Potência ativa gerada total ($P^g$)     | 709,70 p.u. ($\approx 70,97$ GW)        |
| Demanda ativa total atendida ($P^d$)    | 695,67 p.u. ($\approx 69,57$ GW)        |
| Perdas ativas de transmissão            | 0,00 p.u. (desprezadas por premissa DC) |
| Ângulo de fase mínimo ($\theta_{\min}$) | $-165,99^\circ$                         |
| Ângulo de fase máximo ($\theta_{\max}$) | $+176,88^\circ$                         |
| Fluxo ativo máximo em ramo ($p_{ij}$)   | 99,50 p.u. ($\approx 9,95$ GW)          |

---

## Tabela 5: Perfil barra a barra de tensões e ângulos no caso pedagógico `3bus_DCSC`

Distribuição nodal de magnitudes de tensão e ângulos de fase no sistema
elementar de três barras com elemento DCSC na linha 1-2 (`3bus_DCSC.pwf`),
evidenciando a diferenciação entre as camadas de controle.

| Barra | Formulação Avaliada        | Magnitude $V$ (p.u.) | Ângulo de Fase $\theta$ (rad) |
| :---: | :------------------------- | :------------------: | :---------------------------: |
|   1   | F0 (OPF-PM)                |        1,1000        |            0,0000             |
|   1   | F1 (PF-PM)                 |        1,0290        |            0,0000             |
|   1   | F2 (QLIM+VLIM)             |        1,0352        |            0,0000             |
|   1   | F3 a F5 (CSCA, CTAP, DERA) |        1,0064        |            0,0000             |
|   2   | F0 (OPF-PM)                |        1,1000        |    $-3,9 \times 10^{-10}$     |
|   2   | F1 (PF-PM)                 |        1,0300        |     $-7,1 \times 10^{-3}$     |
|   2   | F2 (QLIM+VLIM)             |        1,0362        |     $-2,4 \times 10^{-4}$     |
|   2   | F3 a F5 (CSCA, CTAP, DERA) |        1,0062        |     $-2,6 \times 10^{-4}$     |
|   3   | F0 (OPF-PM)                |        1,0698        |     $-1,8 \times 10^{-2}$     |
|   3   | F1 (PF-PM)                 |        0,9970        |     $-2,5 \times 10^{-2}$     |
|   3   | F2 (QLIM+VLIM)             |        1,0178        |     $-1,2 \times 10^{-2}$     |
|   3   | F3 a F5 (CSCA, CTAP, DERA) |        0,9878        |     $-1,3 \times 10^{-2}$     |
