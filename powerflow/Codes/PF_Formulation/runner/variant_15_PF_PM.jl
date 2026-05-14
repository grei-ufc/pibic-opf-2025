# variant_15_PF_PM.jl — adaptação do (15)PF_PM.jl.jl original para o runner.
# Original em ../(15)PF_PM.jl.jl é IMUTÁVEL.
#
# Idêntico ao variant_14 exceto que usa solve_ac_pf (não OPF), e o original
# não tinha a demote de múltiplas ref buses — aqui adicionamos a mesma proteção
# para robustez (sem isso, casos com >1 slack faliam silenciosamente).

using PWF
using PowerModels
using Ipopt
using JuMP
using CSV
using DataFrames

include(joinpath(@__DIR__, "_common.jl"))

const PIBIC_PWF     = get(ENV, "PIBIC_PWF",
                          joinpath(@__DIR__, "..", "..", "data", "01 MAXIMA NOTURNA_DEZ25.PWF"))
const PIBIC_CSV_DIR = get(ENV, "PIBIC_CSV_DIR",
                          joinpath(@__DIR__, "out_default", "15"))
const PIBIC_CASE_ID = get(ENV, "PIBIC_CASE_ID", basename(PIBIC_PWF))
const PIBIC_SCRIPT  = "15"
mkpath(PIBIC_CSV_DIR)

println("[variant_15] case=$PIBIC_CASE_ID  out=$PIBIC_CSV_DIR")

try
    println("1. Lendo arquivo PWF: $PIBIC_PWF")
    data = PWF.parse_file(PIBIC_PWF)
    base_mva = data["baseMVA"]

    PowerModels.select_largest_component!(data)
    PowerModels.standardize_cost_terms!(data, order=2)

    ref_buses = [b_dict for (_, b_dict) in data["bus"] if b_dict["bus_type"] == 3]
    if length(ref_buses) > 1
        println("-> Demovendo $(length(ref_buses)-1) barras slack para PV.")
        for i in 2:length(ref_buses)
            ref_buses[i]["bus_type"] = 2
        end
    end

    optimizer = optimizer_with_attributes(Ipopt.Optimizer,
        "max_iter" => 3000, "tol" => 1e-5, "print_level" => 0)

    println("2. Resolvendo AC PF...")
    resultado_pm = solve_ac_pf(data, optimizer)
    status = string(resultado_pm["termination_status"])
    solve_time_s = get(resultado_pm, "solve_time", NaN)
    obj = get(resultado_pm, "objective", NaN)
    iters = try_get_iters_pm(resultado_pm)
    println("Status=$status  solve_time=$solve_time_s  obj=$obj  iters=$iters")

    if status != "LOCALLY_SOLVED"
        write_failure_row(case=PIBIC_CASE_ID, script=PIBIC_SCRIPT, out=PIBIC_CSV_DIR,
                          termination_status=status)
        println("[variant_15] não convergiu (status=$status); somente convergencia.csv gravado.")
        exit(0)
    end

    df_barras = DataFrame(
        caso = String[], script = String[],
        bus_id = Int[], vm_pu = Float64[], va_rad = Float64[],
        pd_pu = Float64[], qd_pu = Float64[],
        pg_pu = Float64[], qg_pu = Float64[],
        bus_type = Int[],
    )
    for (i_str, bus_sol) in resultado_pm["solution"]["bus"]
        bus_id = parse(Int, i_str)
        vm = bus_sol["vm"]
        va = bus_sol["va"]

        pg = 0.0; qg = 0.0
        if haskey(resultado_pm["solution"], "gen")
            for (g, gen_sol) in resultado_pm["solution"]["gen"]
                if data["gen"][g]["gen_bus"] == bus_id
                    pg += gen_sol["pg"]
                    qg += gen_sol["qg"]
                end
            end
        end

        pd = 0.0; qd = 0.0
        for (_, load_data) in data["load"]
            if load_data["load_bus"] == bus_id
                pd += load_data["pd"]
                qd += load_data["qd"]
            end
        end

        push!(df_barras, (PIBIC_CASE_ID, PIBIC_SCRIPT, bus_id, vm, va,
                          pd, qd, pg, qg, data["bus"][i_str]["bus_type"]))
    end
    sort!(df_barras, :bus_id)

    df_ramos = DataFrame(
        caso = String[], script = String[],
        branch_id = Int[], f_bus = Int[], t_bus = Int[],
        pf_pu = Float64[], qf_pu = Float64[],
        pt_pu = Float64[], qt_pu = Float64[],
        loss_p_pu = Float64[], loss_q_pu = Float64[],
    )
    for (l, branch) in data["branch"]
        l_idx = parse(Int, l)
        f_bus = branch["f_bus"]; t_bus = branch["t_bus"]

        v_m_f = resultado_pm["solution"]["bus"][string(f_bus)]["vm"]
        v_a_f = resultado_pm["solution"]["bus"][string(f_bus)]["va"]
        v_m_t = resultado_pm["solution"]["bus"][string(t_bus)]["vm"]
        v_a_t = resultado_pm["solution"]["bus"][string(t_bus)]["va"]

        g, b = PowerModels.calc_branch_y(branch)
        tr, ti = PowerModels.calc_branch_t(branch)
        tm = branch["tap"]
        g_fr = branch["g_fr"]; b_fr = branch["b_fr"]
        g_to = branch["g_to"]; b_to = branch["b_to"]

        pf =  (g+g_fr)/tm^2 * v_m_f^2 + (-g*tr+b*ti)/tm^2 * (v_m_f*v_m_t*cos(v_a_f-v_a_t)) + (-b*tr-g*ti)/tm^2 * (v_m_f*v_m_t*sin(v_a_f-v_a_t))
        qf = -(b+b_fr)/tm^2 * v_m_f^2 - (-b*tr-g*ti)/tm^2 * (v_m_f*v_m_t*cos(v_a_f-v_a_t)) + (-g*tr+b*ti)/tm^2 * (v_m_f*v_m_t*sin(v_a_f-v_a_t))
        pt =  (g+g_to) * v_m_t^2 + (-g*tr-b*ti)/tm^2 * (v_m_t*v_m_f*cos(v_a_t-v_a_f)) + (-b*tr+g*ti)/tm^2 * (v_m_t*v_m_f*sin(v_a_t-v_a_f))
        qt = -(b+b_to) * v_m_t^2 - (-b*tr+g*ti)/tm^2 * (v_m_t*v_m_f*cos(v_a_t-v_a_f)) + (-g*tr-b*ti)/tm^2 * (v_m_t*v_m_f*sin(v_a_t-v_a_f))

        push!(df_ramos, (PIBIC_CASE_ID, PIBIC_SCRIPT, l_idx, f_bus, t_bus,
                         pf, qf, pt, qt, pf + pt, qf + qt))
    end
    sort!(df_ramos, :branch_id)

    write_canonical_outputs(
        case=PIBIC_CASE_ID, script=PIBIC_SCRIPT, out=PIBIC_CSV_DIR,
        barras=df_barras, ramos=df_ramos,
        meta=(termination_status = status,
              solve_time_s = solve_time_s,
              objective = obj,
              iteracoes = iters,
              p_loss_total_pu = sum(df_ramos.loss_p_pu)))
    println("[variant_15] OK  barras=$(nrow(df_barras))  ramos=$(nrow(df_ramos))  p_loss_total=$(sum(df_ramos.loss_p_pu))")
catch e
    @warn "[variant_15] OTHER_ERROR" exception=(e, catch_backtrace())
    write_failure_row(case=PIBIC_CASE_ID, script=PIBIC_SCRIPT, out=PIBIC_CSV_DIR,
                      termination_status="OTHER_ERROR")
end
