# Consolida per-job CSVs em masters (convergencia, barras, ramos).
# Substitui o bloco do runner_analise_tcc.jl que falhou por soft-scope.

using CSV
using DataFrames

const OUT_ROOT = abspath(joinpath(@__DIR__, "..", "resultados_csv"))

function read_optional(path)
    isfile(path) ? CSV.read(path, DataFrame) : nothing
end

function gather(filename)
    df = DataFrame()
    n = 0
    for entry in readdir(OUT_ROOT; join=true)
        isdir(entry) || continue
        basename(entry) == "logs" && continue
        for case_dir in readdir(entry; join=true)
            isdir(case_dir) || continue
            d = read_optional(joinpath(case_dir, filename))
            d === nothing && continue
            df = isempty(df) ? d : vcat(df, d; cols=:union)
            n += 1
        end
    end
    return df, n
end

println("Consolidando convergencia.csv...")
conv, n_conv = gather("convergencia.csv")
CSV.write(joinpath(OUT_ROOT, "convergencia.csv"), conv)
println("  $n_conv jobs → $(nrow(conv)) linhas")

println("Consolidando barras.csv...")
barras, n_barras = gather("barras.csv")
CSV.write(joinpath(OUT_ROOT, "barras.csv"), barras)
println("  $n_barras jobs → $(nrow(barras)) linhas")

println("Consolidando ramos.csv...")
ramos, n_ramos = gather("ramos.csv")
CSV.write(joinpath(OUT_ROOT, "ramos.csv"), ramos)
println("  $n_ramos jobs → $(nrow(ramos)) linhas")

# Sumário por script
println("\n=== Taxa de convergência por script ===")
conv.script = string.(conv.script)
grp = combine(groupby(conv, :script),
              :termination_status => (s -> sum(s .== "LOCALLY_SOLVED")) => :ok,
              :termination_status => length => :total)
for r in eachrow(grp)
    pct = round(100 * r.ok / r.total, digits=1)
    println("  ($(r.script)): $(r.ok)/$(r.total)  ($pct%)")
end
