# Instalação do ambiente (máquina nova)

Este guia reproduz **exatamente** o ambiente Julia usado no desenvolvimento do
trabalho, com as mesmas versões de todos os pacotes. Nenhum pacote é atualizado:
tudo é instalado nas versões pinadas em `Manifest.toml`.

## 1. Pré-requisitos

| Ferramenta | Versão | Observação |
|---|---|---|
| **Julia** | **1.8.3** | a mesma que gerou o `Manifest.toml` |
| git | qualquer recente | usado para clonar o PWF.jl |

A forma recomendada de obter o Julia 1.8.3 é via [juliaup](https://github.com/JuliaLang/juliaup):

```bash
juliaup add 1.8.3
```

## 2. Instalação automática (recomendada)

Na raiz do repositório:

```bash
julia +1.8.3 setup.jl        # com juliaup
# ou simplesmente: julia setup.jl   (se `julia --version` já for 1.8.3)
```

O `setup.jl` faz quatro coisas:

1. Verifica a versão do Julia;
2. Clona o **PWF.jl** no commit exato usado no trabalho (ver §4) em `~/.julia/dev/PWF`;
3. Aplica um pequeno patch de `[compat]` no `Project.toml` do PWF (ver §4);
4. Roda `Pkg.develop(path=...)` + `Pkg.instantiate()`, que baixa **todos** os
   demais pacotes nas versões pinadas do `Manifest.toml`.

## 3. Versões dos pacotes (registro)

Dependências diretas do projeto (`Project.toml`), com as versões efetivamente
usadas (`Manifest.toml`, gerado pelo Julia 1.8.3):

| Pacote | Versão | Origem |
|---|---|---|
| JuMP | **0.22.3** | registro General |
| PowerModels | **0.19.10** | registro General |
| Ipopt | **0.9.1** | registro General |
| PWF | 0.1.0 | **cópia local em `develop`** — ver §4 |
| ControlPowerFlow | 0.1.0 | **GitHub** `LAMPSPUC/ControlPowerFlow.jl`, branch `main` (tree-hash pinado no Manifest) |
| InfrastructureModels | 0.7.8 | registro General |
| PowerModelsRestoration | 0.7.0 | registro General |
| PowerPlots | 0.5.2 | registro General |
| CSV | 0.10.15 | registro General |
| DataFrames | 1.7.1 | registro General |
| JSON | 0.21.4 | registro General |
| Printf | stdlib | — |

> ⚠️ **Atenção:** JuMP 0.22 e Ipopt 0.9 são versões **antigas** (anteriores ao
> JuMP 1.0). O código usa a API da época (`@NLexpression`, `@NLconstraint`,
> `optimizer_with_attributes`). **Não rode `Pkg.update()`** — atualizar JuMP/Ipopt
> quebra os scripts. Se o Pkg sugerir upgrade, recuse e use `Pkg.instantiate()`.

## 4. O caso especial do PWF.jl

O `Manifest.toml` registra o PWF como pacote em modo `develop` apontando para um
caminho local (`~/.julia/dev/PWF`). Esse diretório é um clone de
[LAMPSPUC/PWF.jl](https://github.com/LAMPSPUC/PWF.jl) no commit:

```
97703035b224eb45aa2af55b5c9b0547f7b9cde4   (25/11/2022, merge do PR #38)
```

com **uma única modificação local**: a adição de um bloco `[compat]` ao
`Project.toml` (o commit original não tem compat, o que impede a resolução das
versões pinadas de Ipopt/PowerModels):

```toml
[compat]
Ipopt = "0.9"
PowerModels = "0.19"
Memento = "1.2"
```

O `setup.jl` clona, faz checkout desse commit e aplica esse patch automaticamente.
Se preferir fazer à mão:

```bash
git clone https://github.com/LAMPSPUC/PWF.jl.git ~/.julia/dev/PWF
git -C ~/.julia/dev/PWF checkout 9770303
# adicione o bloco [compat] acima ao final de ~/.julia/dev/PWF/Project.toml
```

e depois, na raiz deste repositório:

```julia
using Pkg
Pkg.activate(".")
Pkg.develop(path = joinpath(homedir(), ".julia", "dev", "PWF"))
Pkg.instantiate()
```

## 5. Verificando a instalação

Teste com uma rede pequena (edite a linha `arquivo = ...` no fim do script para
apontar para `3bus.pwf`, ou rode como está para o caso default):

```bash
julia --project=. "powerflow/Codes/PF_Formulation/(F2)QLIM+VLIM.jl"
```

Saída esperada: log do Ipopt terminando em `EXIT: Optimal Solution Found` /
`LOCALLY_SOLVED` e dois CSVs gravados em
`powerflow/Codes/PF_Formulation/resultados_csv/`.

> Os scripts F1/F4/FDC apontam por padrão para `CASO_VER_MAXDIU.PWF` (SIN
> integral, 13.338 barras) e F2/F3/F5 para `01 MAXIMA NOTURNA_DEZ25.PWF` —
> ambos **demoram muito** e (nas formulações AC) não convergem. Para um teste
> rápido, use sempre `3bus.pwf` ou `9bus.pwf`.

## 6. Problemas comuns

- **`Pkg.instantiate()` falha com "path .../dev/PWF does not exist"** — o
  Manifest guarda um caminho absoluto da máquina original. Rode o `setup.jl`
  (ou o passo manual do §4), que reescreve a entrada para o seu caminho local.
- **Erro de método/macro em JuMP (`@NLexpression` etc.)** — você está com um
  JuMP mais novo do que 0.22. Apague as alterações no `Project.toml`/
  `Manifest.toml` (`git checkout -- Project.toml Manifest.toml`) e rode
  `Pkg.instantiate()` de novo, sem `Pkg.add`/`Pkg.update`.
- **Julia 1.9+ re-resolve o Manifest** — use o Julia 1.8.3 (`juliaup add 1.8.3`).
