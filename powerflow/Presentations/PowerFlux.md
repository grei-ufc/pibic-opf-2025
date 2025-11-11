---
marp: true
theme: gaia
class:
  - lead
paginate: true
---

# Fluxo de Potência

Revisão Conceitual para Pesquisa em Otimização

---

## 1. O Que é Análise de Fluxo de Potência?

A Análise de Fluxo de Potência (ou Fluxo de Carga) é a ferramenta fundamental para descrever o estado operacional de um sistema elétrico.

- **Objetivo Principal:** Dada a geração e o consumo, o método determina as **tensões** (magnitude e ângulo) em todas as barras (nós) do sistema.
- **Resultados Secundários:** Com as tensões conhecidas, as correntes em cada linha de transmissão são facilmente calculadas.
- **Aplicação:** Essencial para entender como a energia flui em redes complexas e malhadas, como as de transmissão.

---

## 2. O Problema Central: A Não Linearidade

O maior desafio da análise de fluxo de potência é a natureza não linear das equações de potência.

- As equações que relacionam potência com tensão são quadráticas.
  Exemplo: $S = I^*IZ$ ou $S = \frac{VV^*}{Z}$.
- **Consequência:** Não existe uma solução analítica ou de forma fechada para o problema.
- A solução precisa ser encontrada numericamente por meio de métodos de **aproximações sucessivas (iteração)**.

---

## 3. Modelagem do Sistema: (Buses)

Para a análise, o sistema é abstraído em um modelo matemático.

- **Buses de Carga (P,Q):**
    - Potência ativa (P) e reativa (Q) consumidas são **conhecidas**.
    - Tensão (V) e ângulo (θ) são **desconhecidos**.
- **Buses de Geração (P,V):**
    - Potência ativa (P) injetada e magnitude da tensão (V) são **conhecidas**.
    - Potência reativa (Q) e ângulo (θ) são **desconhecidos**.

---

## 3. Modelagem do Sistema: (Buses)

- **Buses de Referência (Slack/Swing):**
    - Compensa as perdas do sistema, que não são conhecidas a priori.
    - Magnitude da tensão (V) e ângulo (θ, tipicamente $0^\circ$) são **conhecidos**.
    - Potência ativa (P) e reativa (Q) são **desconhecidas**.

---

## 4. Métodos de Solução Numérica

O processo inicia-se com uma estimativa ("partida plana") e ajusta as variáveis iterativamente para minimizar o "mismatch" de potência.

- **Método de Newton-Raphson:** O mais popular, pois tende a convergir rapidamente.
- Utiliza a **matriz Jacobiana (J)**, que contém as derivadas parciais do sistema, para encontrar a correção a cada passo.
- Equação de atualização:
  $$ \Delta \mathbf{x} = -\mathbf{J}^{-1}\mathbf{f}(\mathbf{x}) $$
 

---

## 5. Otimização do Fluxo de Potência

- **Objetivo:** Encontrar a configuração operacional que otimiza uma **função objetivo**, respeitando os limites físicos e operacionais do sistema.
- **Funções Objetivo Comuns:**
    - Minimização do custo total de geração.
    - Minimização das perdas de transmissão.
    - Otimização da segurança e resiliência do sistema.
- A "otimalidade" é subjetiva e depende da definição da função objetivo. O resultado do OPF é uma **informação de assessoria** para a tomada de decisão.

---

## 6. Simplificações para Otimização

O OPF é computacionalmente intensivo. Aproximações são usadas para torná-lo viável.

<div>

### Fluxo Desacoplado

Baseia-se na forte relação P-θ e Q-V para simplificar a matriz Jacobiana (assumindo que $\frac{\partial P}{\partial V}$ e $\frac{\partial Q}{\partial \theta}$ são desprezíveis), tornando a solução mais rápida.

</div>

---

## 6. Simplificações para Otimização

### Fluxo de Potência "DC"

É uma aproximação **linear** que ignora perdas, reativos e assume V=1.0 p.u..
- **Não requer iteração**, sendo extremamente rápido.
- Equação fundamental:
  $P_{ik} \approx \frac{1}{x_{ik}}(\theta_i - \theta_k)$
- Ideal para análise de contingências e OPF em larga escala.

</div>

---

## 7. Conclusão

- A Análise de Fluxo de Potência é a base para a operação e o planejamento de sistemas de potência.
- O OPF utiliza essa análise para encontrar estados operacionais ótimos, mas é computacionalmente intensivo.
- Aproximações como o Fluxo de Potência DC são cruciais para tornar o OPF tratável em problemas reais, fornecendo uma visão geral rápida e adequada.

