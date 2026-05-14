# Helpers compartilhados pelas 6 variantes (runner_analise_tcc.jl).
# Não tem `using JuMP` — variantes garantem que JuMP/PowerModels já estão carregados
# antes de chamar try_get_iters_jump.

using CSV
using DataFrames

# Schemas canônicos:
#   barras.csv:        caso, script, bus_id, vm_pu, va_rad, pd_pu, qd_pu, pg_pu, qg_pu, bus_type
#   ramos.csv:         caso, script, branch_id, f_bus, t_bus, pf_pu, qf_pu, pt_pu, qt_pu, loss_p_pu, loss_q_pu
#   convergencia.csv:  caso, script, termination_status, solve_time_s, objective, iteracoes, p_loss_total_pu

function write_canonical_outputs(; case::AbstractString, script::AbstractString,
                                   out::AbstractString,
                                   barras::DataFrame, ramos::DataFrame,
                                   meta::NamedTuple)
    mkpath(out)
    CSV.write(joinpath(out, "barras.csv"), barras)
    CSV.write(joinpath(out, "ramos.csv"),  ramos)
    conv = DataFrame(
        caso = [case], script = [script],
        termination_status = [String(meta.termination_status)],
        solve_time_s = [meta.solve_time_s],
        objective = [meta.objective],
        iteracoes = [meta.iteracoes],
        p_loss_total_pu = [meta.p_loss_total_pu],
    )
    CSV.write(joinpath(out, "convergencia.csv"), conv)
    return nothing
end

function write_failure_row(; case::AbstractString, script::AbstractString,
                            out::AbstractString,
                            termination_status::AbstractString)
    mkpath(out)
    conv = DataFrame(
        caso = [case], script = [script],
        termination_status = [String(termination_status)],
        solve_time_s = [NaN],
        objective = [NaN],
        iteracoes = [NaN],
        p_loss_total_pu = [NaN],
    )
    CSV.write(joinpath(out, "convergencia.csv"), conv)
    return nothing
end

# JuMP+Ipopt: tenta MOI.BarrierIterations(); fallback NaN se não disponível.
function try_get_iters_jump(model)
    try
        return Float64(JuMP.MOI.get(model, JuMP.MOI.BarrierIterations()))
    catch
        return NaN
    end
end

# PowerModels solve_ac_*: result Dict pode expor iter sob várias chaves.
function try_get_iters_pm(result)
    for k in ("solve_iters", "iterations", "iter")
        if haskey(result, k)
            v = result[k]
            v isa Number && return Float64(v)
        end
    end
    if haskey(result, "solver") && result["solver"] isa AbstractDict
        s = result["solver"]
        for k in ("iter", "iterations")
            if haskey(s, k)
                v = s[k]
                v isa Number && return Float64(v)
            end
        end
    end
    return NaN
end
