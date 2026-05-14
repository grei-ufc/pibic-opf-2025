# consolidar.jl — pós-processamento dos masters CSVs do runner_analise_tcc.
#
# - Carrega resultados_csv/{convergencia,barras,ramos}.csv
# - Aplica critério de equivalência (|Δ|≤1e-4) entre pares de formulações
# - Atribui cluster IDs incrementais por caso: (14)=1, demais comparam contra
#   clusters existentes na ordem e herdam ou recebem próximo inteiro.
# - Não-convergidos → "N/C"
# - Escreve resultados_csv/clusters.csv

using CSV
using DataFrames

const OUT_ROOT = abspath(joinpath(@__DIR__, "..", "resultados_csv"))
const TOL = 1e-4
const SCRIPT_ORDER = ["14", "15", "16", "17", "18", "19"]

function load_or_empty(path)
    isfile(path) || return DataFrame()
    CSV.read(path, DataFrame)
end

conv   = load_or_empty(joinpath(OUT_ROOT, "convergencia.csv"))
barras = load_or_empty(joinpath(OUT_ROOT, "barras.csv"))
ramos  = load_or_empty(joinpath(OUT_ROOT, "ramos.csv"))

if isempty(conv)
    error("convergencia.csv vazio ou ausente em $OUT_ROOT")
end

# Normaliza colunas de tipo para string
conv.script = string.(conv.script)
conv.caso = string.(conv.caso)
isempty(barras) || (barras.script = string.(barras.script); barras.caso = string.(barras.caso))
isempty(ramos)  || (ramos.script  = string.(ramos.script);  ramos.caso  = string.(ramos.caso))

solved(c::AbstractString, s::AbstractString) = begin
    sel = (conv.caso .== c) .& (conv.script .== s)
    any(sel) && first(conv[sel, :termination_status]) == "LOCALLY_SOLVED"
end

# Função: dado um caso e dois scripts, retorna true se equivalentes.
# Critério: |Δvm|, |Δva|, |Δpg|, |Δqg|, |Δpf|, |Δqf| ≤ TOL em TODOS os elementos.
function are_equivalent(caso::AbstractString, a::AbstractString, b::AbstractString)
    (solved(caso, a) && solved(caso, b)) || return false

    ba = filter(r -> r.caso == caso && r.script == a, barras)
    bb = filter(r -> r.caso == caso && r.script == b, barras)
    if isempty(ba) || isempty(bb)
        return false
    end
    # Join por bus_id
    j = innerjoin(ba, bb; on=:bus_id, makeunique=true)
    if nrow(j) != nrow(ba) || nrow(j) != nrow(bb)
        return false
    end
    if any(abs.(j.vm_pu .- j.vm_pu_1) .> TOL); return false; end
    if any(abs.(j.va_rad .- j.va_rad_1) .> TOL); return false; end
    if any(abs.(j.pg_pu .- j.pg_pu_1) .> TOL); return false; end
    if any(abs.(j.qg_pu .- j.qg_pu_1) .> TOL); return false; end

    ra = filter(r -> r.caso == caso && r.script == a, ramos)
    rb = filter(r -> r.caso == caso && r.script == b, ramos)
    if isempty(ra) || isempty(rb)
        return false
    end
    jr = innerjoin(ra, rb; on=:branch_id, makeunique=true)
    if nrow(jr) != nrow(ra) || nrow(jr) != nrow(rb)
        return false
    end
    if any(abs.(jr.pf_pu .- jr.pf_pu_1) .> TOL); return false; end
    if any(abs.(jr.qf_pu .- jr.qf_pu_1) .> TOL); return false; end

    return true
end

# Atribuição de clusters por caso
cluster_rows = NamedTuple{(:caso, :script, :cluster_id), Tuple{String, String, String}}[]

cases = unique(conv.caso)
sort!(cases)
for caso in cases
    # Cluster representatives: dict cluster_id => script_representante
    reps = Tuple{Int, String}[]
    next_id = 1
    for s in SCRIPT_ORDER
        if !solved(caso, s)
            push!(cluster_rows, (caso=caso, script=s, cluster_id="N/C"))
            continue
        end
        # Procura cluster existente equivalente
        found_id = 0
        for (cid, rep_script) in reps
            if are_equivalent(caso, s, rep_script)
                found_id = cid
                break
            end
        end
        if found_id == 0
            # Novo cluster
            cid = next_id
            push!(reps, (cid, s))
            next_id += 1
            push!(cluster_rows, (caso=caso, script=s, cluster_id=string(cid)))
        else
            push!(cluster_rows, (caso=caso, script=s, cluster_id=string(found_id)))
        end
    end
    println("Caso $caso: $(length(reps)) cluster(s) distintos.")
end

df_clusters = DataFrame(cluster_rows)
CSV.write(joinpath(OUT_ROOT, "clusters.csv"), df_clusters)

# Sumário
n_cases = length(cases)
total_clusters = 0
for caso in cases
    cl = filter(r -> r.caso == caso && r.cluster_id != "N/C", df_clusters)
    if !isempty(cl)
        total_clusters += length(unique(cl.cluster_id))
    end
end
println("Total de casos: $n_cases")
println("Total de clusters distintos (somando por caso): $total_clusters")
println("clusters.csv → $(joinpath(OUT_ROOT, "clusters.csv"))")
