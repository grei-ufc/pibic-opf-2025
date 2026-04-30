# Compara barras entre formulações para casos críticos

using CSV
using DataFrames
using Printf

PASTA = joinpath(@__DIR__, "resultados_csv")

function carregar(case, sufixo)
    p = joinpath(PASTA, "$(case)__$(sufixo).csv")
    isfile(p) || (return nothing)
    df = CSV.read(p, DataFrame)
    rename!(df, :Vm_pu => Symbol("Vm_$sufixo"),
                :Va_graus => Symbol("Va_$sufixo"),
                :Pg_pu => Symbol("Pg_$sufixo"),
                :Qg_pu => Symbol("Qg_$sufixo"))
    return df
end

function comparar(case::String, sufa::String, sufb::String; topn::Int = 5)
    a = carregar(case, sufa); b = carregar(case, sufb)
    (isnothing(a) || isnothing(b)) && return
    cols_a = [:ID_Barra, Symbol("Vm_$sufa"), Symbol("Va_$sufa"),
              Symbol("Pg_$sufa"), Symbol("Qg_$sufa")]
    cols_b = [:ID_Barra, Symbol("Vm_$sufb"), Symbol("Va_$sufb"),
              Symbol("Pg_$sufb"), Symbol("Qg_$sufb")]
    df = innerjoin(a[:, cols_a], b[:, cols_b], on = :ID_Barra)
    df.dVm = abs.(df[:, Symbol("Vm_$sufa")] .- df[:, Symbol("Vm_$sufb")])
    df.dVa = abs.(df[:, Symbol("Va_$sufa")] .- df[:, Symbol("Va_$sufb")])
    df.dPg = abs.(df[:, Symbol("Pg_$sufa")] .- df[:, Symbol("Pg_$sufb")])
    df.dQg = abs.(df[:, Symbol("Qg_$sufa")] .- df[:, Symbol("Qg_$sufb")])

    println("\n========== CASO: $case  ($sufa vs $sufb) ==========")
    @printf("ΔVm máx = %.4f  |  ΔVa máx = %.4f°  |  ΔPg máx = %.4f pu  |  ΔQg máx = %.4f pu\n",
            maximum(df.dVm), maximum(df.dVa), maximum(df.dPg), maximum(df.dQg))

    println("\nTOP $topn |ΔVm|:")
    s = sort(df, :dVm, rev = true)
    @printf("%-6s %-12s %-12s %-12s\n", "Barra", "Vm_$sufa", "Vm_$sufb", "ΔVm")
    for i in 1:min(topn, nrow(s))
        @printf("%-6d %-12.4f %-12.4f %-12.4f\n",
                s.ID_Barra[i],
                s[i, Symbol("Vm_$sufa")],
                s[i, Symbol("Vm_$sufb")],
                s.dVm[i])
    end

    println("\nTOP $topn |ΔQg|:")
    s = sort(df, :dQg, rev = true)
    @printf("%-6s %-12s %-12s %-12s\n", "Barra", "Qg_$sufa", "Qg_$sufb", "ΔQg")
    for i in 1:min(topn, nrow(s))
        @printf("%-6d %-12.4f %-12.4f %-12.4f\n",
                s.ID_Barra[i],
                s[i, Symbol("Qg_$sufa")],
                s[i, Symbol("Qg_$sufb")],
                s.dQg[i])
    end

    println("\nTOP $topn |ΔPg|:")
    s = sort(df, :dPg, rev = true)
    @printf("%-6s %-12s %-12s %-12s\n", "Barra", "Pg_$sufa", "Pg_$sufb", "ΔPg")
    for i in 1:min(topn, nrow(s))
        @printf("%-6d %-12.4f %-12.4f %-12.4f\n",
                s.ID_Barra[i],
                s[i, Symbol("Pg_$sufa")],
                s[i, Symbol("Pg_$sufb")],
                s.dPg[i])
    end
end

# Casos críticos
comparar("5busfrank_csca", "1617_qv", "1617_csca", topn = 5)
comparar("3bus_DSHL", "pm", "1617_qv", topn = 3)
comparar("300bus", "pm", "1617_qv", topn = 10)
comparar("300bus", "1617_qv", "1617_csca", topn = 10)
comparar("3busfrank_qlim", "pm", "1617_qv", topn = 3)
comparar("3bus_DBSH", "1617_qv", "1617_csca", topn = 3)
comparar("3busfrank_continuous_shunt", "1617_qv", "1617_csca", topn = 3)
comparar("4busfrank_vlim", "1617_qv", "1617_csca", topn = 4)
comparar("3bus_shunt_fields", "1617_qv", "1617_csca", topn = 3)
comparar("500bus", "1617_qv", "1617_csca", topn = 10)
