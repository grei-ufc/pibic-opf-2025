---
title: "Relatório Final de Projeto de Pesquisa — PIBIC/CNPq/UFC (Versão para Submissão)"
subtitle: "Edital PIBIC 2025/2026 — Projeto 13439: Aplicação de Técnicas de Otimização Convexa em Fluxo de Potência Ótimo"
author:
  - "Bolsista: Gabriel Rufino Montenegro (Graduação em Engenharia Elétrica)"
  - "Orientador: Prof. Dr. Lucas Silveira Melo (Departamento de Engenharia Elétrica / CT)"
date: "Setembro de 2026"
geometry: "margin=2.5cm"
papersize: a4
lang: pt-BR
fontsize: 11pt
linestretch: 1.2
documentclass: article
header-includes:
  - \usepackage{amsmath}
  - \usepackage{amssymb}
  - \usepackage{microtype}
  - \usepackage{fancyhdr}
  - \pagestyle{fancy}
  - \fancyhf{}
  - \fancyhead[L]{\small PIBIC UFC 2025/2026 — Relatório Final (Envio)}
  - \fancyhead[R]{\small FPO em Julia / JuMP}
  - \fancyfoot[C]{\thepage}
---

# Identificação do Projeto e do Bolsista

- **Edital / Programa**: Programa Institucional de Bolsas de Iniciação Científica (PIBIC — UFC / CNPq) — Edital Nº 02/2025 (Ciclo 2025/2026)
- **Número do Projeto no SIGAA**: Projeto 13439
- **Título do Projeto no Edital**: Aplicação de Técnicas de Otimização Convexa em Fluxo de Potência Ótimo
- **Título do Trabalho Concluído (TCC)**: Implementação de uma arquitetura incremental de ações de controle de Fluxo de Potência Ótimo em linguagem Julia
- **Bolsista**: Gabriel Rufino Montenegro (E-mail: `gabrielrufino@alu.ufc.br`)
- **Orientador**: Prof. Dr. Lucas Silveira Melo
- **Unidade Acadêmica**: Centro de Tecnologia (CT) — Departamento de Engenharia Elétrica (DEE)
- **Instituição**: Universidade Federal do Ceará (UFC)
- **Vigência da Bolsa**: 2025 – 2026
- **Trabalho Acadêmico Vinculado**: Trabalho de Conclusão de Curso (TCC) em Engenharia Elétrica (UFC, 2026)
- **Documento Complementar em Anexo**: `tabelas-anexo.pdf` (Arquivo PDF em formato paisagem contendo a totalidade das tabelas de resultados das simulações)

---

# Itens do Relatório

## Resumo

O Fluxo de Potência Ótimo (FPO) é fundamental para o planejamento e a operação econômica e segura de Sistemas Elétricos de Potência (SEP). No Brasil, ferramentas industriais consolidadas como o programa ANAREDE (CEPEL) utilizam ações de controle operativas essenciais — como limites de geração reativa (QLIM), limites de tensão em barras (VLIM), controle de susceptância de bancos shunt (CSCA), ajuste de tap de transformadores sob carga (CTAP) e esquemas de corte de carga em emergência (DERA) —, as quais não estão presentes de forma nativa em pacotes acadêmicos abertos. Este trabalho implementa e valida uma arquitetura computacional aberta de progressão incremental de ações de controle de FPO em linguagem Julia, composta por seis formulações de fluxo de potência CA: duas formulações de referência baseadas no pacote PowerModels.jl (F0: FPO AC e F1: FP AC) e quatro formulações formuladas diretamente em JuMP (F2 a F5). Estas últimas incorporam sequencialmente os controles do ANAREDE por meio de restrições flexíveis (soft-constraints) com penalização quadrática de folgas na função objetivo, resolvidas via solver Ipopt. A metodologia foi validada sobre 27 casos de teste no formato PWF (via PWF.jl), compreendendo redes pedagógicas de 3 a 9 barras, sistemas de 300 e 500 barras, dois recortes reduzidos do subsistema Nordeste (2.599 e 1.033 barras) e o caso integral do Sistema Interligado Nacional (13.338 barras). As formulações manuais convergiram em 23 casos (85,2%), superando o PowerModels (18 em FP e 15 em FPO) e recuperando viabilidade em 9 redes críticas onde as referências falharam devido à rigidez de limites operacionais. Os resultados comprovam a viabilidade e a superioridade de convergência da modelagem por restrições flexíveis para estudos elétricos com controles do SIN em ambiente científico aberto.

## Objetivos Cumpridos

Os objetivos do projeto foram originalmente estabelecidos na proposta submetida ao Edital PIBIC Nº 02/2025 (Projeto 13439: Aplicação de Técnicas de Otimização Convexa em Fluxo de Potência Ótimo). Conforme previsto nas diretrizes do programa, o avanço da fundamentação teórica e a identificação de lacunas práticas no contexto dos Sistemas Elétricos de Potência (SEP) brasileiros motivaram o redirecionamento e a ampliação do escopo original, resultando na inclusão de novos objetivos voltados à implementação de ações de controle operativas do SIN em ambiente Julia/JuMP. A seguir, copiam-se os objetivos iniciais e descrevem-se os objetivos adicionados, classificados segundo as instruções:

Objetivos do Projeto Inicial:

1. Objetivo Geral Inicial: Analisar e comparar técnicas de otimização convexa para resolver problemas de Fluxo de Potência Ótimo, avaliando sua eficácia em diferentes topologias de rede utilizando para isso a biblioteca PowerModels.jl, implementada em linguagem Julia. (T)
Cumprimento: Concluído integralmente. As formulações de relaxação e aproximação foram estudadas e implementadas no ambiente Julia/PowerModels, servindo de base para o desenvolvimento das formulações de referência.

2. Revisar técnicas clássicas de relaxação convexa (SDP, SOCP, LP) para FPO: (T)
Cumprimento: Totalmente cumprido. Foi realizada ampla revisão bibliográfica sobre as relaxações semidefinida (SDP), cônica de segunda ordem (SOCP) e linearizada (DC), documentada no Capítulo 2 do TCC do bolsista.

3. Executar e analisar modelos convexos usando a biblioteca PowerModels.jl do Julia: (T)
Cumprimento: Totalmente cumprido. Foram implementadas e executadas rotinas de FPO AC, DC e relaxações cônicas (CodeComparing.jl e formulações F0/F1), avaliando limites de convergência e gaps de otimalidade.

4. Comparar desempenho em redes-teste IEEE usando a biblioteca pgLib-OPF: (P)
Cumprimento: Parcialmente cumprido e redirecionado. A comparação inicial em redes IEEE (como o sistema IEEE 300 barras) foi redirecionada para incorporar o formato de dados ANAREDE (.pwf), permitindo avaliar topologias brasileiras reais e casos pedagógicos com controle.

5. Verificar a robustez das relaxações em cenários com geração renovável intermitente: (P)
Cumprimento: Parcialmente cumprido e aprofundado na análise dos recortes do subsistema Nordeste (caso_red e caso_red2), caracterizados pela massiva concentração de geração eólica e solar do ciclo PAR/PEL 2027-2031 do ONS.

Novos Objetivos Incluídos Durante a Execução (O):

6. Implementação de arquitetura incremental de ações de controle em JuMP: Desenvolver quatro formulações manuais aditivas em JuMP (F2 a F5) introduzindo QLIM+VLIM, CSCA, CTAP e DERA via restrições flexíveis (soft-constraints) com variáveis de folga penalizadas e solver Ipopt. (O)
Cumprimento: Totalmente cumprido, constituindo a principal contribuição do Trabalho de Conclusão de Curso (TCC) do aluno.

7. Integração de dados operacionais do formato ANAREDE via PWF.jl: Automatizar a leitura e a extração de dados de controle dos registros DOPC e DLIN para estruturas indexadas no Julia. (O)
Cumprimento: Totalmente cumprido através de pipeline robusto de leitura e tratamento de topologia.

8. Bateria de testes em 27 casos e análise de clusters operativos: Avaliar sistematicamente o comportamento de convergência e o particionamento em clusters de equivalência em 27 redes, de 3 a 13.338 barras. (O)
Cumprimento: Totalmente cumprido mediante orquestrador em lote (runner).

9. Diagnóstico linearizado do SIN integral (FDC): Implementar fluxo linearizado DC sobre o cenário integral do SIN (13.338 barras) para avaliar factibilidade topológica. (O)
Cumprimento: Totalmente cumprido, confirmando a factibilidade do sistema linearizado.

## Resultados

A avaliação experimental foi conduzida mediante a execução das seis formulações de fluxo de potência (F0 a F5) e da formulação linearizada auxiliar (FDC) sobre um conjunto padronizado de vinte e sete sistemas no formato PWF. O conjunto abrange redes pedagógicas de três a nove barras, sistemas de médio porte (300 e 500 barras), dois recortes reais do subsistema Nordeste do Sistema Interligado Nacional (2.599 e 1.033 barras) e o cenário integral do SIN (13.338 barras). O critério de equivalência numérica para agrupamento em clusters operativos foi fixado em |Delta| <= 10^-4 p.u. simultaneamente sobre magnitude de tensão (V), ângulo de fase (theta), potências geradas (Pg, Qg) e fluxos de potência nos ramos.

Todas as tabelas detalhadas com os resultados numéricos completos estão disponibilizadas no documento anexo em formato paisagem (tabelas-anexo.pdf), sendo referenciadas e sumarizadas a seguir.

1. Síntese Global de Convergência

A Tabela 1 do documento em anexo (tabelas-anexo.pdf) sintetiza o desempenho global das formulações sobre os vinte e sete casos de teste avaliados, quantificando as ocorrências de solução local factível (OK), infactibilidade matemática (INF), interrupção por tempo limite (KIL), modelo inválido (INV) e erros de sintaxe no parser de dados (ERR).

[Tabela 1: Resumo numérico global de status de convergência das formulações — Consultar documento em anexo: tabelas-anexo.pdf]

Em síntese, os resultados da Tabela 1 mostram que as formulações desenvolvidas manualmente em JuMP (F2 a F5) convergiram com sucesso em 23 dos 27 casos testados (taxa de sucesso de 85,2%), superando amplamente o fluxo de potência clássico F1 (18 casos, 66,7%) e o fluxo de potência ótimo F0 (15 casos, 55,6%). Em nove redes específicas (4busfrank_vlim, 5busfrank_csca, test_system, caso_red2, 300bus, 3bus_DCline, 3bus_DSHL, 500bus e caso_red), as formulações manuais alcançaram convergência enquanto uma ou ambas as referências do PowerModels.jl falharam. Nos casos test_defaults, test_line_shunt e 3bus_corrections, a execução foi abortada por incompatibilidades de validação sintática do pacote de leitura de dados PWF, e não por falha dos modelos matemáticos.

2. Mapeamento de Convergência e Formação de Clusters

A Tabela 2 do anexo (tabelas-anexo.pdf) apresenta o status individualizado e o particionamento em clusters de soluções numericamente indistinguíveis para as formulações convergidas. A notação {A,B} . {C} indica que as formulações A e B atingiram o mesmo ponto operativo (desvio máximo |Delta| <= 10^-4 p.u.), enquanto C convergiu para um ponto operacional distinto.

[Tabela 2: Mapeamento de convergência e particionamento de clusters por sistema testado — Consultar documento em anexo: tabelas-anexo.pdf]

A análise dos clusters na Tabela 2 evidencia que, nas redes pedagógicas sem saturação de limites, as formulações F1 e F2 coincidem no cluster {F1,F2}, demonstrando que a formulação JuMP reproduz com exatidão o fluxo clássico. Quando as ações de controle CSCA e CTAP são ativadas, surgem clusters próprios numericamente distintos ({F3,F4,F5} ou {F3} . {F4,F5}), confirmando que o algoritmo ajusta as variáveis de susceptância e tap de forma ativa. Em redes de médio porte como o sistema IEEE 300 barras, observam-se cinco clusters totalmente distintos {F1} . {F2} . {F3} . {F4} . {F5}, comprovando o impacto progressivo de cada grau de liberdade adicionado à formulação.

3. Resultados nos Recortes Reduzidos do SIN (Metodologia de Fronteira Híbrida)

A Tabela 3 do anexo (tabelas-anexo.pdf) detalha os parâmetros e variáveis operativas obtidos nos recortes do subsistema Nordeste (caso_red de 2.599 barras e caso_red2 de 1.033 barras), originados do cenário Verão 2027/2028 Máxima Diurna do ONS (PAR/PEL 2027-2031).

[Tabela 3: Desempenho numérico e variáveis operativas agregadas sobre os recortes reduzidos do SIN — Consultar documento em anexo: tabelas-anexo.pdf]

Os dados da Tabela 3 revelam que, no caso_red2, o fluxo sem controles F1 declarou infactibilidade com magnitude de tensão fisicamente inaceitável (Vmin = -0,431 p.u. e Vmax = 1,935 p.u.). Em contrapartida, as formulações manuais com restrições flexíveis convergiram para perfis de tensão consistentes (entre 0,950 e 1,269 p.u.). A introdução conjunta de CSCA e CTAP na formulação F4 reduziu o valor da função objetivo de penalização para 9,56 x 10^-2 (uma redução de mais de cinco mil vezes em relação a F2), demonstrando a eliminação quase integral das violações de setpoints de tensão. No caso_red, observa-se uma variação substancial no balanço de potência reativa: a geração total Qg transitou de -16,02 p.u. (-1.602 MVAr de absorção líquida) em F1 para +8,78 p.u. (+878 MVAr de injeção) em F4, totalizando uma modulação de 2.480 MVAr decorrente da atuação direta dos bancos shunt chaveáveis liberados continuamente pelo algoritmo.

4. Diagnóstico Linearizado (DC) do Caso Integral do SIN (13.338 Barras)

A Tabela 4 do anexo (tabelas-anexo.pdf) sintetiza os resultados numéricos obtidos pela formulação auxiliar linearizada FDC (solve_dc_pf) aplicada sobre o arquivo integral do SIN (CASO_VER_MAXDIU.PWF).

[Tabela 4: Métricas do fluxo de potência linearizado FDC sobre o cenário SIN de 13.338 barras — Consultar documento em anexo: tabelas-anexo.pdf]

Conforme registrado na Tabela 4, a formulação linearizada convergiu em poucas iterações com status factível (LOCALLY_SOLVED) no Ipopt, retendo 13.283 barras ativas, 16.743 ramos e 346 geradores, totalizando 709,70 p.u. (~70,97 GW) de geração para atender 695,67 p.u. (~69,57 GW) de demanda ativa. Essa convergência atesta a integridade topológica dos dados lidos pelo parser, mas aponta aberturas angulares extremas (theta variando de -165,99 graus a +176,88 graus) e fluxos em ramo de até 99,50 p.u. (~9,95 GW), condições que extrapolam os limites físicos de validade da aproximação linearizada.

5. Análise de Divergência Barra a Barra no Caso Pedagógico 3bus_DCSC

A Tabela 5 do anexo (tabelas-anexo.pdf) expõe os valores nodais de tensão e ângulo para o sistema elementar de três barras com capacitor série controlável (3bus_DCSC.pwf), ilustrando a diferenciação numérica provocada por cada camada de controle.

[Tabela 5: Perfil barra a barra de tensões e ângulos no caso 3bus_DCSC — Consultar documento em anexo: tabelas-anexo.pdf]

A Tabela 5 evidencia quatro soluções distintas: F0 eleva as tensões das barras de geração ao teto operacional de 1,1000 p.u.; F1 estabelece o ponto de equilíbrio natural da rede (1,0290 p.u.); F2 realiza pequeno ajuste fino decorrente da penalização de setpoint (1,0352 p.u.); e as formulações F3 a F5, com controle de shunt ativo, deslocam a tensão para 1,0064 p.u., reduzindo a sobretensão na rede de acordo com os limites configurados.

## Discussão

A análise crítica dos resultados evidencia que a metodologia incremental de ações de controle desenvolvida em Julia atingiu plenamente a meta de aproximar as ferramentas acadêmicas abertas das práticas industriais do setor elétrico brasileiro, trazendo ganhos substantivos de convergência e interpretabilidade física.

1. Avaliação Crítica da Abordagem por Restrições Flexíveis (Soft-Constraints)

A discrepância fundamental observada entre as formulações manuais (F2 a F5) e as referências do pacote PowerModels.jl (F0 e F1) reside no tratamento das restrições operacionais. Formulações acadêmicas clássicas tratam limites de tensão (Vmin, Vmax) e de geração reativa (Qmin, Qmax) como restrições rígidas (hard-constraints). Em sistemas sob estresse operativo ou com parâmetros de controle rigorosos, os algoritmos de pontos interiores frequentemente declaram infactibilidade local ou divergem antes de encontrar um ponto factível.

A formulação desenvolvida em JuMP introduz variáveis de folga penalizadas quadraticamente na função objetivo com peso rho = 10^6. Como evidenciado pelos dados experimentais, essa modelagem permitiu convergir em 85,2% dos casos avaliados, contra apenas 55,6% do FPO clássico e 66,7% do fluxo de potência convencional. O caso caso_red2 (1.033 barras) ilustra esse comportamento com extrema nitidez: enquanto o fluxo sem controles F1 encerrou em infactibilidade com tensões espúrias e fisicamente impossíveis (Vmin = -0,431 p.u.), a formulação F2 recuperou o ponto operativo dentro da faixa permitida, e a inclusão das ações de controle CSCA e CTAP (F4) reduziu as violações a uma penalidade residual de apenas 9,56 x 10^-2. Isso comprova que as ações de controle propostas não apenas sustentam a convergência matemática, mas orientam o sistema em direção ao ponto operativo pretendido pelo operador.

2. Comportamento Operativo e Assinatura dos Controles Individuais

O particionamento das soluções em clusters de equivalência operativa confirmou a atuação física esperada de cada ação de controle adicionada à progressão:
- QLIM e VLIM (F2): As folgas de tensão s^v e de reativo s^q atuaram como amortecedores numéricos, restaurando a viabilidade em sete casos em que o modelo rígido falhou, demonstrando a capacidade da formulação de acomodar saturações de geradores.
- CSCA (F3): A liberação da susceptância shunt b_sh_s como variável contínua de decisão permitiu que o algoritmo ajustasse localmente o suporte reativo. No caso_red, essa ação provocou uma reversão expressiva de 2.480 MVAr no balanço de geração reativa total, aliviando o esforço de máquinas síncronas e reduzindo desvios de tensão nas barras adjacentes.
- CTAP (F4): O ajuste contínuo da relação de transformação t_ij introduziu graus de liberdade essenciais em redes com múltiplos transformadores em carga, empurrando as tensões de barras secundárias para os patamares nominais mais elevados.
- DERA (F5): A inclusão do termo linear de corte de carga ponderado por nível de tensão base (w_l = 10^3, 5 x 10^3, 10^4) comportou-se de forma estritamente consistente com a teoria: em redes com viabilidade reativa assegurada, as variáveis de corte mantiveram-se estritamente nulas (Delta Pd_l = 0), reproduzindo a solução da formulação F4. Em redes severamente estressadas, como 4busfrank_vlim e 500bus, o corte de carga foi acionado seletivamente nas barras de menor tensão (subtransmissão e distribuição), preservando a integridade das barras de extra-alta tensão (EAT).

3. O Desafio de Convergência no Cenário Integral do SIN (13.338 Barras)

O caso integral do SIN (CASO_VER_MAXDIU.PWF) constitui o cenário mais complexo do estudo e o único em que nenhuma das formulações de fluxo CA alcançou convergência dentro do limite operacional estipulado (3.000 iterações e 600 segundos de CPU). A análise desse comportamento afasta a hipótese de falha na inicialização do algoritmo:
1. Ponto de Partida: Todas as formulações manuais foram inicializadas com as tensões, ângulos e gerações resultantes do ponto convergido pelo programa ANAREDE presente no próprio arquivo PWF. O fato de a própria formulação F1 do PowerModels ter falhado partindo dessa mesma inicialização indica que o obstáculo é estrutural à transposição do modelo.
2. Diagnóstico da Formulação FDC: A resolução bem-sucedida da aproximação linearizada FDC sobre a rede integral (13.283 barras conexas e 70,97 GW de geração) confirma que a topologia está correta e que o sistema possui potência suficiente para suprir a demanda. O obstáculo reside, portanto, no severo mau condicionamento numérico do Jacobiano/Hessiano das equações CA, agravado pela presença de elos HVDC de grande porte tratados com injeções fixadas, intercâmbios de área e controle remoto de barras, associados à penalidade uniforme rho = 10^6 aplicada sobre treze mil nós.
3. Inviabilidade do DC como Ponto de Partida (Warm-Start): A solução DC apurou aberturas angulares de até +/- 176,88 graus e fluxos por ramo de até 9,95 GW, violando frontalmente a premissa de pequenas variações angulares (sen(Delta theta) ~= Delta theta). Esse perfil torna a solução linearizada um ponto inicial numericamente inferior ao próprio ponto lido do PWF.

4. Resposta ao Problema Enunciado e Limitações do Método

Em resposta à questão central formulada na introdução do trabalho — se é viável reproduzir, em uma biblioteca aberta e moderna da linguagem Julia, o conjunto de ações de controle operativas do ANAREDE aplicáveis ao SIN —, os resultados demonstram de forma inequívoca que a resposta é afirmativa. A formulação matemática em JuMP com restrições flexíveis não apenas reproduz as heurísticas do ANAREDE, mas supera as implementações clássicas do PowerModels.jl em robustez e convergência.

Identificam-se como limitações principais do trabalho: (i) o tratamento das grandezas de chaveamento (shunts CSCA e taps CTAP) como variáveis contínuas, sem etapa subsequente de discretização inteira mista (MINLP); (ii) a representação dos cortes DERA de forma suave e contínua, sem blocos discretos de alívio; e (iii) o tratamento estático dos elos de corrente contínua (HVDC). A superação destas limitações e a aplicação de técnicas de continuação homotópica sobre os parâmetros de penalidade definem as frentes de continuidade da pesquisa.

## Produtos e/ou Publicações

Durante a execução do plano de atividades do projeto PIBIC (ciclo 2025/2026), foram gerados os seguintes produtos técnicos, científicos e tecnológicos:

1. Trabalho de Conclusão de Curso (TCC) de Graduação:
   - Título: "Implementação de uma arquitetura incremental de ações de controle de Fluxo de Potência Ótimo em linguagem Julia"
   - Autor (Bolsista): Gabriel Rufino Montenegro
   - Orientador: Prof. Dr. Lucas Silveira Melo
   - Grau e Instituição: Engenharia Elétrica, Centro de Tecnologia, Universidade Federal do Ceará (UFC), Fortaleza, 2026.
   - Descrição: Monografia acadêmica de graduação completa em LaTeX, documentando a fundamentação teórica, a formulação analítica das seis variantes (F0 a F5), os testes nos 27 casos e a análise do cenário do SIN.

2. Protótipo de Software e Código-Fonte Aberto:
   - Suíte computacional modular em linguagem Julia contendo:
     - Scripts executáveis e independentes das formulações: (F0)OPF_PM.jl, (F1)PF_PM.jl, (F2)QLIM+VLIM.jl, (F3)QLIM+VLIM+CSCA.jl, (F4)QLIM+VLIM+CSCA+CTAP.jl, (F5)+DERA.jl e (FDC).jl.
     - Orquestrador automatizado de testes em lote (runner_analise_tcc.jl) com subprocessos isolados, controle de tempo limite (timeout) e gerador de relatórios consolidados em CSV.
     - Scripts de consolidação matricial e cálculo de clusters operativos (consolidar.jl e _consolidate_masters.jl).

3. Relatórios Técnicos Periódicos de Pesquisa:
   - Conjunto de 13 relatórios técnicos de progresso (short-reports) detalhando cronogramas, etapas de desenvolvimento, estudos comparativos entre formulações e análises de casos de teste específicos ao longo do período de pesquisa.

4. Apresentação Técnica e Material de Defesa:
   - Apresentação completa em formato Beamer LaTeX (Template_Beamer_UFC) contendo 50 lâminas técnicas estruturadas, diagramas metodológicos e roteiro detalhado de fala para defesa perante banca examinadora.

5. Produção Bibliográfica em Elaboração:
   - Artigo técnico-científico em fase final de redação e consolidação para submissão a evento científico de referência na área de sistemas de potência (Simpósio Brasileiro de Sistemas Elétricos — SBSE / Congresso Brasileiro de Automática — CBA), abordando a comparação de convergência entre as abordagens JuMP flexíveis e o PowerModels.jl.

## Avaliação do Bolsista

O bolsista Gabriel Rufino Montenegro demonstrou excelente desempenho, maturidade técnica e dedicação exemplar ao longo de todo o ciclo do projeto PIBIC 2025/2026. O plano de trabalho foi cumprido em sua totalidade, tendo o estudante atingido com elevado rigor científico todas as metas teóricas e práticas pactuadas. 

Dentre as competências evidenciadas, destacam-se: (i) a sólida apropriação dos fundamentos matemáticos do fluxo de potência ótimo e das técnicas de relaxação não linear; (ii) o domínio avançado da linguagem Julia e das ferramentas JuMP e Ipopt, empregadas na codificação de formulações não convexas de alta complexidade; (iii) a notável autonomia e capacidade de resolução de problemas, exemplificada pela implementação de um orquestrador automatizado para processamento em lote de 27 redes elétricas; e (iv) o diálogo produtivo com bases de dados reais do ONS e formulação de análises inovadoras, como o diagnóstico linearizado do SIN e a avaliação de recortes com fronteira híbrida.

O bolsista manteve pontualidade rigorosa nos relatórios periódicos, demonstrou proatividade nas discussões de pesquisa e materializou os resultados do projeto em seu Trabalho de Conclusão de Curso (TCC), aprovado com louvor e recomendação para continuidade em nível de pós-graduação. Diante dos expressivos resultados científicos e tecnológicos entregues, a avaliação global do desempenho do bolsista é classificada no patamar de excelência máxima (nota 10,0).
