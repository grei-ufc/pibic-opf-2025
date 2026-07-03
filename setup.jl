# setup.jl — Prepara o ambiente Julia deste repositório em uma máquina nova,
# reproduzindo EXATAMENTE as versões de pacotes usadas no desenvolvimento
# (ver Manifest.toml e INSTALACAO.md).
#
# Uso (a partir da raiz do repositório):
#     julia setup.jl
#
# Requisito: Julia 1.8.3 (a mesma versão registrada no Manifest.toml).
# Recomendado instalar via juliaup:  juliaup add 1.8.3
#
# O que este script faz:
#   1. Verifica a versão do Julia (avisa se diferente de 1.8.x);
#   2. Clona o PWF.jl (LAMPSPUC) no commit exato usado no trabalho
#      (9770303, de 25/11/2022) para ~/.julia/dev/PWF, caso ainda não exista;
#   3. Aplica o patch local de [compat] no Project.toml do PWF
#      (necessário para coexistir com Ipopt 0.9 / PowerModels 0.19);
#   4. Registra o PWF como pacote em modo `develop` e roda Pkg.instantiate(),
#      que baixa todos os demais pacotes NAS VERSÕES PINADAS do Manifest.toml
#      (JuMP 0.22.3, PowerModels 0.19.10, Ipopt 0.9.1, etc.), inclusive o
#      ControlPowerFlow.jl direto do GitHub no tree-hash registrado.
#
# O script NÃO atualiza nenhum pacote (nunca chama Pkg.update()).

using Pkg

const PWF_URL    = "https://github.com/LAMPSPUC/PWF.jl.git"
const PWF_COMMIT = "97703035b224eb45aa2af55b5c9b0547f7b9cde4"  # 2022-11-25
const PWF_DEV    = joinpath(homedir(), ".julia", "dev", "PWF")

# Bloco [compat] aplicado localmente sobre o Project.toml do PWF
# (o commit acima não possui compat, o que quebraria a resolução de versões).
const PWF_COMPAT = """

[compat]
Ipopt = "0.9"
PowerModels = "0.19"
Memento = "1.2"
"""

# ---------------------------------------------------------------------------
# 1. Versão do Julia
# ---------------------------------------------------------------------------
if VERSION < v"1.8" || VERSION >= v"1.9"
    @warn """
    Este projeto foi desenvolvido com Julia 1.8.3 e o Manifest.toml foi
    gerado por essa versão. Você está usando Julia $(VERSION).
    Para reproduzir o ambiente fielmente:
        juliaup add 1.8.3
        julia +1.8.3 setup.jl
    Continuando mesmo assim (o Pkg pode re-resolver versões)...
    """
end

# ---------------------------------------------------------------------------
# 2. Clonar PWF.jl no commit usado no trabalho
# ---------------------------------------------------------------------------
if isdir(joinpath(PWF_DEV, ".git"))
    @info "PWF.jl já existe em $PWF_DEV — mantendo como está (não vou sobrescrever)."
else
    @info "Clonando PWF.jl em $PWF_DEV ..."
    mkpath(dirname(PWF_DEV))
    run(`git clone $PWF_URL $PWF_DEV`)
    run(`git -C $PWF_DEV checkout $PWF_COMMIT`)

    # 3. Patch de compat (idempotente)
    proj_path = joinpath(PWF_DEV, "Project.toml")
    proj = read(proj_path, String)
    if !occursin("[compat]", proj)
        @info "Aplicando patch [compat] no Project.toml do PWF..."
        write(proj_path, rstrip(proj) * PWF_COMPAT)
    end
end

# ---------------------------------------------------------------------------
# 4. Ativar o ambiente do repositório e instalar tudo nas versões pinadas
# ---------------------------------------------------------------------------
Pkg.activate(@__DIR__)

# Registra o PWF local em modo develop. Em outra máquina o caminho absoluto
# gravado no Manifest.toml não existe, então este passo o reescreve para o
# caminho local equivalente (~/.julia/dev/PWF) sem alterar versões.
@info "Registrando PWF em modo develop..."
Pkg.develop(path = PWF_DEV)

@info "Instalando dependências nas versões pinadas do Manifest.toml..."
Pkg.instantiate()

Pkg.status()

@info """
Ambiente pronto!

Teste rápido (rede de 3 barras):
    julia --project=. "powerflow/Codes/PF_Formulation/(F2)QLIM+VLIM.jl"
    (antes, edite a linha `arquivo = ...` no fim do script para "3bus.pwf")

Consulte INSTALACAO.md e README.md para detalhes.
"""
