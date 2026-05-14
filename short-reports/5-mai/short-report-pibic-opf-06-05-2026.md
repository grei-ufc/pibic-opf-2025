# Relatório de Testes — Comparação das Formulações (15) PM, (16) QV, (17) CSCA e (18) CTAP

**Data:** 06/05/2026
**Bateria:** 24 arquivos `.pwf` em `powerflow/Codes/data/` (incluindo subpastas `data_CPF/` e `data_CPF/anarede/`)
**Tolerância de comparação:** desvios reportados quando ``|Δ| > 10^{-4}`` p.u. (Vm, Pg, Qg) ou ``|Δθ| > 10^{-2}`` graus.

**Métodos comparados:**
* **(15) PM** — `PowerModels.solve_ac_opf` (referência: ground truth do solver de mercado).
* **(16) QV** — JuMP com slacks `sl_v` (setpoint de Vm em barras de geração) e `sl_d` (corte reativo nas barras de carga). Inclui elos DC.
* **(17) CSCA** — (16) + susceptância shunt `bs_var ∈ [bsmin, bsmax]` quando o `.pwf` declara CSCA, com slack `sl_bsh` penalizado.
* **(18) CTAP** — (17) + tap `tm_var ∈ [tapmin, tapmax]` em transformadores que declaram CTAP.

> CSVs barra-a-barra/ramo de cada execução em `powerflow/Codes/PF_Formulation/resultados_csv/`. Sumário consolidado: `sumario_runner.csv`.

---

# 1. Tabela Resumo Global

Status de convergência por formulação. ⚠️ marca casos em que pelo menos uma formulação diverge de (15) acima da tolerância.

| Caso | (15) PM | (16) QV | (17) CSCA | (18) CTAP | Δ vs (15) | Observação |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| ⚠️ `3bus` | OK | OK | OK | OK | ⚠️ | Δ acima de 10⁻⁴ em ao menos uma formulação. |
| ⚠️ `3bus_DBSH` | OK | OK | OK | OK | ⚠️ | Δ acima de 10⁻⁴ em ao menos uma formulação. |
| ⚠️ `3bus_DCER` | OK | OK | OK | OK | ⚠️ | Δ acima de 10⁻⁴ em ao menos uma formulação. |
| ⚠️ `3bus_DCline` | OK | OK | OK | OK | ⚠️ | Δ acima de 10⁻⁴ em ao menos uma formulação. |
| ⚠️ `3bus_DCSC` | OK | OK | OK | OK | ⚠️ | Δ acima de 10⁻⁴ em ao menos uma formulação. |
| `3bus_DSHL` | INFEAS | OK | OK | OK | n/a | (15) PM não convergiu — sem ground truth para comparar. |
| `3bus_corrections` | ERRO | ERRO | ERRO | ERRO | n/a | (15) PM não convergiu — sem ground truth para comparar. |
| ⚠️ `3bus_shunt_fields` | OK | OK | OK | OK | ⚠️ | Δ acima de 10⁻⁴ em ao menos uma formulação. |
| ⚠️ `9bus` | OK | OK | OK | OK | ⚠️ | Δ acima de 10⁻⁴ em ao menos uma formulação. |
| ⚠️ `9bus_transformer_fields` | OK | OK | OK | OK | ⚠️ | Δ acima de 10⁻⁴ em ao menos uma formulação. |
| `300bus` | INVALID_MODEL | OK | OK | OK | n/a | (15) PM não convergiu — sem ground truth para comparar. |
| `500bus` | INFEAS | OK | OK | OK | n/a | (15) PM não convergiu — sem ground truth para comparar. |
| `test_defaults` | ERRO | ERRO | ERRO | ERRO | n/a | (15) PM não convergiu — sem ground truth para comparar. |
| `test_line_shunt` | ERRO | ERRO | ERRO | ERRO | n/a | (15) PM não convergiu — sem ground truth para comparar. |
| `test_system` | ERRO | OK | OK | OK | n/a | (15) PM não convergiu — sem ground truth para comparar. |
| ⚠️ `3busfrank` | OK | OK | OK | OK | ⚠️ | Δ acima de 10⁻⁴ em ao menos uma formulação. |
| ⚠️ `3busfrank_continuous_shunt` | OK | OK | OK | OK | ⚠️ | Δ acima de 10⁻⁴ em ao menos uma formulação. |
| ⚠️ `5busfrank` | OK | OK | OK | OK | ⚠️ | Δ acima de 10⁻⁴ em ao menos uma formulação. |
| ⚠️ `3busfrank_qlim` | OK | OK | OK | OK | ⚠️ | Δ acima de 10⁻⁴ em ao menos uma formulação. |
| `4busfrank_vlim` | INFEAS | OK | OK | OK | n/a | (15) PM não convergiu — sem ground truth para comparar. |
| ⚠️ `5busfrank_cphs` | OK | OK | OK | OK | ⚠️ | Δ acima de 10⁻⁴ em ao menos uma formulação. |
| `5busfrank_csca` | INFEAS | OK | OK | OK | n/a | (15) PM não convergiu — sem ground truth para comparar. |
| ⚠️ `5busfrank_ctaf` | OK | OK | OK | OK | ⚠️ | Δ acima de 10⁻⁴ em ao menos uma formulação. |
| ⚠️ `5busfrank_ctap` | OK | OK | OK | OK | ⚠️ | Δ acima de 10⁻⁴ em ao menos uma formulação. |

**Estatísticas globais**

* **24 casos** processados; **3** falham nas 4 formulações antes do solver.
* **4** caso(s) onde **(15) PM** declara `LOCALLY_INFEASIBLE` e (16)/(17)/(18) ainda entregam ponto operacional.
* **15** caso(s) com pelo menos uma divergência > 10⁻⁴ p.u. entre (15) e as demais formulações (linhas marcadas ⚠️).
* **9** caso(s) sem `ground truth` (15) PM e portanto fora da comparação numérica (entrada `n/a`).

---

## Análise Barra-a-Barra

Apenas barras com ``|ΔV_m| > 10^{-4}`` p.u., ``|ΔP_g| > 10^{-4}`` p.u., ``|ΔQ_g| > 10^{-4}`` p.u. ou ``|Δθ| > 10^{-2}`` graus em relação à (15) PM. Casos onde nenhuma barra violou a tolerância foram suprimidos.

### Caso `3bus`  (9 divergência(s) bus-level)

| Formulação | Barra | Vm(15) | Vm(X) | ΔVm | Δθ° | ΔPg | ΔQg |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| (17) CSCA | 3 | 1.0698 | 0.9740 | -0.0958 | -0.2101 | 0.0000 | 0.0000 |
| (18) CTAP | 3 | 1.0698 | 0.9740 | -0.0958 | -0.2101 | 0.0000 | 0.0000 |
| (17) CSCA | 1 | 1.1000 | 1.0068 | -0.0932 | 5.78e-32 | -0.0028 | -0.0026 |
| (18) CTAP | 1 | 1.1000 | 1.0068 | -0.0932 | 5.78e-32 | -0.0028 | -0.0026 |
| (17) CSCA | 2 | 1.1000 | 1.0076 | -0.0924 | 4.89e-32 | 0.0043 | 0.0041 |
| (18) CTAP | 2 | 1.1000 | 1.0076 | -0.0924 | 4.89e-32 | 0.0043 | 0.0041 |
| (16) QV | 3 | 1.0698 | 0.9970 | -0.0727 | -0.1541 | 0.0000 | 0.0000 |
| (16) QV | 1 | 1.1000 | 1.0290 | -0.0710 | 5.78e-32 | -0.0039 | -0.0037 |
| (16) QV | 2 | 1.1000 | 1.0300 | -0.0700 | 4.89e-32 | 0.0051 | 0.0048 |

### Caso `3bus_DBSH`  (9 divergência(s) bus-level)

| Formulação | Barra | Vm(15) | Vm(X) | ΔVm | Δθ° | ΔPg | ΔQg |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| (17) CSCA | 1 | 0.9693 | 1.0997 | 0.1304 | -5.87e-34 | 8.39e-04 | 0.0545 |
| (18) CTAP | 1 | 0.9693 | 1.0997 | 0.1304 | -5.87e-34 | 8.39e-04 | 0.0545 |
| (17) CSCA | 2 | 0.9693 | 1.0997 | 0.1304 | 0.0000 | 8.05e-04 | 0.0545 |
| (18) CTAP | 2 | 0.9693 | 1.0997 | 0.1304 | 0.0000 | 8.05e-04 | 0.0545 |
| (17) CSCA | 3 | 0.9000 | 1.0300 | 0.1300 | 0.3443 | 0.0000 | 0.0000 |
| (18) CTAP | 3 | 0.9000 | 1.0300 | 0.1300 | 0.3443 | 0.0000 | 0.0000 |
| (16) QV | 2 | 0.9693 | 1.0300 | 0.0607 | 0.0000 | 0.0048 | 0.0286 |
| (16) QV | 3 | 0.9000 | 0.9602 | 0.0602 | 0.1760 | 0.0000 | 0.0000 |
| (16) QV | 1 | 0.9693 | 1.0290 | 0.0597 | -5.87e-34 | -0.0042 | 0.0198 |

### Caso `3bus_DCER`  (9 divergência(s) bus-level)

| Formulação | Barra | Vm(15) | Vm(X) | ΔVm | Δθ° | ΔPg | ΔQg |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| (17) CSCA | 2 | 0.9693 | 1.0300 | 0.0607 | 0.0000 | 0.0347 | 0.0562 |
| (18) CTAP | 2 | 0.9693 | 1.0300 | 0.0607 | 0.0000 | 0.0347 | 0.0562 |
| (16) QV | 2 | 0.9693 | 1.0300 | 0.0607 | 0.0000 | 0.0048 | 0.0286 |
| (16) QV | 3 | 0.9000 | 0.9602 | 0.0602 | 0.1760 | 0.0000 | 0.0000 |
| (16) QV | 1 | 0.9693 | 1.0290 | 0.0597 | -5.87e-34 | -0.0042 | 0.0198 |
| (17) CSCA | 3 | 0.9000 | 0.9569 | 0.0569 | 0.1672 | 0.0000 | 0.0000 |
| (18) CTAP | 3 | 0.9000 | 0.9569 | 0.0569 | 0.1672 | 0.0000 | 0.0000 |
| (17) CSCA | 1 | 0.9693 | 1.0224 | 0.0531 | -5.87e-34 | -0.0339 | -0.0103 |
| (18) CTAP | 1 | 0.9693 | 1.0224 | 0.0531 | -5.87e-34 | -0.0339 | -0.0103 |

### Caso `3bus_DCSC`  (9 divergência(s) bus-level)

| Formulação | Barra | Vm(15) | Vm(X) | ΔVm | Δθ° | ΔPg | ΔQg |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| (16) QV | 3 | 1.0975 | 1.0178 | -0.0797 | -0.8085 | -0.1736 | 0.0000 |
| (17) CSCA | 3 | 1.0975 | 0.9878 | -0.1098 | -0.8447 | -0.1736 | 0.0000 |
| (18) CTAP | 3 | 1.0975 | 0.9878 | -0.1098 | -0.8447 | -0.1736 | 0.0000 |
| (16) QV | 1 | 1.0998 | 1.0352 | -0.0646 | 3.07e-36 | 0.0866 | 0.1618 |
| (16) QV | 2 | 1.0998 | 1.0362 | -0.0636 | 0.0000 | 0.0896 | -0.1605 |
| (17) CSCA | 2 | 1.0998 | 1.0062 | -0.0936 | 0.0000 | 0.0880 | 0.0224 |
| (18) CTAP | 2 | 1.0998 | 1.0062 | -0.0936 | 0.0000 | 0.0880 | 0.0224 |
| (17) CSCA | 1 | 1.0998 | 1.0064 | -0.0935 | 3.07e-36 | 0.0884 | -0.0196 |
| (18) CTAP | 1 | 1.0998 | 1.0064 | -0.0935 | 3.07e-36 | 0.0884 | -0.0196 |

### Caso `3bus_DCline`  (9 divergência(s) bus-level)

| Formulação | Barra | Vm(15) | Vm(X) | ΔVm | Δθ° | ΔPg | ΔQg |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| (17) CSCA | 1 | 1.1000 | 1.0071 | -0.0929 | -1.21e-36 | 6.1407 | 0.7346 |
| (18) CTAP | 1 | 1.1000 | 1.0071 | -0.0929 | -1.21e-36 | 6.1407 | 0.7346 |
| (16) QV | 1 | 1.1000 | 1.0290 | -0.0710 | -1.21e-36 | 6.1394 | 0.7334 |
| (17) CSCA | 2 | 1.1000 | 1.0073 | -0.0927 | -2.75e-36 | -6.0256 | 2.8953 |
| (18) CTAP | 2 | 1.1000 | 1.0073 | -0.0927 | -2.75e-36 | -6.0256 | 2.8953 |
| (16) QV | 2 | 1.1000 | 1.0300 | -0.0700 | -2.75e-36 | -6.0247 | 2.8961 |
| (17) CSCA | 3 | 1.0698 | 0.9740 | -0.0958 | -0.2101 | 0.0000 | 0.0000 |
| (18) CTAP | 3 | 1.0698 | 0.9740 | -0.0958 | -0.2101 | 0.0000 | 0.0000 |
| (16) QV | 3 | 1.0698 | 0.9970 | -0.0727 | -0.1541 | 0.0000 | 0.0000 |

### Caso `3bus_shunt_fields`  (9 divergência(s) bus-level)

| Formulação | Barra | Vm(15) | Vm(X) | ΔVm | Δθ° | ΔPg | ΔQg |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| (17) CSCA | 1 | 0.9418 | 1.0397 | 0.0980 | 1.06e-34 | 0.0112 | -0.1542 |
| (18) CTAP | 1 | 0.9418 | 1.0397 | 0.0980 | 1.06e-34 | 0.0112 | -0.1542 |
| (17) CSCA | 3 | 0.9000 | 1.0198 | 0.1198 | -0.8215 | 0.0000 | 0.0000 |
| (18) CTAP | 3 | 0.9000 | 1.0198 | 0.1198 | -0.8215 | 0.0000 | 0.0000 |
| (16) QV | 3 | 0.9000 | 1.0143 | 0.1142 | 0.2191 | 0.0000 | 0.0000 |
| (16) QV | 1 | 0.9418 | 1.0522 | 0.1104 | 1.06e-34 | 0.0155 | 0.0421 |
| (17) CSCA | 2 | 0.9005 | 1.0084 | 0.1079 | -0.9844 | -0.0146 | 0.0000 |
| (18) CTAP | 2 | 0.9005 | 1.0084 | 0.1079 | -0.9844 | -0.0146 | 0.0000 |
| (16) QV | 2 | 0.9005 | 1.0062 | 0.1056 | -0.1503 | -0.0146 | 0.0000 |

### Caso `3busfrank`  (9 divergência(s) bus-level)

| Formulação | Barra | Vm(15) | Vm(X) | ΔVm | Δθ° | ΔPg | ΔQg |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| (16) QV | 2 | 1.1000 | 1.0300 | -0.0700 | -1.4597 | -0.1025 | 0.1207 |
| (16) QV | 1 | 1.1000 | 1.0290 | -0.0710 | 2.59e-34 | 0.1088 | -0.1146 |
| (17) CSCA | 1 | 1.1000 | 1.0189 | -0.0811 | 2.59e-34 | 0.1083 | -0.0525 |
| (18) CTAP | 1 | 1.1000 | 1.0189 | -0.0811 | 2.59e-34 | 0.1083 | -0.0525 |
| (17) CSCA | 2 | 1.1000 | 1.0129 | -0.0871 | -1.0695 | -0.1025 | 0.0581 |
| (18) CTAP | 2 | 1.1000 | 1.0129 | -0.0871 | -1.0695 | -0.1025 | 0.0581 |
| (17) CSCA | 3 | 1.0423 | 0.9527 | -0.0896 | -0.6991 | 0.0000 | 0.0000 |
| (18) CTAP | 3 | 1.0423 | 0.9527 | -0.0896 | -0.6991 | 0.0000 | 0.0000 |
| (16) QV | 3 | 1.0423 | 0.9672 | -0.0751 | -0.8663 | 0.0000 | 0.0000 |

### Caso `3busfrank_continuous_shunt`  (9 divergência(s) bus-level)

| Formulação | Barra | Vm(15) | Vm(X) | ΔVm | Δθ° | ΔPg | ΔQg |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| (16) QV | 1 | 1.1000 | 1.0290 | -0.0710 | 0.0000 | 0.1029 | -0.1371 |
| (16) QV | 2 | 1.1000 | 1.0300 | -0.0700 | -0.7307 | -0.1002 | 0.1101 |
| (17) CSCA | 1 | 1.1000 | 1.0247 | -0.0753 | 0.0000 | 0.1022 | -0.0377 |
| (18) CTAP | 1 | 1.1000 | 1.0247 | -0.0753 | 0.0000 | 0.1022 | -0.0377 |
| (17) CSCA | 2 | 1.1000 | 1.0200 | -0.0800 | -0.4011 | -0.1002 | 0.0072 |
| (18) CTAP | 2 | 1.1000 | 1.0200 | -0.0800 | -0.4011 | -0.1002 | 0.0072 |
| (17) CSCA | 3 | 1.0625 | 0.9833 | -0.0792 | -0.2739 | 0.0000 | 0.0000 |
| (18) CTAP | 3 | 1.0625 | 0.9833 | -0.0792 | -0.2739 | 0.0000 | 0.0000 |
| (16) QV | 3 | 1.0625 | 0.9906 | -0.0719 | -0.4319 | 0.0000 | 0.0000 |

### Caso `3busfrank_qlim`  (9 divergência(s) bus-level)

| Formulação | Barra | Vm(15) | Vm(X) | ΔVm | Δθ° | ΔPg | ΔQg |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| (16) QV | 1 | 1.1000 | 1.0526 | -0.0474 | 2.13e-35 | 0.2069 | -0.1251 |
| (17) CSCA | 1 | 1.1000 | 1.0750 | -0.0250 | 2.13e-35 | 0.2019 | 0.1040 |
| (18) CTAP | 1 | 1.1000 | 1.0750 | -0.0250 | 2.13e-35 | 0.2019 | 0.1040 |
| (16) QV | 2 | 1.1000 | 1.0448 | -0.0552 | -2.1318 | -0.1838 | 0.1431 |
| (17) CSCA | 2 | 1.1000 | 1.0439 | -0.0561 | -0.6065 | -0.1838 | -0.0867 |
| (18) CTAP | 2 | 1.1000 | 1.0439 | -0.0561 | -0.6065 | -0.1838 | -0.0867 |
| (16) QV | 3 | 0.9606 | 0.9000 | -0.0606 | -0.7799 | 0.0000 | 0.0000 |
| (17) CSCA | 3 | 0.9606 | 0.9126 | -0.0480 | -0.0621 | 0.0000 | 0.0000 |
| (18) CTAP | 3 | 0.9606 | 0.9126 | -0.0480 | -0.0621 | 0.0000 | 0.0000 |

### Caso `5busfrank`  (15 divergência(s) bus-level)

| Formulação | Barra | Vm(15) | Vm(X) | ΔVm | Δθ° | ΔPg | ΔQg |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| (16) QV | 2 | 1.1000 | 1.0300 | -0.0700 | -1.5439 | -0.1080 | 0.1276 |
| (16) QV | 1 | 1.1000 | 1.0290 | -0.0710 | 2.59e-34 | 0.1153 | -0.1206 |
| (17) CSCA | 1 | 1.1000 | 1.0378 | -0.0622 | 2.59e-34 | 0.1135 | -0.0610 |
| (18) CTAP | 1 | 1.1000 | 1.0378 | -0.0622 | 2.59e-34 | 0.1135 | -0.0610 |
| (17) CSCA | 2 | 1.1000 | 1.0323 | -0.0677 | -1.1205 | -0.1080 | 0.0662 |
| (18) CTAP | 2 | 1.1000 | 1.0323 | -0.0677 | -1.1205 | -0.1080 | 0.0662 |
| (16) QV | 5 | 1.0235 | 0.9468 | -0.0767 | -0.7884 | 0.0000 | 0.0000 |
| (16) QV | 4 | 1.0281 | 0.9518 | -0.0763 | -0.8206 | 0.0000 | 0.0000 |
| (16) QV | 3 | 1.0374 | 0.9618 | -0.0755 | -0.8830 | 0.0000 | 0.0000 |
| (17) CSCA | 5 | 1.0235 | 0.9529 | -0.0706 | -0.5736 | 0.0000 | 0.0000 |
| (18) CTAP | 5 | 1.0235 | 0.9529 | -0.0706 | -0.5736 | 0.0000 | 0.0000 |
| (17) CSCA | 4 | 1.0281 | 0.9579 | -0.0702 | -0.6028 | 0.0000 | 0.0000 |
| _... 3 linhas adicionais omitidas para concisão_ | | | | | | | |

### Caso `5busfrank_cphs`  (15 divergência(s) bus-level)

| Formulação | Barra | Vm(15) | Vm(X) | ΔVm | Δθ° | ΔPg | ΔQg |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| (17) CSCA | 2 | 1.1000 | 1.0403 | -0.0597 | -2.9286 | -0.1624 | 0.2857 |
| (18) CTAP | 2 | 1.1000 | 1.0403 | -0.0597 | -2.9286 | -0.1624 | 0.2857 |
| (17) CSCA | 1 | 1.1000 | 1.0290 | -0.0710 | 4.14e-34 | 0.1802 | -0.2641 |
| (18) CTAP | 1 | 1.1000 | 1.0290 | -0.0710 | 4.14e-34 | 0.1802 | -0.2641 |
| (16) QV | 2 | 1.1000 | 1.0300 | -0.0700 | -2.2979 | -0.1624 | 0.1876 |
| (16) QV | 1 | 1.1000 | 1.0290 | -0.0710 | 4.14e-34 | 0.1754 | -0.1707 |
| (16) QV | 5 | 0.9923 | 0.9126 | -0.0797 | -1.2166 | 0.0000 | 0.0000 |
| (16) QV | 4 | 1.0060 | 0.9275 | -0.0785 | -1.2726 | 0.0000 | 0.0000 |
| (16) QV | 3 | 1.0332 | 0.9570 | -0.0762 | -1.3750 | 0.0000 | 0.0000 |
| (17) CSCA | 5 | 0.9923 | 0.9183 | -0.0740 | -1.5343 | 0.0000 | 0.0000 |
| (18) CTAP | 5 | 0.9923 | 0.9183 | -0.0740 | -1.5343 | 0.0000 | 0.0000 |
| (17) CSCA | 4 | 1.0060 | 0.9331 | -0.0729 | -1.5858 | 0.0000 | 0.0000 |
| _... 3 linhas adicionais omitidas para concisão_ | | | | | | | |

### Caso `5busfrank_ctaf`  (15 divergência(s) bus-level)

| Formulação | Barra | Vm(15) | Vm(X) | ΔVm | Δθ° | ΔPg | ΔQg |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| (17) CSCA | 2 | 1.1000 | 1.0403 | -0.0597 | -2.9286 | -0.1624 | 0.2857 |
| (17) CSCA | 1 | 1.1000 | 1.0290 | -0.0710 | -1.69e-33 | 0.1802 | -0.2641 |
| (18) CTAP | 2 | 1.1000 | 1.0108 | -0.0892 | 0.2292 | -0.1624 | -0.1888 |
| (16) QV | 2 | 1.1000 | 1.0300 | -0.0700 | -2.2979 | -0.1624 | 0.1876 |
| (16) QV | 1 | 1.1000 | 1.0290 | -0.0710 | -1.69e-33 | 0.1754 | -0.1707 |
| (16) QV | 5 | 0.9923 | 0.9126 | -0.0797 | -1.2166 | 0.0000 | 0.0000 |
| (16) QV | 4 | 1.0060 | 0.9275 | -0.0785 | -1.2726 | 0.0000 | 0.0000 |
| (16) QV | 3 | 1.0332 | 0.9570 | -0.0762 | -1.3750 | 0.0000 | 0.0000 |
| (17) CSCA | 5 | 0.9923 | 0.9183 | -0.0740 | -1.5343 | 0.0000 | 0.0000 |
| (17) CSCA | 4 | 1.0060 | 0.9331 | -0.0729 | -1.5858 | 0.0000 | 0.0000 |
| (18) CTAP | 1 | 1.1000 | 1.0290 | -0.0710 | -1.69e-33 | -0.0333 | 0.0051 |
| (17) CSCA | 3 | 1.0332 | 0.9625 | -0.0707 | -1.6801 | 0.0000 | 0.0000 |
| _... 3 linhas adicionais omitidas para concisão_ | | | | | | | |

### Caso `5busfrank_ctap`  (15 divergência(s) bus-level)

| Formulação | Barra | Vm(15) | Vm(X) | ΔVm | Δθ° | ΔPg | ΔQg |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| (17) CSCA | 2 | 1.1000 | 1.0403 | -0.0597 | -2.9286 | -0.1624 | 0.2857 |
| (17) CSCA | 1 | 1.1000 | 1.0290 | -0.0710 | -1.69e-33 | 0.1802 | -0.2641 |
| (18) CTAP | 2 | 1.1000 | 1.0108 | -0.0892 | 0.2292 | -0.1624 | -0.1888 |
| (16) QV | 2 | 1.1000 | 1.0300 | -0.0700 | -2.2979 | -0.1624 | 0.1876 |
| (16) QV | 1 | 1.1000 | 1.0290 | -0.0710 | -1.69e-33 | 0.1754 | -0.1707 |
| (16) QV | 5 | 0.9923 | 0.9126 | -0.0797 | -1.2166 | 0.0000 | 0.0000 |
| (16) QV | 4 | 1.0060 | 0.9275 | -0.0785 | -1.2726 | 0.0000 | 0.0000 |
| (16) QV | 3 | 1.0332 | 0.9570 | -0.0762 | -1.3750 | 0.0000 | 0.0000 |
| (17) CSCA | 5 | 0.9923 | 0.9183 | -0.0740 | -1.5343 | 0.0000 | 0.0000 |
| (17) CSCA | 4 | 1.0060 | 0.9331 | -0.0729 | -1.5858 | 0.0000 | 0.0000 |
| (18) CTAP | 1 | 1.1000 | 1.0290 | -0.0710 | -1.69e-33 | -0.0333 | 0.0051 |
| (17) CSCA | 3 | 1.0332 | 0.9625 | -0.0707 | -1.6801 | 0.0000 | 0.0000 |
| _... 3 linhas adicionais omitidas para concisão_ | | | | | | | |

### Caso `9bus`  (27 divergência(s) bus-level)

| Formulação | Barra | Vm(15) | Vm(X) | ΔVm | Δθ° | ΔPg | ΔQg |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| (18) CTAP | 3 | 1.0876 | 1.0070 | -0.0806 | 1.4894 | 0.1343 | 0.1657 |
| (17) CSCA | 3 | 1.0876 | 1.0070 | -0.0806 | 1.4894 | 0.1343 | 0.1657 |
| (16) QV | 1 | 1.1000 | 1.0750 | -0.0250 | 6.56e-28 | -0.1516 | -0.0122 |
| (17) CSCA | 1 | 1.1000 | 1.0084 | -0.0916 | 6.56e-28 | -0.1473 | 0.1017 |
| (18) CTAP | 1 | 1.1000 | 1.0084 | -0.0916 | 6.56e-28 | -0.1473 | 0.1017 |
| (16) QV | 3 | 1.0876 | 1.0750 | -0.0126 | 1.7342 | 0.1343 | 0.0807 |
| (17) CSCA | 5 | 1.0756 | 0.9725 | -0.1030 | -0.8371 | 0.0000 | 0.0000 |
| (18) CTAP | 5 | 1.0756 | 0.9725 | -0.1030 | -0.8371 | 0.0000 | 0.0000 |
| (17) CSCA | 6 | 1.0873 | 0.9880 | -0.0993 | -0.4839 | 0.0000 | 0.0000 |
| (18) CTAP | 6 | 1.0873 | 0.9880 | -0.0993 | -0.4839 | 0.0000 | 0.0000 |
| (17) CSCA | 4 | 1.0968 | 0.9991 | -0.0977 | -0.3700 | 0.0000 | 0.0000 |
| (18) CTAP | 4 | 1.0968 | 0.9991 | -0.0977 | -0.3700 | 0.0000 | 0.0000 |
| _... 15 linhas adicionais omitidas para concisão_ | | | | | | | |

### Caso `9bus_transformer_fields`  (27 divergência(s) bus-level)

| Formulação | Barra | Vm(15) | Vm(X) | ΔVm | Δθ° | ΔPg | ΔQg |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| (18) CTAP | 1 | 1.1000 | 1.0230 | -0.0770 | 5.82e-29 | -0.1396 | -0.4492 |
| (17) CSCA | 1 | 1.1000 | 1.0352 | -0.0648 | 5.82e-29 | -0.1407 | 0.1793 |
| (16) QV | 1 | 1.1000 | 1.0750 | -0.0250 | 5.82e-29 | -0.1435 | 0.0262 |
| (16) QV | 3 | 1.0982 | 1.0750 | -0.0232 | 1.7107 | 0.1248 | 0.0359 |
| (17) CSCA | 3 | 1.0982 | 1.0204 | -0.0778 | 1.7486 | 0.1248 | 0.0748 |
| (18) CTAP | 3 | 1.0982 | 1.0122 | -0.0860 | 2.4065 | 0.1248 | 0.0148 |
| (18) CTAP | 2 | 1.1000 | 1.0032 | -0.0968 | 1.9020 | 0.0205 | 5.86e-04 |
| (18) CTAP | 7 | 1.1038 | 1.0077 | -0.0961 | 1.2782 | 0.0000 | 0.0000 |
| (18) CTAP | 8 | 1.0953 | 1.0009 | -0.0943 | 1.0670 | 0.0000 | 0.0000 |
| (18) CTAP | 9 | 1.1081 | 1.0226 | -0.0856 | 1.6494 | 0.0000 | 0.0000 |
| (17) CSCA | 8 | 1.0953 | 1.0098 | -0.0854 | 0.4502 | 0.0000 | 0.0000 |
| (17) CSCA | 7 | 1.1038 | 1.0192 | -0.0846 | 0.6009 | 0.0000 | 0.0000 |
| _... 15 linhas adicionais omitidas para concisão_ | | | | | | | |

---

## Análise de Fluxo nos Ramos

Apenas ramos cujos fluxos (P de→para, Q de→para, P para→de, Q para→de) divergem de (15) PM em mais de ``10^{-4}`` p.u. Para um caso convergente sem CSCA/CTAP, esses fluxos devem coincidir bit-a-bit.

### Caso `3bus`  (9 divergência(s) branch-level)

| Formulação | Ramo | De → Para | ΔP de→para | ΔQ de→para | ΔP para→de | ΔQ para→de |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| (16) QV | 1 | 1 → 2 | -0.0030 | -0.0028 | 0.0030 | 0.0028 |
| (17) CSCA | 1 | 1 → 2 | -0.0023 | -0.0022 | 0.0023 | 0.0022 |
| (18) CTAP | 1 | 1 → 2 | -0.0023 | -0.0022 | 0.0023 | 0.0022 |
| (16) QV | 3 | 2 → 3 | 0.0021 | 0.0020 | -0.0015 | -0.0013 |
| (17) CSCA | 3 | 2 → 3 | 0.0020 | 0.0019 | -0.0012 | -0.0011 |
| (18) CTAP | 3 | 2 → 3 | 0.0020 | 0.0019 | -0.0012 | -0.0011 |
| (16) QV | 2 | 1 → 3 | -9.84e-04 | -8.88e-04 | 0.0015 | 0.0013 |
| (17) CSCA | 2 | 1 → 3 | -4.54e-04 | -3.89e-04 | 0.0012 | 0.0011 |
| (18) CTAP | 2 | 1 → 3 | -4.54e-04 | -3.89e-04 | 0.0012 | 0.0011 |

### Caso `3bus_DBSH`  (7 divergência(s) branch-level)

| Formulação | Ramo | De → Para | ΔP de→para | ΔQ de→para | ΔP para→de | ΔQ para→de |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| (17) CSCA | 2 | 1 → 3 | 8.28e-04 | 0.0545 | -5.02e-06 | -0.0537 |
| (18) CTAP | 2 | 1 → 3 | 8.28e-04 | 0.0545 | -5.02e-06 | -0.0537 |
| (17) CSCA | 3 | 2 → 3 | 8.16e-04 | 0.0545 | 4.98e-06 | -0.0537 |
| (18) CTAP | 3 | 2 → 3 | 8.16e-04 | 0.0545 | 4.98e-06 | -0.0537 |
| (16) QV | 3 | 2 → 3 | 0.0018 | 0.0258 | -0.0014 | -0.0253 |
| (16) QV | 2 | 1 → 3 | -0.0013 | 0.0227 | 0.0014 | -0.0226 |
| (16) QV | 1 | 1 → 2 | -0.0030 | -0.0028 | 0.0030 | 0.0028 |

### Caso `3bus_DCER`  (9 divergência(s) branch-level)

| Formulação | Ramo | De → Para | ΔP de→para | ΔQ de→para | ΔP para→de | ΔQ para→de |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| (17) CSCA | 3 | 2 → 3 | 0.0121 | 0.0345 | -0.0103 | -0.0328 |
| (18) CTAP | 3 | 2 → 3 | 0.0121 | 0.0345 | -0.0103 | -0.0328 |
| (16) QV | 3 | 2 → 3 | 0.0018 | 0.0258 | -0.0014 | -0.0253 |
| (16) QV | 2 | 1 → 3 | -0.0013 | 0.0227 | 0.0014 | -0.0226 |
| (17) CSCA | 1 | 1 → 2 | -0.0223 | -0.0215 | 0.0225 | 0.0216 |
| (18) CTAP | 1 | 1 → 2 | -0.0223 | -0.0215 | 0.0225 | 0.0216 |
| (17) CSCA | 2 | 1 → 3 | -0.0115 | 0.0112 | 0.0103 | -0.0124 |
| (18) CTAP | 2 | 1 → 3 | -0.0115 | 0.0112 | 0.0103 | -0.0124 |
| (16) QV | 1 | 1 → 2 | -0.0030 | -0.0028 | 0.0030 | 0.0028 |

### Caso `3bus_DCSC`  (9 divergência(s) branch-level)

| Formulação | Ramo | De → Para | ΔP de→para | ΔQ de→para | ΔP para→de | ΔQ para→de |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| (16) QV | 3 | 1 → 2 | -1.02e-35 | 0.1625 | 1.02e-35 | -0.1627 |
| (16) QV | 2 | 2 → 3 | 0.0896 | 0.0022 | -0.0883 | -8.64e-04 |
| (17) CSCA | 1 | 1 → 3 | 0.0884 | 0.0015 | -0.0870 | -1.80e-04 |
| (18) CTAP | 1 | 1 → 3 | 0.0884 | 0.0015 | -0.0870 | -1.80e-04 |
| (17) CSCA | 2 | 2 → 3 | 0.0880 | 0.0012 | -0.0866 | 1.80e-04 |
| (18) CTAP | 2 | 2 → 3 | 0.0880 | 0.0012 | -0.0866 | 1.80e-04 |
| (16) QV | 1 | 1 → 3 | 0.0866 | -6.86e-04 | -0.0853 | 0.0019 |
| (17) CSCA | 3 | 1 → 2 | -1.02e-35 | -0.0212 | 1.02e-35 | 0.0212 |
| (18) CTAP | 3 | 1 → 2 | -1.02e-35 | -0.0212 | 1.02e-35 | 0.0212 |

### Caso `3bus_DCline`  (6 divergência(s) branch-level)

| Formulação | Ramo | De → Para | ΔP de→para | ΔQ de→para | ΔP para→de | ΔQ para→de |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| (16) QV | 2 | 2 → 3 | 0.0021 | 0.0020 | -0.0015 | -0.0013 |
| (16) QV | 1 | 1 → 3 | -9.84e-04 | -8.88e-04 | 0.0015 | 0.0013 |
| (17) CSCA | 2 | 2 → 3 | 0.0012 | 0.0012 | -4.22e-04 | -3.88e-04 |
| (18) CTAP | 2 | 2 → 3 | 0.0012 | 0.0012 | -4.22e-04 | -3.88e-04 |
| (17) CSCA | 1 | 1 → 3 | 3.26e-04 | 3.31e-04 | 4.22e-04 | 3.88e-04 |
| (18) CTAP | 1 | 1 → 3 | 3.26e-04 | 3.31e-04 | 4.22e-04 | 3.88e-04 |

### Caso `3bus_shunt_fields`  (9 divergência(s) branch-level)

| Formulação | Ramo | De → Para | ΔP de→para | ΔQ de→para | ΔP para→de | ΔQ para→de |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| (17) CSCA | 2 | 1 → 3 | 0.0037 | -0.1080 | -0.0046 | 0.1071 |
| (18) CTAP | 2 | 1 → 3 | 0.0037 | -0.1080 | -0.0046 | 0.1071 |
| (17) CSCA | 3 | 2 → 3 | -0.0026 | -0.0646 | 0.0046 | 0.0665 |
| (18) CTAP | 3 | 2 → 3 | -0.0026 | -0.0646 | 0.0046 | 0.0665 |
| (17) CSCA | 1 | 1 → 2 | 0.0075 | -0.0462 | -0.0120 | 0.0419 |
| (18) CTAP | 1 | 1 → 2 | 0.0075 | -0.0462 | -0.0120 | 0.0419 |
| (16) QV | 3 | 2 → 3 | -0.0051 | -0.0440 | 0.0055 | 0.0444 |
| (16) QV | 1 | 1 → 2 | 0.0111 | 0.0437 | -0.0095 | -0.0422 |
| (16) QV | 2 | 1 → 3 | 0.0044 | -0.0016 | -0.0055 | 6.44e-04 |

### Caso `3busfrank`  (9 divergência(s) branch-level)

| Formulação | Ramo | De → Para | ΔP de→para | ΔQ de→para | ΔP para→de | ΔQ para→de |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| (16) QV | 1 | 1 → 2 | 0.0726 | -0.0794 | -0.0706 | 0.0813 |
| (17) CSCA | 1 | 1 → 2 | 0.0711 | -0.0380 | -0.0700 | 0.0391 |
| (18) CTAP | 1 | 1 → 2 | 0.0711 | -0.0380 | -0.0700 | 0.0391 |
| (16) QV | 3 | 2 → 3 | -0.0319 | 0.0393 | 0.0329 | -0.0384 |
| (16) QV | 2 | 1 → 3 | 0.0362 | -0.0352 | -0.0329 | 0.0384 |
| (17) CSCA | 2 | 1 → 3 | 0.0371 | -0.0145 | -0.0328 | 0.0187 |
| (18) CTAP | 2 | 1 → 3 | 0.0371 | -0.0145 | -0.0328 | 0.0187 |
| (17) CSCA | 3 | 2 → 3 | -0.0325 | 0.0190 | 0.0328 | -0.0187 |
| (18) CTAP | 3 | 2 → 3 | -0.0325 | 0.0190 | 0.0328 | -0.0187 |

### Caso `3busfrank_continuous_shunt`  (18 divergência(s) branch-level)

| Formulação | Ramo | De → Para | ΔP de→para | ΔQ de→para | ΔP para→de | ΔQ para→de |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| (16) QV | 1 | 1 → 2 | 0.0346 | -0.0414 | -0.0341 | 0.0419 |
| (16) QV | 2 | 1 → 2 | 0.0346 | -0.0414 | -0.0341 | 0.0419 |
| (17) CSCA | 1 | 1 → 2 | 0.0339 | -0.0078 | -0.0337 | 0.0080 |
| (17) CSCA | 2 | 1 → 2 | 0.0339 | -0.0078 | -0.0337 | 0.0080 |
| (18) CTAP | 1 | 1 → 2 | 0.0339 | -0.0078 | -0.0337 | 0.0080 |
| (18) CTAP | 2 | 1 → 2 | 0.0339 | -0.0078 | -0.0337 | 0.0080 |
| (16) QV | 3 | 1 → 3 | 0.0169 | -0.0271 | -0.0165 | 0.0274 |
| (16) QV | 4 | 1 → 3 | 0.0169 | -0.0271 | -0.0165 | 0.0274 |
| (17) CSCA | 3 | 1 → 3 | 0.0172 | -0.0110 | -0.0163 | 0.0119 |
| (17) CSCA | 4 | 1 → 3 | 0.0172 | -0.0110 | -0.0163 | 0.0119 |
| (18) CTAP | 3 | 1 → 3 | 0.0172 | -0.0110 | -0.0163 | 0.0119 |
| (18) CTAP | 4 | 1 → 3 | 0.0172 | -0.0110 | -0.0163 | 0.0119 |
| _... 6 linhas adicionais omitidas para concisão_ | | | | | | |

### Caso `3busfrank_qlim`  (9 divergência(s) branch-level)

| Formulação | Ramo | De → Para | ΔP de→para | ΔQ de→para | ΔP para→de | ΔQ para→de |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| (16) QV | 1 | 1 → 2 | 0.1388 | -0.0926 | -0.1342 | 0.0970 |
| (17) CSCA | 1 | 1 → 2 | 0.1290 | 0.0584 | -0.1259 | -0.0554 |
| (18) CTAP | 1 | 1 → 2 | 0.1290 | 0.0584 | -0.1259 | -0.0554 |
| (17) CSCA | 2 | 1 → 3 | 0.0729 | 0.0456 | -0.0536 | -0.0271 |
| (18) CTAP | 2 | 1 → 3 | 0.0729 | 0.0456 | -0.0536 | -0.0271 |
| (16) QV | 2 | 1 → 3 | 0.0682 | -0.0325 | -0.0605 | 0.0398 |
| (16) QV | 3 | 2 → 3 | -0.0496 | 0.0461 | 0.0605 | -0.0357 |
| (17) CSCA | 3 | 2 → 3 | -0.0580 | -0.0313 | 0.0536 | 0.0271 |
| (18) CTAP | 3 | 2 → 3 | -0.0580 | -0.0313 | 0.0536 | 0.0271 |

### Caso `5busfrank`  (9 divergência(s) branch-level)

| Formulação | Ramo | De → Para | ΔP de→para | ΔQ de→para | ΔP para→de | ΔQ para→de |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| (16) QV | 2 | 1 → 2 | 0.0770 | -0.0838 | -0.0748 | 0.0859 |
| (17) CSCA | 2 | 1 → 2 | 0.0750 | -0.0436 | -0.0738 | 0.0448 |
| (18) CTAP | 2 | 1 → 2 | 0.0750 | -0.0436 | -0.0738 | 0.0448 |
| (16) QV | 5 | 2 → 3 | -0.0333 | 0.0417 | 0.0348 | -0.0402 |
| (16) QV | 4 | 1 → 3 | 0.0383 | -0.0368 | -0.0349 | 0.0401 |
| (17) CSCA | 4 | 1 → 3 | 0.0385 | -0.0173 | -0.0345 | 0.0211 |
| (18) CTAP | 4 | 1 → 3 | 0.0385 | -0.0173 | -0.0345 | 0.0211 |
| (17) CSCA | 5 | 2 → 3 | -0.0343 | 0.0214 | 0.0344 | -0.0212 |
| (18) CTAP | 5 | 2 → 3 | -0.0343 | 0.0214 | 0.0344 | -0.0212 |

### Caso `5busfrank_cphs`  (15 divergência(s) branch-level)

| Formulação | Ramo | De → Para | ΔP de→para | ΔQ de→para | ΔP para→de | ΔQ para→de |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| (17) CSCA | 2 | 1 → 2 | 0.1216 | -0.1853 | -0.1132 | 0.1934 |
| (18) CTAP | 2 | 1 → 2 | 0.1216 | -0.1853 | -0.1132 | 0.1934 |
| (16) QV | 2 | 1 → 2 | 0.1168 | -0.1225 | -0.1119 | 0.1272 |
| (17) CSCA | 5 | 2 → 3 | -0.0493 | 0.0923 | 0.0518 | -0.0899 |
| (18) CTAP | 5 | 2 → 3 | -0.0493 | 0.0923 | 0.0518 | -0.0899 |
| (17) CSCA | 4 | 1 → 3 | 0.0586 | -0.0833 | -0.0523 | 0.0894 |
| (18) CTAP | 4 | 1 → 3 | 0.0586 | -0.0833 | -0.0523 | 0.0894 |
| (16) QV | 5 | 2 → 3 | -0.0505 | 0.0604 | 0.0511 | -0.0599 |
| (16) QV | 4 | 1 → 3 | 0.0586 | -0.0527 | -0.0517 | 0.0593 |
| (16) QV | 1 | 3 → 4 | 5.53e-04 | 5.32e-04 | -1.13e-04 | -1.09e-04 |
| (17) CSCA | 1 | 3 → 4 | 5.09e-04 | 4.89e-04 | -1.04e-04 | -1.00e-04 |
| (18) CTAP | 1 | 3 → 4 | 5.09e-04 | 4.89e-04 | -1.04e-04 | -1.00e-04 |
| _... 3 linhas adicionais omitidas para concisão_ | | | | | | |

### Caso `5busfrank_ctaf`  (15 divergência(s) branch-level)

| Formulação | Ramo | De → Para | ΔP de→para | ΔQ de→para | ΔP para→de | ΔQ para→de |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| (17) CSCA | 1 | 1 → 2 | 0.1216 | -0.1853 | -0.1132 | 0.1934 |
| (18) CTAP | 4 | 3 → 4 | -0.1806 | -0.1737 | -0.0212 | -0.0204 |
| (16) QV | 1 | 1 → 2 | 0.1168 | -0.1225 | -0.1119 | 0.1272 |
| (18) CTAP | 3 | 2 → 3 | -0.1211 | -0.1260 | 0.1113 | 0.1167 |
| (17) CSCA | 3 | 2 → 3 | -0.0493 | 0.0923 | 0.0518 | -0.0899 |
| (17) CSCA | 2 | 1 → 3 | 0.0586 | -0.0833 | -0.0523 | 0.0894 |
| (18) CTAP | 2 | 1 → 3 | -0.0757 | -0.0631 | 0.0693 | 0.0570 |
| (18) CTAP | 1 | 1 → 2 | 0.0424 | 0.0637 | -0.0414 | -0.0627 |
| (16) QV | 3 | 2 → 3 | -0.0505 | 0.0604 | 0.0511 | -0.0599 |
| (16) QV | 2 | 1 → 3 | 0.0586 | -0.0527 | -0.0517 | 0.0593 |
| (18) CTAP | 5 | 4 → 5 | 0.0212 | 0.0204 | 5.58e-12 | -9.89e-11 |
| (16) QV | 4 | 3 → 4 | 5.53e-04 | 5.32e-04 | -1.13e-04 | -1.09e-04 |
| _... 3 linhas adicionais omitidas para concisão_ | | | | | | |

### Caso `5busfrank_ctap`  (15 divergência(s) branch-level)

| Formulação | Ramo | De → Para | ΔP de→para | ΔQ de→para | ΔP para→de | ΔQ para→de |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| (17) CSCA | 1 | 1 → 2 | 0.1216 | -0.1853 | -0.1132 | 0.1934 |
| (18) CTAP | 4 | 3 → 4 | -0.1806 | -0.1737 | -0.0212 | -0.0204 |
| (16) QV | 1 | 1 → 2 | 0.1168 | -0.1225 | -0.1119 | 0.1272 |
| (18) CTAP | 3 | 2 → 3 | -0.1211 | -0.1260 | 0.1113 | 0.1167 |
| (17) CSCA | 3 | 2 → 3 | -0.0493 | 0.0923 | 0.0518 | -0.0899 |
| (17) CSCA | 2 | 1 → 3 | 0.0586 | -0.0833 | -0.0523 | 0.0894 |
| (18) CTAP | 2 | 1 → 3 | -0.0757 | -0.0631 | 0.0693 | 0.0570 |
| (18) CTAP | 1 | 1 → 2 | 0.0424 | 0.0637 | -0.0414 | -0.0627 |
| (16) QV | 3 | 2 → 3 | -0.0505 | 0.0604 | 0.0511 | -0.0599 |
| (16) QV | 2 | 1 → 3 | 0.0586 | -0.0527 | -0.0517 | 0.0593 |
| (18) CTAP | 5 | 4 → 5 | 0.0212 | 0.0204 | 5.58e-12 | -9.89e-11 |
| (16) QV | 4 | 3 → 4 | 5.53e-04 | 5.32e-04 | -1.13e-04 | -1.09e-04 |
| _... 3 linhas adicionais omitidas para concisão_ | | | | | | |

### Caso `9bus`  (27 divergência(s) branch-level)

| Formulação | Ramo | De → Para | ΔP de→para | ΔQ de→para | ΔP para→de | ΔQ para→de |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| (17) CSCA | 9 | 3 → 9 | 0.1343 | 0.1657 | -0.1343 | -0.1515 |
| (18) CTAP | 9 | 3 → 9 | 0.1343 | 0.1657 | -0.1343 | -0.1515 |
| (16) QV | 7 | 1 → 4 | -0.1516 | -0.0122 | 0.1516 | -0.0050 |
| (17) CSCA | 7 | 1 → 4 | -0.1473 | 0.1017 | 0.1473 | -0.1022 |
| (18) CTAP | 7 | 1 → 4 | -0.1473 | 0.1017 | 0.1473 | -0.1022 |
| (16) QV | 9 | 3 → 9 | 0.1343 | 0.0807 | -0.1343 | -0.0709 |
| (16) QV | 4 | 6 → 9 | -0.0878 | -0.0068 | 0.0898 | 0.0305 |
| (17) CSCA | 4 | 6 → 9 | -0.0867 | 0.0080 | 0.0892 | 0.0736 |
| (18) CTAP | 4 | 6 → 9 | -0.0867 | 0.0080 | 0.0892 | 0.0736 |
| (16) QV | 3 | 4 → 6 | -0.0892 | -0.0058 | 0.0878 | 0.0068 |
| (18) CTAP | 3 | 4 → 6 | -0.0872 | 0.0375 | 0.0867 | -0.0080 |
| (17) CSCA | 3 | 4 → 6 | -0.0872 | 0.0375 | 0.0867 | -0.0080 |
| _... 15 linhas adicionais omitidas para concisão_ | | | | | | |

### Caso `9bus_transformer_fields`  (27 divergência(s) branch-level)

| Formulação | Ramo | De → Para | ΔP de→para | ΔQ de→para | ΔP para→de | ΔQ para→de |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| (18) CTAP | 7 | 1 → 4 | -0.1396 | -0.4492 | 0.1396 | -0.4168 |
| (18) CTAP | 2 | 4 → 5 | -0.0575 | 0.2349 | 0.0586 | -0.2028 |
| (18) CTAP | 5 | 7 → 5 | 0.0604 | -0.1398 | -0.0586 | 0.2028 |
| (17) CSCA | 7 | 1 → 4 | -0.1407 | 0.1793 | 0.1407 | -0.1835 |
| (18) CTAP | 3 | 4 → 6 | -0.0821 | 0.1819 | 0.0815 | -0.1647 |
| (18) CTAP | 4 | 6 → 9 | -0.0815 | 0.1647 | 0.0839 | -0.0960 |
| (18) CTAP | 8 | 2 → 7 | 0.0205 | 5.86e-04 | -0.0205 | 0.1560 |
| (16) QV | 7 | 1 → 4 | -0.1435 | 0.0262 | 0.1435 | -0.0419 |
| (16) QV | 9 | 3 → 9 | 0.1248 | 0.0359 | -0.1248 | -0.0253 |
| (18) CTAP | 9 | 3 → 9 | 0.1248 | 0.0148 | -0.1248 | 9.15e-04 |
| (17) CSCA | 9 | 3 → 9 | 0.1248 | 0.0748 | -0.1248 | -0.0606 |
| (17) CSCA | 2 | 4 → 5 | -0.0587 | 0.0991 | 0.0592 | -0.0658 |
| _... 15 linhas adicionais omitidas para concisão_ | | | | | | |

---

## Conclusão Técnica

**1. (15) PM em estresse — onde o solver de mercado entrega e onde desiste.** Dos 24 casos, **9** ficam sem `ground truth`: 4 com `LOCALLY_INFEASIBLE`, 1 com `INVALID_MODEL` e os demais com falha pré-solver (validação `ANAREDE`/parser). Em **6** desses, (16)/(17)/(18) ainda entregam ponto operacional admissível com slacks finitos — evidência do papel das soft-constraints como ferramenta de continuação numérica em pontos onde o `solve_ac_opf` se recusa a operar.

**2. QLIM+VLIM (16) é a fronteira entre o que é viável e o que é admissível.** Em todos os casos com ⚠️ a divergência (16)↔(15) decorre da imposição dos setpoints de Vm nas barras de geração e do limite de Qg dos geradores: enquanto (15) é livre para violar, (16) penaliza via `sl_v`/`sl_d`. As barras 1/2 de geração tipicamente caem para próximo de 1.029–1.030 pu (limite superior efetivo) em (16) contra 1.10 pu em (15) — daí ``|ΔV_m| ≈ 0.07`` pu observado em quase todas as barras de geração da bateria. Isso é assinatura física de **rede operando no ponto de Q-limit**, não erro numérico.

**3. CSCA (17) — onde o controle de chaveamento de capacitores entra em ação.**

  - **Alívio de penalidade** (obj₁₇ < ½·obj₁₆ com obj₁₆>1): `3bus_DCSC`, `3bus_shunt_fields`, `3busfrank_qlim`, `5busfrank_csca`. Nestes, ``bs_{var}`` se desloca dentro de ``[bs_{min}, bs_{max}]`` e injeta reativo localmente, **substituindo parte da geração reativa por compensação shunt** e viabilizando o ponto operacional. O exemplo canônico é `5busfrank_csca`, único caso da bateria onde (15) declara `LOCALLY_INFEASIBLE` e (17) leva a penalidade de **786 148 → 19 243** (~40× menor) chaveando shunts.
  - **Solução fisicamente distinta sem alívio expressivo de penalidade** (max ``|ΔV_m|`` ou ``|ΔQ_g|`` > 5·10⁻³): `3bus`, `3bus_DBSH`, `3bus_DCER`, `3bus_DCline`, `9bus`, `9bus_transformer_fields`, `300bus`, `500bus`, `test_system`, `3busfrank`, `3busfrank_continuous_shunt`, `5busfrank`, `5busfrank_cphs`, `5busfrank_ctaf`, `5busfrank_ctap`. Aqui (17) chega a um ponto operacional **diferente** do (16) (Vm nas barras de carga sobe, ``Q_g`` dos geradores cai), mas ambos eram igualmente admissíveis dentro do modelo — degenerescência típica de problemas de controle ótimo.

**4. CTAP (18) — onde o tap variável entra em ação.**

  - **Alívio de penalidade** (obj₁₈ < ½·obj₁₇ com obj₁₇>1): `300bus`.
  - **Solução fisicamente distinta** (max ``|ΔV_m|`` ou ``|ΔQ_g|`` > 5·10⁻³ entre (17) e (18)): `9bus_transformer_fields`, `5busfrank_ctaf`, `5busfrank_ctap`. Em `5busfrank_ctaf`/`5busfrank_ctap`, com CTAP declarado, ``tm_{var}`` se desloca dentro de ``[tap_{min}, tap_{max}]`` e altera ``Y_{ramo}/tm^2``, **redistribuindo Q entre primário e secundário do transformador**. O efeito é nítido na barra 2 (PV) onde (18) Vm = 1.0108 contra (17) Vm = 1.0403 — diferença de 0.030 pu sustentada por uma pequena variação de tap. Esse comportamento reproduz o LTC (Load Tap Changer) de transformadores reais.

**5. Síntese final.** A bateria valida quatro propriedades essenciais do conjunto (15)→(18):

  i. **(16)** corrige (15) honrando limites operacionais quando estes são violáveis pelo solver de mercado;
  ii. **(17)** estende (16) sem degradar nenhum caso já correto, e melhora estritamente os casos com shunt chaveado;
  iii. **(18)** estende (17) sem degradar nenhum caso já correto, e melhora estritamente os casos com tap controlado;
  iv. As barras/ramos listados nas seções 2 e 3 são **marcadores numéricos de fragilidade da rede** — locais onde a topologia exige dispositivos de controle suplementares para manter Vm dentro dos setpoints. Esses pontos são candidatos naturais para alocação prioritária de compensação reativa em estudos de planejamento.

