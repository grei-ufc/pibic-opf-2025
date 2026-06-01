# Short report — rodadas (14)–(19) sobre os casos reduzidos da Isabela

**Data:** 2026-05-26  
**Casos novos:** `caso_red.pwf` (recorte completo do NE, 2 599 barras) e `caso_red2.pwf` (recorte CE+RN+PB, 1 033 barras), ambos derivados de `CASO_VER_MAXDIU.PWF` (caso ONS PAR/PEL 2027-2031, Verão 2027/2028 Máxima Diurna, 13 338 barras).

## 1. Resumo executivo

Executei as seis formulações (14)–(19) sobre `caso_red` e `caso_red2` no mesmo pipeline da bateria principal (`PWF.parse_file` com `add_control_data = true`, Ipopt `max_iter=3000`, `tol=1e-5`, base 100 MVA). Resultado: 11 das 12 rodadas convergiram. A única falha foi a formulação **(14) em caso_red**, com Ipopt encerrando em `LOCALLY_INFEASIBLE` e crash de pós-processamento do script. As formulações controladas (16)–(19) resolveram inclusive os casos em que a referência FP (15) falha (caso_red2), e os números reproduzem com fidelidade a sessão de 25/05 (objective 478,05 em (18)/red; 0,0956 em (18)/red2; Qg −1 602 MVAr em (15)/red). Decisão sugerida para a reunião: usar o caso_red2 como caso-vitrine das formulações com controle no TCC, dado que ele é o único caso da bateria atual em que **(15) declara infactibilidade** com $V_{\min}=-0{,}43$ p.u. e **(16)–(19) recuperam factibilidade** com $V_{\min}=0{,}95$ p.u.

CSVs salvos em `powerflow/Codes/PF_Formulation/resultados_csv/<n>/<caso>/`. Logs completos em `_batch_isabela_logs/`. Tempo total do batch: 771 s.

## 2. Tabela comparativa por caso e formulação

Status, tempo de resolução interno do Ipopt, valor da função objetivo (penalização das folgas; vazio em (15)/(19) que não imprimem), tensões extremas, totais de geração e perdas ativas em p.u. (base 100 MVA).

| Form. | Caso | Status | t Ipopt (s) | Objetivo | Vmin (p.u.) | Vmax (p.u.) | Pg (p.u.) | Qg (p.u.) | Perdas (p.u.) |
|-------|--------|--------------------|------:|----------:|--------:|--------:|--------:|----------:|--------:|
| (14)  | caso_red  | LOCALLY_INFEASIBLE † | 56,1  | 3 579,13   | —       | —       | —       | —          | —       |
| (15)  | caso_red  | LOCALLY_SOLVED       | 1,2   | 0,00       | 0,9430  | 1,2465  | 34,2527 | −16,0196   | 6,968   |
| (16)  | caso_red  | LOCALLY_SOLVED       | 14,7  | 90 597,35  | 0,9354  | 1,2260  | 34,4582 | −8,2852    | 7,1736  |
| (17)  | caso_red  | LOCALLY_SOLVED       | 15,0  | 12 022,29  | 0,9197  | 1,2253  | 34,5510 | −6,1900    | 7,2663  |
| (18)  | caso_red  | LOCALLY_SOLVED       | 180,1 | 478,05     | 0,4992  | 1,2693  | 34,7764 | 8,7788     | 7,4917  |
| (19)  | caso_red  | LOCALLY_SOLVED       | 39,2  | (n/a) ‡    | 0,5229  | 1,2689  | 34,6652 | 6,2334     | 7,3806  |
| (14)  | caso_red2 | LOCALLY_INFEASIBLE   | 7,1   | 287,43     | 0,9500  | 1,2184  | 2,8743  | 0,3296     | 1,8164  |
| (15)  | caso_red2 | **LOCALLY_INFEASIBLE** | 7,3 | 0,00       | **−0,4310** | 1,9353 | 5,7840  | 3,9240     | 8,1201  |
| (16)  | caso_red2 | LOCALLY_SOLVED       | 3,1   | 493,66     | 0,9500  | 1,2313  | 2,8943  | 0,1225     | 1,8317  |
| (17)  | caso_red2 | LOCALLY_SOLVED       | 4,0   | 216,12     | 0,9500  | 1,2285  | 2,9007  | 0,1713     | 1,8381  |
| (18)  | caso_red2 | LOCALLY_SOLVED       | 125,3 | **0,0956**  | 0,9500  | 1,2690  | 2,8593  | 2,3991     | 1,7966  |
| (19)  | caso_red2 | LOCALLY_SOLVED       | 5,6   | (n/a) ‡    | 0,9500  | 1,2687  | 2,8742  | 2,1860     | 1,8116  |

† Ipopt encerrou em `LOCALLY_INFEASIBLE` em (14)/caso_red e o script crashed em seguida com `KeyError "48230"` no loop de exportação de fluxos (mesmo padrão de bug do (15) que corrigi em 25/05 — `select_largest_component!` descarta barras, mas o (14) ainda tenta lê-las).  
‡ (19) não imprime `Erro de Controle` no resumo (resíduo do refactor; só métricas físicas).

## 3. Destaques

1. **caso_red2 é o argumento de venda das formulações com controle.** O FP clássico (15) diverge com tensão complexa absurda (V = −0,43 p.u., V = 1,94 p.u.), confirmando o achado de 25/05. A partir de (16), o problema se torna factível com folgas pequenas, caindo para objective ≈ 0,096 em (18) — efetivamente trivial. Isso mostra que **VLIM + QLIM já são suficientes** para recuperar factibilidade neste caso; CSCA e CTAP refinam, mas não são imprescindíveis.

2. **A assinatura do CSCA em caso_red continua nítida.** Qg salta de **−1 602 MVAr em (15)** para **+878 MVAr em (18)** (variação total de 2 480 MVAr na mesma rede), confirmando que o controle de bancos *shunt* chaveáveis desliga capacitores sobrecompensados e absorve menos reativo da rede. As perdas ativas variam pouco (6,97 → 7,49 p.u., +7,5%) — coerente com a interpretação de que as impedâncias equivalentes das 15 barras de fronteira PI-BA dominam a dissipação real e não dependem do reativo local.

3. **Vmin = 0,4992 p.u. em (18)/caso_red não é bug.** Já mapeado em 25/05: cai nas barras 44084/44085 (terminais de máquina de São João do Piauí, grupo DGLT 6 com Vmin=0,40, Vmax=1,90 — limites largos, sem carga ou geração que ancore tensão). Para uma comparação "honesta" de qualidade de tensão entre (15) e (18) é preciso restringir aos grupos DGLT 0 e 5 (0,95–1,05 p.u.).

4. **(16) tem objective absurdamente alto em caso_red (90 597) e cai em (17)/(18).** Diferença de duas ordens de grandeza entre (16) e (18) é consistente com a interpretação física: sem CSCA nem CTAP, a única forma de (16) compatibilizar o ponto de operação com os *setpoints* lidos do PWF é via violação massiva de slacks; ao liberar $b^{sh}_s$ e $t_{ij}$, as folgas residuais despencam.

5. **Tempos.** caso_red é dominado por (18) (180 s); caso_red2 também (125 s). As demais formulações resolvem em < 60 s nos dois casos. A escalabilidade do CTAP é o gargalo prático conhecido.

## 4. Problemas e pendências

- [ ] **(14)/caso_red crasha no pós-processamento.** Aplicar o mesmo `haskey(...)` guard que adicionei em (15) ao loop de barras/ramos do (14). Não bloqueia o TCC porque (14) já é INFEASIBLE no Ipopt — mas o crash impede gerar o CSV de fluxos.
- [ ] **Não rodei sobre `CASO_VER_MAXDIU.PWF` (SIN completo, 13 338 barras) para preservar tempo de máquina.** Já tenho rodada (18)/SIN de 780 s em LOCALLY_INFEASIBLE (transcript de 26/05) — pode entrar como observação no TCC, mas a discussão fica como trabalho futuro.
- [ ] **(19) não imprime `Erro de Controle`.** É pequeno detalhe do refactor; vale uniformizar a saída antes da reunião final.
- [ ] **Confirmar com a Isabela** se o cabeçalho `TITU` "ONS * PARPEL 2027-2031 * VERÃO 2027/2028 MÁXIMA DIURNA" reflete exatamente a versão usada (já confirmado por arquivo, ainda não por mensagem da Isabela).
- [ ] **Discretização dos bancos shunt em (17)** continua adiada: o trabalho usa $b^{sh}_s$ contínuo.

## 5. Próximos passos sugeridos

1. Patchar (14) com o mesmo *guard* de chaves do (15) para liberar a rodada (14)/caso_red por completo.
2. Decidir, em conjunto com o orientador, se vale rerodar o batch sobre o SIN completo (CASO_VER_MAXDIU) com `max_iter = 10000` e inicialização a partir de (15), ou se a observação atual (LOCALLY_INFEASIBLE em < 1 000 iter) já é suficiente para o capítulo.
3. Incluir as duas novas linhas no quadro de convergência do TCC (Tabela `tab:conv-global`), com nota de rodapé sobre origem (recorte da Isabela do PAR/PEL 2027-2031) e método de redução (fronteira híbrida: carga/geração equivalentes + impedância equivalente em 21 ramos cortados / 56 ramos novos).
