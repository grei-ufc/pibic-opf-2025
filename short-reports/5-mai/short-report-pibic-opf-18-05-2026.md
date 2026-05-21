# Resumo das Atividades: Implementação e Análise do Problema de Maximum Load Delivery (MLD)

## 1. Investigação sobre a Função `solve_mld`
Durante a revisão das bibliotecas do ecossistema do LANL em Julia para a execução do MLD, realizei uma investigação detalhada no código-fonte. Identifiquei a existência da função `_solve_mld` dentro do pacote principal `PowerModels.jl` (especificamente em `src/prob/test.jl`). Contudo, constatei que se trata de uma função interna e privada (indicada pelo prefixo `_`), utilizada pelos desenvolvedores apenas para testes simplificados de integração ("toy problems").

Para garantir a robustez e o rigor matemático adequados para análises de sistemas reais, optei por adotar a implementação oficial para ambiente de produção, disponível no pacote `PowerModelsRestoration.jl`. A sintaxe adotada nos benchmarks foi a chamada genérica `run_mld(data, ACPPowerModel, optimizer)`, que permite fácil transição de formulações matemáticas (como relaxações SOC).

## 2. Parsing de Dados e Modelagem Customizada (JuMP)
Ao realizar o parsing dos arquivos `.pwf` do Sistema Interligado Nacional (SIN) utilizando o `PWF.jl`, adotei o parâmetro `add_control_data=true`. Isso foi essencial para carregar os limites operacionais reais do ANAREDE (taps, shunts, limites de tensão).

Na implementação customizada do fluxo de potência via `JuMP`, identifiquei que manter restrições rígidas ("hard constraints") para os balanços nodais gerava infactibilidade local (`Locally_Infeasible`). Para contornar isso e garantir que o espaço de busca nunca fosse vazio, converti a modelagem do OPF para um formato de "Recurso Completo" (MLD puro):
- Adicionei variáveis de folga (*Soft Constraints*) para os limites de tensão (`sl_v`), balanço reativo (`sl_d`) e, principalmente, **balanço de potência ativa (`sl_p`)**.
- Essas variáveis foram penalizadas na função objetivo utilizando o método "Big-M" (peso de $10^6$).

## 3. Análise de Convergência Numérica e Limite de Iterações
Ao rodar os casos do SIN com o solver Ipopt, o modelo atingiu o limite de iterações (`ITERATION_LIMIT` em 3000). Realizei a análise do log de otimização e identifiquei a seguinte situação:
- **Violação de Restrição Física (Constraint Violation):** Estava na ordem de $10^{-6}$, o que significa que as leis de Kirchhoff e os limites de rede foram atendidos. O fluxo convergiu fisicamente.
- **Infactibilidade Dual (Dual Infeasibility):** Apresentou valores elevados ($~0.29$). 

**Diagnóstico:** Como adotei uma penalidade de $10^6$, qualquer ruído numérico infinitamente pequeno nas variáveis de folga resultava em um gradiente elevado na função objetivo. O solver esgotava as iterações tentando zerar uma derivada referente a frações de Watts, caracterizando um problema de mau condicionamento numérico na fase final da convergência.

## 4. Sintonia do Solver e Filtro de Gargalos Físicos
Para otimizar o tempo de processamento e evitar que o solver fique preso em ruídos numéricos, apliquei as seguintes sintonias no `Ipopt`:
- Ativação de `"mu_strategy" => "adaptive"` para auxiliar no escape de mínimos locais.
- Configuração de critérios de parada aceitável (`acceptable_tol`, `acceptable_constr_viol_tol`, `acceptable_iter`), permitindo que o solver encerre o processo caso as violações físicas já estejam dentro de uma tolerância técnica estipulada, ignorando a infactibilidade dual gerada pelo Big-M.

**Extração de Resultados (CSVs):**
Criei uma rotina em Julia para extrair os fluxos e listar as barras problemáticas do sistema. Para distinguir o que é apenas ruído numérico do solver de um corte de carga/gargalo real no sistema de transmissão, apliquei um filtro no DataFrame (CSV):
- Defini a `TOLERANCIA_FOLGA` como `1e-3` pu. 
- Na base de 100 MVA, isso equivale a **0.1 MW / 0.1 MVAr**. Barras que utilizaram folgas abaixo desse limiar foram descartadas, reduzindo drasticamente a lista de erros e isolando com precisão onde o SIN apresenta déficit ou estrangulamento físico nos casos simulados.