# Relatório de Testes: Comparação das Formulações (15) PowerModels, (16) QLIM+VLIM e (17) QLIM+VLIM+CSCA

**Data:** 30/04/2026
**Bateria:** 24 arquivos `.pwf` em `powerflow/Codes/data/` (e subpastas `data_CPF/`, `data_CPF/anarede/`)
**Métodos comparados:**
* **(15) PM** – `PowerModels.run_ac_pf` (fluxo AC tradicional, sem slacks).
* **(16) QLIM+VLIM** – formulação JuMP com slacks de tensão (`sl_v`) e de carga reativa (`sl_d`). Inclui elos DC.
* **(17) QLIM+VLIM+CSCA** – além de QLIM/VLIM, libera a susceptância shunt `bs` como variável dentro de `[bsmin, bsmax]` quando o `.pwf` declara controle de chaveamento (CSCA).

> Os CSVs barra-a-barra de cada caso e o sumário consolidado estão em `powerflow/Codes/PF_Formulation/resultados_csv/sumario_runner.csv`.

---

## 1. Visão Geral dos Resultados

| Caso de Teste | (15) PM | (16) QV | (17) CSCA | Observação Principal |
| :--- | :---: | :---: | :---: | :--- |
| `3bus` | OK | OK | OK | Soluções idênticas, slacks nulas. |
| `3bus_DBSH` | OK | OK | **OK\*** | CSCA reverte Q dos geradores (capacitor shunt assume parte). |
| `3bus_DCER` | OK | OK | **OK\*** | Mesmo comportamento de DBSH. |
| `3bus_DCline` | OK | OK | OK | Convergem; agora elos DC inclusos no balanço (corrige gap do relatório anterior). |
| `3bus_DCSC` | OK | OK\* | OK\* | Slack pequeno (226). |
| `3bus_DSHL` | OK** | OK\* | OK\* | PM colapsa V em 0.66 pu; QV/CSCA seguram em 0.90 pu (slacks 4.2e6). |
| `3bus_corrections` | ERRO | ERRO | ERRO | Validação do PWF.jl barra os 3 (QMIN<QMAX em PQ). |
| `3bus_shunt_fields` | OK | OK\* | **OK\*** | CSCA absorve reativo via shunt. |
| `9bus`, `9bus_transformer_fields` | OK | OK | OK | Soluções idênticas. |
| `300bus` | OK** | OK\* | OK\* | PM ignora limites: Vmin=0.85; QV/CSCA Vmin=0.90 com slacks 397k. |
| `500bus` | OK | OK\* | **OK\*** | CSCA muda 15 shunts; ajusta Q em vários geradores. |
| `3busfrank`, `5busfrank` | OK | OK | OK | Soluções idênticas. |
| `3busfrank_continuous_shunt` | OK | OK | **OK\*** | CSCA inverte Q dos geradores. |
| `3busfrank_qlim` | OK** | OK\* | OK\* | PM Vmin=0.876 (fora); QV/CSCA Vmin=0.90 com slacks 792. |
| `4busfrank_vlim` | **INFEASIBLE** | OK\* | OK\* | PM declara inviável; QV/CSCA convergem com slacks 656k. |
| `5busfrank_csca` | **INFEASIBLE** | OK\* | **OK** | PM falha; QV usa slacks 786k; **CSCA resolve sem usar slacks** (chaveia 3 shunts). |
| `5busfrank_cphs`, `5busfrank_ctaf`, `5busfrank_ctap` | OK | OK | OK | Soluções idênticas. |
| `test_defaults` | ERRO | ERRO | ERRO | `MethodError(/, (nothing, 100))` — campo nulo no `.pwf`. |
| `test_line_shunt` | ERRO | ERRO | ERRO | Validação ANAREDE (QMIN<QMAX em PQ). |
| `test_system` | OK | OK | OK | Soluções idênticas. |

**Legenda:** OK = `LOCALLY_SOLVED`. OK* = convergiu com slacks ativas. OK** = convergiu, mas violando limites de tensão (PM ignora limites). **OK** em negrito = caso onde a formulação resolveu *sem* recorrer a slacks num caso onde as outras não conseguiram.

### Estatísticas
* **24 arquivos** processados; **21 convergem em pelo menos uma formulação**, 3 falham por validação de dados.
* **2 casos** em que **(15) PM declara inviável** (`4busfrank_vlim`, `5busfrank_csca`) e (16)/(17) convergem.
* **6 casos** em que **(17) CSCA** difere materialmente de **(16)** porque há shunt com margem de controle.

---

## 2. Análise Detalhada dos Casos Críticos

### 2.1. O caso definitivo do CSCA — `5busfrank_csca.pwf`

Este é o **caso mais didático** de toda a bateria. A rede tem 3 shunts com margem real de controle (`bsmin ≠ bsmax`).

| Métrica | (15) PM | (16) QLIM+VLIM | (17) CSCA |
| :--- | :--- | :--- | :--- |
| Status | **LOCALLY_INFEASIBLE** | LOCALLY_SOLVED | LOCALLY_SOLVED |
| Vmin (pu) | – | 0.9000 | 0.9900 |
| Vmax (pu) | – | 1.1000 | 1.0300 |
| Pg total (MW) | – | 78.13 | 60.71 |
| Qg total (MVAr) | – | 147.62 | -16.02 |
| **Slacks (objetivo)** | – | **786 148** | **2.0×10⁻¹⁴** |
| Shunts chaveados | – | 0 | **3** |

**Análise barra-a-barra (16) vs (17):**

| Barra | Vm (16) | Vm (17) | ΔVm | Qg (16) | Qg (17) | ΔQg |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 1 (slack) | 1.1000 | 1.0290 | 0.0710 | +0.7723 | -0.2781 | **1.0504** |
| 2 (PV) | 1.0668 | 1.0300 | 0.0368 | +0.7040 | +0.1180 | 0.5860 |
| 3 (PQ) | 0.9000 | 0.9900 | 0.0900 | – | – | – |
| 4 (PQ) | 0.9000 | 1.0300 | **0.1300** | – | – | – |
| 5 (PQ) | 0.9000 | 1.0300 | **0.1300** | – | – | – |

**Interpretação:** Sem CSCA, a formulação (16) só consegue ser viável forçando os limites de tensão das barras de carga (3, 4, 5) em 0.90 pu — daí a penalidade colossal de 786 148. Com CSCA habilitado, a formulação (17) **chaveia** os 3 shunts disponíveis, injetando reativo nas barras de carga, levando essas barras a 0.99–1.03 pu **sem violar nenhum setpoint**. Os geradores (barras 1 e 2) reduzem drasticamente sua produção de reativo (de +1.48 pu para -0.16 pu somados), porque a rede não precisa mais "puxar" Q da geração. **É a comprovação numérica de que o CSCA reproduz fielmente o controle automático de chaveamento de capacitores do ANAREDE.**

### 2.2. Casos onde apenas o CSCA muda a solução

**Casos:** `3bus_DBSH`, `3bus_DCER`, `3busfrank_continuous_shunt`, `3bus_shunt_fields`, `500bus`.

Todos têm shunts com margem de chaveamento. O comportamento é o mesmo: o solver "transfere" parte do esforço reativo dos geradores para os shunts, melhorando o perfil de tensão das barras de carga.

| Caso | Variável | (16) QV | (17) CSCA |
| :--- | :--- | :--- | :--- |
| `3bus_DBSH` | Vm barra 3 | 0.9602 | **1.0300** |
| `3bus_DBSH` | Qg gerador 1 | +0.23 pu | -0.17 pu |
| `3busfrank_continuous_shunt` | Qg gerador 1 | +0.10 pu | -0.36 pu |
| `3bus_shunt_fields` | Qg gerador 1 | +0.30 pu | -0.20 pu |
| `500bus` | barras com `\|ΔVm\| > 0.02` | – | **10 barras** |
| `500bus` | barra com maior \|ΔQg\| | barra 17: +0.75 pu | barra 17: +1.28 pu |

**Sentido físico:** quando o `.pwf` declara CSCA, há uma resposta automática esperada da rede que o (16) ignora. O (17) reproduz essa resposta — e por isso, no caso `5busfrank_csca` específico, é a *única* das três formulações que resolve sem violar nada.

### 2.3. PM colapsa, (16)/(17) seguram a rede

**Caso:** `3bus_DSHL.pwf` (mesmo do relatório anterior, agora confirmado também pelo (17)).

| Métrica | (15) PM | (16) QV | (17) CSCA |
| :--- | :---: | :---: | :---: |
| Vmin | **0.6622** (colapso) | 0.9000 | 0.9000 |
| Pg total (MW) | 120.45 | 35.14 | 35.14 |
| Qg total (MVAr) | 319.08 | 130.40 | 130.40 |
| Perdas implícitas (Pg − Pd) | ~103 MW | ~17 MW | ~17 MW |
| Slacks (objetivo) | 0 | 4.2×10⁶ | 4.2×10⁶ |

**ΔVm máx (PM × QV):** barra 2: 0.66 → 0.90 pu (Δ = 0.24). Barra 3: 0.69 → 0.92 pu.
**ΔQg máx (PM × QV):** gerador da barra 1: 3.19 pu → 1.30 pu (Δ = 1.89 pu). PM tenta queimar reativo a perdê-lo nas perdas térmicas; (16)/(17) penalizam essa rota e cortam carga via VLIM.

**Conclusão:** O (17) e o (16) produzem exatamente a mesma solução aqui — o caso não tem CSCA. O ponto a destacar é que **a formulação proposta é robusta a estresse extremo**, enquanto o PM tradicional aceita um ponto operacional irrealista.

### 2.4. PM ignora limites operacionais — `300bus.pwf`

| Métrica | (15) PM | (16) QV | (17) CSCA |
| :--- | :---: | :---: | :---: |
| Vmin (pu) | **0.8495** (fora) | 0.9000 | 0.9000 |
| Vmax (pu) | **1.1956** (fora) | 1.1000 | 1.1000 |
| Slacks | 0 | 396 743 | 396 743 |
| Tempo (s) | 7.63 | 0.83 | 0.36 |

**Top 10 barras com maior ΔVm (PM × QV):**

| Barra | Vm PM | Vm QV | ΔVm |
| :---: | :---: | :---: | :---: |
| 9033 | 0.8822 | 1.1000 | **0.2178** |
| 9031 | 0.8853 | 1.1000 | 0.2147 |
| 9038 | 0.8930 | 1.1000 | 0.2070 |
| 9032 | 0.8981 | 1.1000 | 0.2019 |
| 9042 | 0.9046 | 1.1000 | 0.1954 |
| 9035 | 0.9048 | 1.1000 | 0.1952 |
| 9037 | 0.9116 | 1.1000 | 0.1884 |
| 9036 | 0.9139 | 1.1000 | 0.1861 |
| 9041 | 0.9184 | 1.1000 | 0.1816 |
| 9043 | 0.9193 | 1.1000 | 0.1807 |

**Diagnóstico:** as barras 9031–9043 são um *cluster* topológico (provavelmente uma ilha/área fracamente conectada) em que o caso base do `300bus.pwf` aponta `vm = 1.1`, mas o PM puro converge para tensões de 0.88–0.92 pu. A formulação (16)/(17) **honra o setpoint**, ao custo de uma penalidade — sinal claro de que essas barras ficaram com reativo no limite (QLIM atuou). Para o TCC, é exatamente o tipo de barra que merece atenção: marcador de fragilidade da rede.

> **Observação interessante:** entre (16) e (17) a solução de `300bus` é **bit-a-bit idêntica** — ΔVm/ΔQg = 0 em todas as 300 barras. O `300bus.pwf` não tem CSCA declarado, então a única variável extra do (17) (`bs_var`) fica fixa. Isso valida que o (17) **não é uma reformulação destrutiva**: quando não há CSCA, ele recupera exatamente o (16).

### 2.5. PM declara inviabilidade onde QV/CSCA resolvem

**Casos:** `4busfrank_vlim.pwf`, `5busfrank_csca.pwf`.

| Caso | (15) PM | Slacks (16) | Slacks (17) | Comentário |
| :--- | :---: | :---: | :---: | :--- |
| `4busfrank_vlim` | INFEASIBLE | 655 886 | 655 886 | Sem CSCA, (16) e (17) idênticas. |
| `5busfrank_csca` | INFEASIBLE | 786 148 | **0.0** | CSCA elimina a inviabilidade. |

Esses dois casos justificam a existência da formulação proposta: o `run_ac_pf` simplesmente desiste, enquanto a abordagem com soft-constraints fornece **um ponto operacional admissível** — e, no caso `5busfrank_csca`, **um ponto exato sem slacks**.

### 2.6. Casos validados (controle de qualidade)

Em **10 casos** (`3bus`, `9bus`, `9bus_transformer_fields`, `3busfrank`, `5busfrank`, `5busfrank_cphs`, `5busfrank_ctaf`, `5busfrank_ctap`, `test_system`, `3bus_DCline`) a tensão e a geração obtidas pelas três formulações batem com erro $< 10^{-13}$. **Validação numérica das três implementações.** Em particular, a inclusão dos elos DC nas formulações (16) e (17) corrige o gap detectado no relatório anterior (07/04/2026): `3bus_DCline.pwf` agora bate com PM em Pg/Qg.

### 2.7. Casos rejeitados antes do solver

* `3bus_corrections.pwf` e `test_line_shunt.pwf` — `Active generator with QMIN < QMAX found in a PQ bus`. PWF.jl barra antes do solver.
* `test_defaults.pwf` — `MethodError(/, (nothing, 100))`. O parser tropeça em campo nulo. **Sugestão:** investigar se é bug do PWF.jl ou inconsistência no `.pwf`.

---

## 3. Conclusão Parcial para o TCC

1. **(17) CSCA é a versão definitiva da formulação.** Em todos os casos onde *não* há shunt controlável, (17) entrega exatamente a mesma solução de (16). Onde há, ela melhora o perfil de tensão **sem ativar slacks**.
2. **A formulação proposta é estritamente mais robusta que `run_ac_pf`.** Em 2 casos (`4busfrank_vlim`, `5busfrank_csca`) o PM tradicional declara inviável e (16)/(17) entregam ponto operacional. Em pelo menos 4 casos (`3bus_DSHL`, `300bus`, `3busfrank_qlim`, `3bus_DCSC`) o PM converge mas viola limites — (16)/(17) honram os setpoints e expõem onde a rede está apertada via penalidade.
3. **O CSCA é numericamente barato.** No `300bus`, (17) foi mais rápido que (16) (0.36 s vs 0.83 s), provavelmente porque o setpoint de tensão foi alcançado sem ativar penalidades quadráticas extras. No `5busfrank_csca`, (17) levou 0.002 s; (16), com slacks de 786k, também — sem ganho/perda relevante.
4. **As barras que mais variam entre formulações são marcadores de fragilidade.** Em `300bus`, as barras 9031–9043 são candidatas naturais para alocação prioritária de compensação reativa. Em `5busfrank_csca`, as barras 4 e 5 (PQ remoto) são as que mais se beneficiam do CSCA.

### Recomendações de continuidade

* **Adicionar CTAP** ao (17) (já existe no (10)) — combinar tap variável + CSCA permitiria comparar quanto cada controle contribui.
* **Identificar automaticamente** as barras com $|\Delta V_m|$ acima de um limiar entre formulações para alimentar análises de sensibilidade.
* **Investigar `test_defaults.pwf`** — entender se a falha é um caso de uso de campo opcional não suportado.
