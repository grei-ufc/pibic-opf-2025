# Resumo das Atividades: Implementação e Análise do Problema de Maximum Load Delivery (MLD)

## 1. Investigação sobre a Função `solve_mld`
Durante a revisão das bibliotecas do ecossistema do PowerModels para a execução do MLD, realizei uma investigação no código-fonte. Identifiquei a existência da função `_solve_mld` dentro do pacote principal `PowerModels.jl` (especificamente em `src/prob/test.jl`). Contudo, constatei que se trata de uma função interna e privada (indicada pelo prefixo `_`), utilizada pelos desenvolvedores apenas para testes simplificados de integração ("toy problems").

Optei enrão por adotar a implementação oficial para ambiente de produção, disponível no pacote `PowerModelsRestoration.jl`. A sintaxe adotada nos benchmarks foi a chamada genérica `run_mld(data, ACPPowerModel, optimizer)`, que permite fácil transição de formulações matemáticas.

## 2. Análise de Convergência Numérica e Limite de Iterações
Ao rodar os casos do SIN com o solver Ipopt, o modelo atingiu o limite de iterações (`ITERATION_LIMIT` em 3000). 
