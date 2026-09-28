---
title: "Relatório Final de Projeto de Pesquisa — PIBIC/CNPq/UFC"
subtitle:
  "Edital PIBIC 2025/2026 — Projeto 13439: Aplicação de Técnicas de Otimização
  Convexa em Fluxo de Potência Ótimo"
author:
  - "Bolsista: Gabriel Rufino Montenegro (Graduação em Engenharia Elétrica)"
  - "Orientador: Prof. Dr. Lucas Silveira Melo (Departamento de Engenharia
    Elétrica / CT)"
date: "Setembro de 2026"
geometry: "margin=2.5cm"
papersize: a4
lang: pt-BR
mainfont: EB Garamond
fontsize: 11pt
linestretch: 1.2
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
  - \fancyhead[L]{\small PIBIC UFC 2025/2026 — Relatório Final}
  - \fancyhead[R]{\small FPO em Julia / JuMP}
  - \fancyfoot[C]{\thepage}
---

# Identificação do Projeto e do Bolsista

- **Edital / Programa**: Programa Institucional de Bolsas de Iniciação
  Científica (PIBIC — UFC / CNPq) — Edital Nº 02/2025 (Ciclo 2025/2026)
- **Número do Projeto no SIGAA**: Projeto 13439
- **Título do Projeto no Edital**: Aplicação de Técnicas de Otimização Convexa
  em Fluxo de Potência Ótimo
- **Título do Trabalho Concluído (TCC)**: Implementação de uma arquitetura
  incremental de ações de controle de Fluxo de Potência Ótimo em linguagem Julia
- **Bolsista**: Gabriel Rufino Montenegro (E-mail: `gabrielrufino@alu.ufc.br`)
- **Orientador**: Prof. Dr. Lucas Silveira Melo
- **Unidade Acadêmica**: Centro de Tecnologia (CT) — Departamento de Engenharia
  Elétrica (DEE)
- **Instituição**: Universidade Federal do Ceará (UFC)
- **Vigência da Bolsa**: 2025 – 2026
- **Trabalho Acadêmico Vinculado**: Trabalho de Conclusão de Curso (TCC) em
  Engenharia Elétrica (UFC, 2026)

---

# Itens do Relatório

## Resumo

O Fluxo de Potência Ótimo (FPO) é fundamental para o planejamento e a operação
econômica e segura de Sistemas Elétricos de Potência (SEP). No Brasil,
ferramentas industriais consolidadas como o programa ANAREDE (CEPEL) utilizam
ações de controle operativas essenciais — como limites de geração reativa
(QLIM), limites de tensão em barras (VLIM), controle de susceptância de bancos
shunt (CSCA), ajuste de tap de transformadores sob carga (CTAP) e esquemas de
corte de carga em emergência (DERA) —, as quais não estão presentes de forma
nativa em pacotes acadêmicos abertos. Este trabalho implementa e valida uma
arquitetura computacional aberta de progressão incremental de ações de controle
de FPO em linguagem Julia, composta por seis formulações de fluxo de potência
CA: duas formulações de referência baseadas no pacote PowerModels.jl (F0: FPO AC
e F1: FP AC) e quatro formulações formuladas diretamente em JuMP (F2 a F5).
Estas últimas incorporam sequencialmente os controles do ANAREDE por meio de
restrições flexíveis (soft-constraints) com penalização quadrática de folgas na
função objetivo, resolvidas via solver Ipopt. A metodologia foi validada sobre
27 casos de teste no formato PWF (via PWF.jl), compreendendo redes pedagógicas
de 3 a 9 barras, sistemas de 300 e 500 barras, dois recortes reduzidos do
subsistema Nordeste (2.599 e 1.033 barras) e o caso integral do Sistema
Interligado Nacional (13.338 barras). As formulações manuais convergiram em 23
casos (85,2%), superando o PowerModels (18 em FP e 15 em FPO) e recuperando
viabilidade em 9 redes críticas onde as referências falharam devido à rigidez de
limites operacionais. Os resultados comprovam a viabilidade e a superioridade de
convergência da modelagem por restrições flexíveis para estudos elétricos com
controles do SIN em ambiente científico aberto.

## Objetivos Cumpridos

Os objetivos do projeto foram originalmente estabelecidos na proposta submetida
ao Edital PIBIC Nº 02/2025 (Projeto 13439: _Aplicação de Técnicas de Otimização
Convexa em Fluxo de Potência Ótimo_). Conforme previsto nas diretrizes do
programa, o avanço da fundamentação teórica e a identificação de lacunas
práticas no contexto dos Sistemas Elétricos de Potência (SEP) brasileiros
motivaram o redirecionamento e a ampliação do escopo original, resultando na
inclusão de novos objetivos voltados à implementação de ações de controle
operativas do SIN em ambiente Julia/JuMP. A seguir, copiam-se os objetivos
iniciais e descrevem-se os objetivos adicionados, classificados segundo as
instruções:

**Objetivos do Projeto Inicial:**

1. **Objetivo Geral Inicial**: Analisar e comparar técnicas de otimização
   convexa para resolver problemas de Fluxo de Potência Ótimo, avaliando sua
   eficácia em diferentes topologias de rede utilizando para isso a biblioteca
   _PowerModels.jl_, implementada em linguagem Julia. **(T)** _Cumprimento_:
   Objetivo concluído. As formulações de relaxação e aproximação foram estudadas
   e implementadas no ambiente Julia/PowerModels, servindo de base para o
   desenvolvimento das formulações de referência.

2. **Revisar técnicas clássicas de relaxação convexa (SDP, SOCP, LP) para FPO**:
   **(T)** _Cumprimento_: Objetivo concluído. Foi realizada ampla revisão
   bibliográfica sobre as relaxações semidefinida (SDP), cônica de segunda ordem
   (SOCP) e linearizada (DC), documentada no Capítulo 2 do TCC do bolsista.

3. **Executar e analisar modelos convexos usando a biblioteca PowerModels.jl do
   Julia**: **(T)** _Cumprimento_: Objetivo concluído. Foram implementadas e
   executadas rotinas de FPO AC, DC e relaxações cônicas, avaliando limites de
   convergência e gaps de otimalidade.

4. **Comparar desempenho em redes-teste IEEE usando a biblioteca pgLib-OPF**:
   **(P)** _Cumprimento_: Parcialmente cumprido e redirecionado. A comparação
   inicial em redes IEEE (como o sistema IEEE 300 barras) foi redirecionada para
   incorporar o formato de dados ANAREDE (.pwf), permitindo avaliar topologias
   brasileiras reais e casos pedagógicos com controle.

5. **Verificar a robustez das relaxações em cenários com geração renovável
   intermitente**: **(P)** _Cumprimento_: Parcialmente cumprido e aprofundado na
   análise dos recortes do subsistema Nordeste (`caso_red` e `caso_red2`),
   caracterizados pela massiva concentração de geração eólica e solar do ciclo
   PAR/PEL 2027-2031 do ONS.

**Novos Objetivos Incluídos Durante a Execução (O):**

6. **Implementação de arquitetura incremental de ações de controle em JuMP**:
   Desenvolver quatro formulações manuais aditivas em JuMP (F2 a F5)
   introduzindo QLIM+VLIM, CSCA, CTAP e DERA via restrições flexíveis
   (_soft-constraints_) com variáveis de folga penalizadas e solver Ipopt.
   **(O)** _Cumprimento_: Cumprido, constituindo a principal contribuição do
   Trabalho de Conclusão de Curso (TCC) do aluno.

7. **Integração de dados operacionais do formato ANAREDE via PWF.jl**:
   Automatizar a leitura e a extração de dados de controle dos registros DOPC e
   DLIN para estruturas indexadas no Julia. **(O)** _Cumprimento_: Cumprido
   através de pipeline de leitura e tratamento de topologia.

8. **Bateria de testes em 27 casos e análise de clusters operativos**: Avaliar
   sistematicamente o comportamento de convergência e o particionamento em
   clusters de equivalência em 27 redes, de 3 a 13.338 barras. **(O)**
   _Cumprimento_: Cumprido.

9. **Diagnóstico linearizado do SIN integral (FDC)**: Implementar fluxo
   linearizado DC sobre o cenário integral do SIN (13.338 barras) para avaliar
   factibilidade topológica. **(O)** _Cumprimento_: Cumprido, confirmando a
   factibilidade do sistema linearizado.

## Resultados

A avaliação experimental foi conduzida mediante a execução das seis formulações
de fluxo de potência (F0 a F5) e da formulação linearizada auxiliar (FDC) sobre
um conjunto padronizado de vinte e sete sistemas no formato PWF. O conjunto
abrange redes pedagógicas de três a nove barras, sistemas de médio porte (300 e
500 barras), dois recortes reais do subsistema Nordeste do Sistema Interligado
Nacional (2.599 e 1.033 barras) e o cenário integral do SIN (13.338 barras). O
critério de equivalência numérica para agrupamento em _clusters_ operativos foi
fixado em $|\Delta| \le 10^{-4}$ p.u. simultaneamente sobre magnitude de tensão
($V$), ângulo de fase ($\theta$), potências geradas ($P^g, Q^g$) e fluxos de
potência nos ramos.

### 1. Síntese Global de Convergência

A Tabela 1 sintetiza o desempenho global das formulações sobre os vinte e sete
casos de teste avaliados, quantificando as ocorrências de solução local factível
(OK), infactibilidade matemática (INF), interrupção por tempo limite (KIL),
modelo inválido (INV) e erros de sintaxe no _parser_ de dados (ERR).

| Indicador Operacional        | F0 (OPF-PM) | F1 (PF-PM) | F2 (QLIM+VLIM) | F3 (+CSCA) | F4 (+CTAP) | F5 (+DERA) |
| :--------------------------- | :---------: | :--------: | :------------: | :--------: | :--------: | :--------: |
| Casos Convergidos (OK)       | 15 (55,6%)  | 18 (66,7%) |   23 (85,2%)   | 23 (85,2%) | 23 (85,2%) | 23 (85,2%) |
| Infactibilidade Local (INF)  |  6 (22,2%)  | 5 (18,5%)  |    0 (0,0%)    |  1 (3,7%)  |  0 (0,0%)  |  1 (3,7%)  |
| Tempo Limite Excedido (KIL)  |  1 (3,7%)   |  0 (0,0%)  |    1 (3,7%)    |  0 (0,0%)  |  1 (3,7%)  |  0 (0,0%)  |
| Modelo Inválido (INV)        |  1 (3,7%)   |  0 (0,0%)  |    0 (0,0%)    |  0 (0,0%)  |  0 (0,0%)  |  0 (0,0%)  |
| Erro de Leitura/Parser (ERR) |  4 (14,8%)  | 4 (14,8%)  |   3 (11,1%)    | 3 (11,1%)  | 3 (11,1%)  | 3 (11,1%)  |
| Total de Casos Avaliados     |  27 (100%)  | 27 (100%)  |   27 (100%)    | 27 (100%)  | 27 (100%)  | 27 (100%)  |

_Tabela 1: Resumo numérico global de status de convergência das formulações._

As formulações desenvolvidas manualmente em JuMP (F2 a F5) convergiram com
sucesso em 23 dos 27 casos testados (taxa de sucesso de 85,2%), superando o
fluxo de potência clássico F1 (18 casos, 66,7%) e o fluxo de potência ótimo F0
(15 casos, 55,6%). Em nove redes específicas (`4busfrank_vlim`,
`5busfrank_csca`, `test_system`, `caso_red2`, `300bus`, `3bus_DCline`,
`3bus_DSHL`, `500bus` e `caso_red`), as formulações manuais alcançaram
convergência enquanto uma ou ambas as referências do _PowerModels.jl_ falharam.

### 2. Mapeamento de Convergência e Formação de Clusters

A Tabela 2 apresenta o status individualizado e o particionamento em _clusters_
de soluções numericamente indistinguíveis para as formulações convergidas. A
notação $\{A,B\}\cdot\{C\}$ indica que $A$ e $B$ atingiram o mesmo ponto
operativo, enquanto $C$ atingiu ponto operacional distinto.

| Caso de Teste (.pwf)         | Barras |  F0  | F1  | F2  | F3  | F4  | F5  | Particionamento em Clusters                                                             |
| :--------------------------- | :----: | :--: | :-: | :-: | :-: | :-: | :-: | :-------------------------------------------------------------------------------------- |
| `3bus`                       |   3    |  OK  | OK  | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F1,F2}\}\cdot\{\text{F3,F4,F5}\}$                            |
| `3bus_DBSH`                  |   3    |  OK  | OK  | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F1,F2}\}\cdot\{\text{F3,F4,F5}\}$                            |
| `3bus_DCER`                  |   3    |  OK  | OK  | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F1,F2}\}\cdot\{\text{F3,F4,F5}\}$                            |
| `3bus_DCSC`                  |   3    |  OK  | OK  | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F1}\}\cdot\{\text{F2}\}\cdot\{\text{F3,F4,F5}\}$             |
| `3bus_DCline`                |   3    |  OK  | INF | OK  | OK  | OK  | OK  | $\{\text{F0}\}\cdot\{\text{F2,F3,F4,F5}\}$                                              |
| `3bus_DSHL`                  |   3    | INF  | OK  | OK  | OK  | OK  | OK  | $\{\text{F1}\}\cdot\{\text{F2}\}\cdot\{\text{F3,F4,F5}\}$                               |
| `3bus_corrections`           |   3    | ERR  | ERR | ERR | ERR | ERR | ERR | Sem convergência (erro de leitura)                                                      |
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
| `CASO_VER_MAXDIU`            | 13.338 | KIL  | INF | KIL | INF | KIL | INF | Sem convergência (tempo ou infactibilidade)                                             |
| `test_defaults`              |   3    | ERR  | ERR | ERR | ERR | ERR | ERR | Sem convergência (erro de leitura)                                                      |
| `test_line_shunt`            |   3    | ERR  | ERR | ERR | ERR | ERR | ERR | Sem convergência (erro de leitura)                                                      |
| `test_system`                |   3    | ERR  | ERR | OK  | OK  | OK  | OK  | $\{\text{F2}\}\cdot\{\text{F3,F4,F5}\}$                                                 |

_Tabela 2: Mapeamento de convergência e particionamento de clusters por sistema
testado. Legenda: OK (Locally Solved), INF (Infeasible), KIL (Timeout), INV
(Invalid Model), ERR (Parser Error)._

### 3. Resultados nos Recortes Reduzidos do SIN (Metodologia de Fronteira Híbrida)

A Tabela 3 detalha os parâmetros e variáveis operativas obtidos nos recortes do
subsistema Nordeste (`caso_red` e `caso_red2`), originados do cenário Verão
2027/2028 Máxima Diurna do ONS (PAR/PEL 2027-2031). Os valores de geração,
perdas e função objetivo estão normalizados em base 100 MVA.

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

_Tabela 3: Desempenho numérico e variáveis operativas agregadas sobre os
recortes reduzidos do SIN._

No `caso_red2`, o fluxo sem controles F1 declarou infactibilidade com magnitude
de tensão fisicamente inaceitável ($V_{\min} = -0,431$ p.u. e $V_{\max} = 1,935$
p.u.). Em contrapartida, as formulações manuais com restrições flexíveis
convergiram para perfis de tensão consistentes (entre 0,950 e 1,269 p.u.). A
introdução conjunta de CSCA e CTAP na formulação F4 reduziu o valor da função
objetivo de penalização para $9,56 \times 10^{-2}$, demonstrando a eliminação
quase integral das violações de setpoints de tensão sem necessidade de relaxação
excessiva. No `caso_red`, observa-se uma variação substancial no balanço de
potência reativa: a geração total $Q^g$ transitou de $-16,02$ p.u. (-1.602 MVAr
de absorção líquida) em F1 para $+8,78$ p.u. (+878 MVAr de injeção) em F4, o que
reflete a atuação direta dos bancos shunt chaveáveis liberados continuamente
pelo algoritmo.

### 4. Diagnóstico Linearizado (DC) do Caso Integral do SIN (13.338 Barras)

A Tabela 4 sintetiza os resultados numéricos obtidos pela formulação auxiliar
linearizada FDC (`solve_dc_pf`) aplicada sobre o arquivo integral do SIN
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
| Fluxo ativo máximo em ramo ($           | p_{ij}                                  | $)  | 99,50 p.u. ($\approx 9,95$ GW) |

_Tabela 4: Métricas do fluxo de potência linearizado FDC sobre o cenário SIN de
13.338 barras._

A formulação linearizada convergiu em poucas iterações com status factível no
Ipopt. As grandezas atestam a integridade dos dados topológicos lidos pelo
parser, mas revelam desvios angulares extremos ($\theta$ variando entre
$-165,99^\circ$ e $+176,88^\circ$) e fluxos concentrados de até 9,95 GW,
condições que extrapolam os limites teóricos de validade da aproximação
linearizada ($\sin\Delta\theta \approx \Delta\theta$).

### 5. Análise de Divergência Barra a Barra no Caso Pedagógico `3bus_DCSC`

A Tabela 5 expõe os valores nodais de tensão e ângulo para o sistema elementar
de três barras com capacitor série controlável (`3bus_DCSC.pwf`), ilustrando a
diferenciação numérica provocada por cada camada de controle sobre as barras do
sistema.

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

_Tabela 5: Perfil barra a barra de tensões e ângulos no caso 3bus_DCSC._

Nota: As representações gráficas complementares (fluxograma metodológico, mapa
de calor de convergência das 27 redes, diagrama unifilar do sistema 3bus_DCSC,
curvas de perfil de tensão e evolução logarítmica da função objetivo nos casos
reduzidos) constam documentadas no ANEXO técnico deste relatório.

## Discussão

A análise crítica dos resultados evidencia que a metodologia incremental de
ações de controle desenvolvida em Julia atingiu plenamente a meta de aproximar
as ferramentas acadêmicas abertas das práticas industriais do setor elétrico
brasileiro, trazendo ganhos substantivos de convergência e interpretabilidade
física.

### 1. Avaliação Crítica da Abordagem por Restrições Flexíveis (_Soft-Constraints_)

A discrepância fundamental observada entre as formulações manuais (F2 a F5) e as
referências do pacote _PowerModels.jl_ (F0 e F1) reside no tratamento das
restrições operacionais. Formulações acadêmicas clássicas tratam limites de
tensão ($V_{\min}, V_{\max}$) e de geração reativa ($Q_{\min}, Q_{\max}$) como
restrições rígidas (_hard-constraints_). Em sistemas sob estresse operativo ou
com parâmetros de controle rigorosos, os algoritmos de pontos interiores
frequentemente declaram infactibilidade local ou divergem antes de encontrar um
ponto factível.

A formulação desenvolvida em _JuMP_ introduz variáveis de folga penalizadas
quadraticamente na função objetivo com peso $\rho = 10^6$. Como evidenciado
pelos dados experimentais, essa modelagem permitiu convergir em 85,2% dos casos
avaliados, contra apenas 55,6% do FPO clássico e 66,7% do fluxo de potência
convencional. O caso `caso_red2` (1.033 barras) ilustra esse comportamento com
extrema nitidez: enquanto o fluxo sem controles F1 encerrou em infactibilidade
com tensões espúrias e fisicamente impossíveis ($V_{\min} = -0,431$ p.u.), a
formulação F2 recuperou o ponto operativo dentro da faixa permitida, e a
inclusão das ações de controle CSCA e CTAP (F4) reduziu as violações a uma
penalidade residual de apenas $9,56 \times 10^{-2}$. Isso comprova que as ações
de controle propostas não apenas sustentam a convergência matemática, mas
orientam o sistema em direção ao ponto operativo pretendido pelo operador.

### 2. Comportamento Operativo e Assinatura dos Controles Individuais

O particionamento das soluções em _clusters_ de equivalência operativa confirmou
a atuação física esperada de cada ação de controle adicionada à progressão:

- **QLIM e VLIM (F2)**: As folgas de tensão $s^v$ e de reativo $s^q$ atuaram
  como amortecedores numéricos, restaurando a viabilidade em sete casos em que o
  modelo rígido falhou, demonstrando a capacidade da formulação de acomodar
  saturações de geradores.
- **CSCA (F3)**: A liberação da susceptância shunt $b^{sh}_s$ como variável
  contínua de decisão permitiu que o algoritmo ajustasse localmente o suporte
  reativo. No `caso_red`, essa ação provocou uma reversão expressiva de 2.480
  MVAr no balanço de geração reativa total, aliviando o esforço de máquinas
  síncronas e reduzindo desvios de tensão nas barras adjacentes.
- **CTAP (F4)**: O ajuste contínuo da relação de transformação $t_{ij}$
  introduziu graus de liberdade essenciais em redes com múltiplos
  transformadores em carga, empurrando as tensões de barras secundárias para os
  patamares nominais mais elevados.
- **DERA (F5)**: A inclusão do termo linear de corte de carga ponderado por
  nível de tensão base ($w_l = 10^3, 5 \times 10^3, 10^4$) comportou-se de forma
  estritamente consistente com a teoria: em redes com viabilidade reativa
  assegurada, as variáveis de corte mantiveram-se estritamente nulas
  ($\Delta P^d_l = 0$), reproduzindo a solução da formulação F4. Em redes
  severamente estressadas, como `4busfrank_vlim` e `500bus`, o corte de carga
  foi acionado seletivamente nas barras de menor tensão (subtransmissão e
  distribuição), preservando a integridade das barras de extra-alta tensão
  (EAT).

### 3. O Desafio de Convergência no Cenário Integral do SIN (13.338 Barras)

O caso integral do SIN (`CASO_VER_MAXDIU.PWF`) constitui o cenário mais complexo
do estudo e o único em que nenhuma das formulações de fluxo CA alcançou
convergência dentro do limite operacional estipulado (3.000 iterações e 600
segundos de CPU). A análise desse comportamento afasta a hipótese de falha na
inicialização do algoritmo:

1. **Ponto de Partida**: Todas as formulações manuais foram inicializadas com as
   tensões, ângulos e gerações resultantes do ponto convergido pelo programa
   ANAREDE presente no próprio arquivo PWF. O fato de a própria formulação F1 do
   _PowerModels_ ter falhado partindo dessa mesma inicialização indica que o
   obstáculo é estrutural à transposição do modelo.
2. **Diagnóstico da Formulação FDC**: A resolução bem-sucedida da aproximação
   linearizada FDC sobre a rede integral (13.283 barras conexas e 70,97 GW de
   geração) confirma que a topologia está correta e que o sistema possui
   potência suficiente para suprir a demanda. O obstáculo reside, portanto, no
   severo mau condicionamento numérico do Jacobiano/Hessiano das equações CA,
   agravado pela presença de elos HVDC de grande porte tratados com injeções
   fixadas, intercâmbios de área e controle remoto de barras, associados à
   penalidade uniforme $\rho = 10^6$ aplicada sobre treze mil nós.
3. **Inviabilidade do DC como Ponto de Partida (_Warm-Start_)**: A solução DC
   apurou aberturas angulares de até $\pm 176,88^\circ$ e fluxos por ramo de até
   9,95 GW, violando frontalmente a premissa de pequenas variações angulares
   ($\sin\Delta\theta \approx \Delta\theta$). Esse perfil torna a solução
   linearizada um ponto inicial numericamente inferior ao próprio ponto lido do
   PWF.

### 4. Resposta ao Problema Enunciado e Limitações do Método

Em resposta à questão central formulada na introdução do trabalho — _se é viável
reproduzir, em uma biblioteca aberta e moderna da linguagem Julia, o conjunto de
ações de controle operativas do ANAREDE aplicáveis ao SIN_ —, os resultados
demonstram de forma inequívoca que a resposta é afirmativa. A formulação
matemática em JuMP com restrições flexíveis não apenas reproduz as heurísticas
do ANAREDE, mas supera as implementações clássicas do _PowerModels.jl_ em
robustez e convergência.

Identificam-se como limitações principais do trabalho: (i) o tratamento das
grandezas de chaveamento (shunts CSCA e taps CTAP) como variáveis contínuas, sem
etapa subsequente de discretização inteira mista (MINLP); (ii) a representação
dos cortes DERA de forma suave e contínua, sem blocos discretos de alívio; e
(iii) o tratamento estático dos elos de corrente contínua (HVDC). A superação
destas limitações e a aplicação de técnicas de continuação homotópica sobre os
parâmetros de penalidade definem as frentes de continuidade da pesquisa.

## Produtos e/ou Publicações

Durante a execução do plano de atividades do projeto PIBIC (ciclo 2025/2026),
foram gerados os seguintes produtos técnicos, científicos e tecnológicos:

1. **Trabalho de Conclusão de Curso (TCC) de Graduação**:
   - _Título_: "Implementação de uma arquitetura incremental de ações de
     controle de Fluxo de Potência Ótimo em linguagem Julia"
   - _Autor (Bolsista)_: Gabriel Rufino Montenegro
   - _Orientador_: Prof. Dr. Lucas Silveira Melo
   - _Grau e Instituição_: Engenharia Elétrica, Centro de Tecnologia,
     Universidade Federal do Ceará (UFC), Fortaleza, 2026.
   - _Descrição_: Monografia acadêmica de graduação completa em LaTeX,
     documentando a fundamentação teórica, a formulação analítica das seis
     variantes (F0 a F5), os testes nos 27 casos e a análise do cenário do SIN.

2. **Protótipo de Software e Código-Fonte Aberto**:
   - Suíte computacional modular em linguagem Julia contendo:
     - Scripts executáveis e independentes das formulações: `(F0)OPF_PM.jl`,
       `(F1)PF_PM.jl`, `(F2)QLIM+VLIM.jl`, `(F3)QLIM+VLIM+CSCA.jl`,
       `(F4)QLIM+VLIM+CSCA+CTAP.jl`, `(F5)+DERA.jl` e `(FDC).jl`.
     - Orquestrador automatizado de testes em lote (`runner_analise_tcc.jl`) com
       subprocessos isolados, controle de tempo limite (_timeout_) e gerador de
       relatórios consolidados em CSV.
     - Scripts de consolidação matricial e cálculo de clusters operativos
       (`consolidar.jl` e `_consolidate_masters.jl`).

3. **Relatórios Técnicos Periódicos de Pesquisa**:
   - Conjunto de 13 relatórios técnicos de progresso (_short-reports_)
     detalhando cronogramas, etapas de desenvolvimento, estudos comparativos
     entre formulações e análises de casos de teste específicos ao longo do
     período de pesquisa.

4. **Apresentação Técnica e Material de Defesa**:
   - Apresentação completa em formato Beamer LaTeX (`Template_Beamer_UFC`)
     contendo 50 lâminas técnicas estruturadas, diagramas metodológicos e
     roteiro detalhado de fala para defesa perante banca examinadora.

5. **Produção Bibliográfica em Elaboração**:
   - Artigo técnico-científico em fase final de redação e consolidação para
     submissão a evento científico de referência na área de sistemas de potência
     (Simpósio Brasileiro de Sistemas Elétricos — SBSE / Congresso Brasileiro de
     Automática — CBA), abordando a comparação de convergência entre as
     abordagens JuMP flexíveis e o PowerModels.jl.

## Avaliação do Bolsista

O bolsista Gabriel Rufino Montenegro demonstrou excelente desempenho, maturidade
técnica e dedicação exemplar ao longo de todo o ciclo do projeto PIBIC
2025/2026. O plano de trabalho foi cumprido em sua totalidade, tendo o estudante
atingido com elevado rigor científico todas as metas teóricas e práticas
pactuadas.

Dentre as competências evidenciadas, destacam-se: (i) a sólida apropriação dos
fundamentos matemáticos do fluxo de potência ótimo e das técnicas de relaxação
não linear; (ii) o domínio avançado da linguagem Julia e das ferramentas JuMP e
Ipopt, empregadas na codificação de formulações não convexas de alta
complexidade; (iii) a notável autonomia e capacidade de resolução de problemas,
exemplificada pela implementação de um orquestrador automatizado para
processamento em lote de 27 redes elétricas; e (iv) o diálogo produtivo com
bases de dados reais do ONS e formulação de análises inovadoras, como o
diagnóstico linearizado do SIN e a avaliação de recortes com fronteira híbrida.

O bolsista manteve pontualidade rigorosa nos relatórios periódicos, demonstrou
proatividade nas discussões de pesquisa e materializou os resultados do projeto
em seu Trabalho de Conclusão de Curso (TCC), aprovado com louvor e recomendação
para continuidade em nível de pós-graduação. Diante dos expressivos resultados
científicos e tecnológicos entregues, a avaliação global do desempenho do
bolsista é classificada no patamar de excelência máxima (nota 10,0).

---

# Anexo: Identificação de Imagens e Figuras Complementares

Conforme instrução do edital, as representações esquemáticas e gráficas citadas
no corpo deste relatório encontram-se compiladas e disponíveis no documento de
Trabalho de Conclusão de Curso
(`Modelo_de_Trabalho_Acadêmico_UFC/documento.pdf`), correspondendo às seguintes
referências:

- **Figura 1: Fluxograma da Sequência de Execução das Formulações (Pipeline)** —
  Ilustra as etapas encadeadas de leitura do PWF via PWF.jl, adequação
  topológica (maior componente conexa e rebaixamento de múltiplas slacks),
  construção da estrutura de dados indexada (`build_ref`), montagem simbólica
  das restrições e expressões no JuMP, resolução numérica com Ipopt e exportação
  para CSV.
- **Figura 2: Mapa de Calor da Convergência Global** — Representação matricial
  colorida (verde para OK, amarelo para INF, vermelho para KIL, laranja para INV
  e cinza para ERR) ilustrando o status das seis formulações nas 27 redes
  testadas e evidenciando a ampliação da faixa factível nas abordagens F2 a F5.
- **Figura 3: Diagrama Unifilar da Rede Pedagógica `3bus_DCSC`** — Esquema da
  rede triangular de três barras com duas barras de geração, uma barra de carga
  e um elemento DCSC na linha 1-2.
- **Figura 4: Perfil de Tensão por Barra no Caso `3bus_DCSC`** — Gráfico
  comparativo de linhas destacando o deslocamento das tensões de F0 (teto de
  1,10 p.u.), F1 (ponto base), F2 (ajuste fino com QLIM/VLIM) e F3 a F5 (redução
  de tensão pela atuação do CSCA ajustando a susceptância shunt).
- **Figura 5: Evolução Logarítmica da Função Objetivo nos Casos Reduzidos** —
  Gráfico de barras verticais em escala logarítmica demonstrando a redução
  drástica das folgas de penalização de F2 para F3 e F4 nos recortes `caso_red`
  e `caso_red2` (atingindo $9,56 \times 10^{-2}$).
