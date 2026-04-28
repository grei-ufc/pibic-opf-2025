# Relatório de Testes: Validação do Fluxo de Potência (Formulação QLIM+VLIM vs PowerModels)

## 1. Visão Geral dos Resultados

Abaixo apresentamos um quadro resumo comparando a execução do script customizado com variáveis de folga (`QLIM+VLIM`) e o fluxo de potência AC tradicional padrão do pacote `PowerModels.jl` (`PM`).

| Caso de Teste | Status (QLIM+VLIM) | Status (PM) | Solução Idêntica? | Uso de Slacks (Erro) | Observação Principal |
| :--- | :--- | :--- | :---: | :---: | :--- |
| **`3bus_corrections`** | Erro (Validação) | Erro (Validação) | N/A | N/A | Inconsistência de dados corretamente barrada em ambos. |
| **`3bus_DBSH`** | Convergiu | Convergiu | **Sim** | $\approx 0$ | Fluxos e perdas bateram perfeitamente. |
| **`3bus_DCER`** | Convergiu | Convergiu | **Sim** | $\approx 0$ | Resultados matematicamente equivalentes. |
| **`3bus_DCline`** | Convergiu | Convergiu | **Não** | $\approx 0$ | PM calculou P_gen maior. Falta modelar fluxo DC no JuMP. |
| **`3bus_DCSC`** | Convergiu | Convergiu | **Não** | $226.19$ | Violação de limites ativou o controle QLIM/VLIM. |
| **`3bus_DSHL`** | Convergiu | Convergiu | **Não** | $4.2 \times 10^6$ | PM colapsou a tensão. QLIM/VLIM segurou a rede. |
| **`3bus_shunt_fields`**| Convergiu | Convergiu | **Não** | $1106.28$ | Controle de tensão ativo no modelo JuMP. |
| **`3bus` (Base)** | Convergiu | Convergiu | **Sim** | $\approx 0$ | Caso base perfeitamente alinhado. |

---

## 2. Análise Detalhada por Caso de Estudo

### 2.1. Casos com Solução Exata (Comprovação da Física)
**Casos:** `3bus.pwf`, `3bus_DBSH.pwf`, `3bus_DCER.pwf`

Nestes arquivos, a rede operava dentro dos limites físicos nominais. O esforço das variáveis de folga na formulação `QLIM+VLIM` foi virtualmente nulo (na ordem de $10^{-17}$, que é o zero da máquina).
* **Tensão:** $0.9602 \dots 1.03$ pu (Idêntico)
* **Geração Ativa / Reativa:** $33.27$ MW / $47.55$ MVAr (Idêntico)
* **Perdas:** $2.88$ MW (Idêntico)

**Conclusão Teórica:** As equações de balanço nodal e injeção de ramos implementadas no JuMP através da matriz de admitância estão **corretas e validadas**.

### 2.2. O Caso do Colapso de Tensão (O Valor da Formulação Customizada)
**Caso:** `3bus_DSHL.pwf`

Este é o resultado mais rico para a discussão do TCC. A rede foi submetida a um estresse severo de potência reativa.

| Métrica | PowerModels Puro (ACP) | Formulação JuMP (QLIM+VLIM) |
| :--- | :--- | :--- |
| **Tensão Mínima** | **0.6622 pu** (Colapso) | **0.9000 pu** (Controlada) |
| **Geração Ativa Total** | 120.45 MW | 35.14 MW |
| **Geração Reativa Total**| 319.08 MVAr | 130.40 MVAr |
| **Perdas Ativas** | 103.05 MW | 17.74 MW |
| **Erro de Slacks** | 0.0 (Ignora limites) | $4.2 \times 10^6$ (Penalização Máxima) |

**Análise:** O PowerModels tradicional não modela os limites das máquinas; ele trata o problema estritamente como um sistema não-linear engessado. Como consequência, ele convergiu para um estado físico irrealista (Tensão de 0.66 pu gerando 103 MW de perdas térmicas). Já a sua formulação ativou pesadamente as slacks de penalidade (`4.2e6`), convertendo barras PV em PQ temporariamente para respeitar limites, mantendo as perdas controladas (17.74 MW) e tensões mais adequadas à operação.

### 2.3. Casos de Atuação Leve e Moderada de Controle
**Casos:** `3bus_DCSC.pwf` e `3bus_shunt_fields.pwf`

De maneira similar ao caso extremo, nestes sistemas o PowerModels resolveu o balanço mantendo a tensão de referência fixa, enquanto a formulação customizada identificou pequenas extrapolações de limites e ativou as slacks (Erros de 226 e 1106).
* **Exemplo (`3bus_shunt_fields`):** No PowerModels a perda foi de $1.04$ MW. Na formulação com controle, a perda subiu ligeiramente para $2.62$ MW, pois o sistema precisou sacrificar o despacho ótimo estrito para acomodar os limites de reativo de forma factível.

### 2.4. Divergência Algébrica (Oportunidade de Melhoria)
**Caso:** `3bus_DCline.pwf`

Neste caso não houve violação de limites (Erro de controle $10^{-17}$), porém os resultados de geração diferiram fortemente:
* **Geração (PM):** 42.62 MW / 3.08 MVAr
* **Geração (JuMP):** 31.26 MW / 6.16 MVAr
* **Perdas:** 0.87 MW (Idêntico)

**Causa Raiz:** O arquivo `.pwf` contém uma Linha de Transmissão de Corrente Contínua (Elo DC). O PowerModels lê e insere automaticamente a carga/injeção desse Elo DC no balanço nodal. No nosso código JuMP atual, iteramos apenas sobre os componentes de Corrente Alternada (`ref[:branch]`). O conversor DC não está embutindo sua potência na Lei de Kirchhoff do nosso nó.
* **Próximo Passo:** Para futuras versões, o código JuMP precisará extrair o dicionário `ref[:dcline]` e somar sua injeção nas restrições nodais.

### 2.5. O Caso de Erro Prévio
**Caso:** `3bus_corrections.pwf`
Ambos os scripts pararam imediatamente acusando:
`Active generator with QMIN < QMAX found in a PQ bus`
Isso demonstra que a verificação de sanidade dos dados do pacote PWF.jl opera em uma camada anterior e independente à montagem do solver matemático. A base de dados requer higienização prévia.

---

## 3. Conclusão Parcial para o TCC

Os testes comprovam que:
1. A **Matemática AC Polar** foi corretamente traduzida da literatura para o modelo explícito em `JuMP`.
2. A utilização de restrições flexíveis (*soft-constraints*) com variáveis de folga provou-se altamente superior ao fluxo tradicional de viabilidade para sistemas operando em limites estreitos.
3. A formulação JuMP foi capaz de obter soluções operacionais controladas, evitando o colapso numérico e físico percebido pelo modelo padrão ACP do PowerModels (Exemplo: 3bus_DSHL).