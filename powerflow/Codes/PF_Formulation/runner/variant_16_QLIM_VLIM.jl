# variant_16_QLIM_VLIM.jl — adaptação do (16)QLIM+VLIM.jl original para o runner.
# Original em ../(16)QLIM+VLIM.jl é IMUTÁVEL.
#
# Diferenças vs original:
#  - PIBIC_PWF / PIBIC_CSV_DIR / PIBIC_CASE_ID via ENV
#  - O original NÃO escrevia CSV; adicionamos bloco canônico no final
#  - Wrap em try/catch que grava failure row

using PWF
using PowerModels
using JuMP
using Ipopt
using CSV
using DataFrames

include(joinpath(@__DIR__, "_common.jl"))

const PIBIC_PWF     = get(ENV, "PIBIC_PWF",
                          joinpath(@__DIR__, "..", "..", "data", "01 MAXIMA NOTURNA_DEZ25.PWF"))
const PIBIC_CSV_DIR = get(ENV, "PIBIC_CSV_DIR",
                          joinpath(@__DIR__, "out_default", "16"))
const PIBIC_CASE_ID = get(ENV, "PIBIC_CASE_ID", basename(PIBIC_PWF))
const PIBIC_SCRIPT  = "16"
mkpath(PIBIC_CSV_DIR)

println("[variant_16] case=$PIBIC_CASE_ID  out=$PIBIC_CSV_DIR")

function resolver_fluxo_controlado(caminho_arquivo)
    println("1. Lendo arquivo PWF: $caminho_arquivo")
    data = PWF.parse_file(caminho_arquivo)
    base_mva = data["baseMVA"]

    PowerModels.select_largest_component!(data)

    ref_buses = [b_dict for (_, b_dict) in data["bus"] if b_dict["bus_type"] == 3]
    if length(ref_buses) > 1
        println("-> Demovendo $(length(ref_buses)-1) barras slack para PV.")
        for i in 2:length(ref_buses)
            ref_buses[i]["bus_type"] = 2
        end
    end

    PowerModels.standardize_cost_terms!(data, order=2)
    ref = PowerModels.build_ref(data)[:it][:pm][:nw][0]

    model = Model(optimizer_with_attributes(Ipopt.Optimizer,
        "max_iter" => 3000, "tol" => 1e-5, "print_level" => 5))

    println("2. Criando variáveis...")
    @variable(model, ref[:bus][i]["vmin"] <= vm[i in keys(ref[:bus])] <= ref[:bus][i]["vmax"], start=ref[:bus][i]["vm"])
    @variable(model, va[i in keys(ref[:bus])], start=ref[:bus][i]["va"])

    @variable(model, ref[:gen][i]["pmin"] <= pg[i in keys(ref[:gen])] <= ref[:gen][i]["pmax"], start=ref[:gen][i]["pg"])
    @variable(model, ref[:gen][i]["qmin"] <= qg[i in keys(ref[:gen])] <= ref[:gen][i]["qmax"], start=ref[:gen][i]["qg"])

    p_dc = Dict(); q_dc = Dict()
    for (l, dcline) in ref[:dcline]
        f = dcline["f_bus"]; t = dcline["t_bus"]
        p_dc[(l, f, t)] = @variable(model, start=dcline["pf"])
        p_dc[(l, t, f)] = @variable(model, start=dcline["pt"])
        q_dc[(l, f, t)] = @variable(model, start=dcline["qf"])
        q_dc[(l, t, f)] = @variable(model, start=dcline["qt"])
        fix(p_dc[(l, f, t)], dcline["pf"]; force=true)
        fix(p_dc[(l, t, f)], dcline["pt"]; force=true)
        fix(q_dc[(l, f, t)], dcline["qf"]; force=true)
        fix(q_dc[(l, t, f)], dcline["qt"]; force=true)
    end

    for (i, gen) in ref[:gen]
        if gen["gen_bus"] in keys(ref[:ref_buses])
            if has_lower_bound(pg[i]) delete_lower_bound(pg[i]) end
            if has_upper_bound(pg[i]) delete_upper_bound(pg[i]) end
        else
            fix(pg[i], gen["pg"]; force=true)
        end
    end

    for (i, _bus) in ref[:ref_buses]
        fix(va[i], 0.0; force=true)
    end

    PENALIDADE = 1e6

    gen_buses = unique([gen["gen_bus"] for (_, gen) in ref[:gen]])
    @variable(model, sl_v[i in gen_buses], start=0.0)
    for bus_id in gen_buses
        vm_setpoint = ref[:bus][bus_id]["vm"]
        @constraint(model, vm[bus_id] == vm_setpoint + sl_v[bus_id])
    end

    @variable(model, sl_d[i in keys(ref[:load])], start=0.0)

    println("3. Montando equações de fluxo (AC Polar)...")
    p = Dict(); q = Dict()
    for (l, branch) in ref[:branch]
        f = branch["f_bus"]; t = branch["t_bus"]
        g, b = PowerModels.calc_branch_y(branch)
        tr, ti = PowerModels.calc_branch_t(branch)
        tm = branch["tap"]
        g_fr = branch["g_fr"]; b_fr = branch["b_fr"]
        g_to = branch["g_to"]; b_to = branch["b_to"]

        p[(l, f, t)] = @NLexpression(model, (g+g_fr)/tm^2 * vm[f]^2 + (-g*tr+b*ti)/tm^2 * (vm[f]*vm[t]*cos(va[f]-va[t])) + (-b*tr-g*ti)/tm^2 * (vm[f]*vm[t]*sin(va[f]-va[t])))
        q[(l, f, t)] = @NLexpression(model, -(b+b_fr)/tm^2 * vm[f]^2 - (-b*tr-g*ti)/tm^2 * (vm[f]*vm[t]*cos(va[f]-va[t])) + (-g*tr+b*ti)/tm^2 * (vm[f]*vm[t]*sin(va[f]-va[t])))
        p[(l, t, f)] = @NLexpression(model, (g+g_to) * vm[t]^2 + (-g*tr-b*ti)/tm^2 * (vm[t]*vm[f]*cos(va[t]-va[f])) + (-b*tr+g*ti)/tm^2 * (vm[t]*vm[f]*sin(va[t]-va[f])))
        q[(l, t, f)] = @NLexpression(model, -(b+b_to) * vm[t]^2 - (-b*tr+g*ti)/tm^2 * (vm[t]*vm[f]*cos(va[t]-va[f])) + (-g*tr-b*ti)/tm^2 * (vm[t]*vm[f]*sin(va[t]-va[f])))
    end

    println("4. Montando balanço nodal (Kirchhoff)...")
    for (i, _bus) in ref[:bus]
        bus_arcs = ref[:bus_arcs][i]
        bus_arcs_dc = ref[:bus_arcs_dc][i]
        bus_gens = ref[:bus_gens][i]
        bus_loads = ref[:bus_loads][i]

        gs = sum(shunt["gs"] for (_, shunt) in ref[:shunt] if shunt["shunt_bus"] == i; init=0.0)
        bs = sum(shunt["bs"] for (_, shunt) in ref[:shunt] if shunt["shunt_bus"] == i; init=0.0)

        pd_nominal = sum(load["pd"] for (_, load) in ref[:load] if load["load_bus"] == i; init=0.0)
        qd_nominal = sum(load["qd"] for (_, load) in ref[:load] if load["load_bus"] == i; init=0.0)

        p_gen_total = isempty(bus_gens) ? 0.0 : sum(pg[g] for g in bus_gens)
        q_gen_total = isempty(bus_gens) ? 0.0 : sum(qg[g] for g in bus_gens)
        p_dcline_total = isempty(bus_arcs_dc) ? 0.0 : sum(p_dc[a] for a in bus_arcs_dc)
        q_dcline_total = isempty(bus_arcs_dc) ? 0.0 : sum(q_dc[a] for a in bus_arcs_dc)
        slack_vlim = isempty(bus_loads) ? 0.0 : sum(sl_d[l] for l in bus_loads)

        @NLconstraint(model,
            sum(p[a] for a in bus_arcs) + p_dcline_total == p_gen_total - pd_nominal - gs*vm[i]^2)
        @NLconstraint(model,
            sum(q[a] for a in bus_arcs) + q_dcline_total == q_gen_total - (qd_nominal + slack_vlim) + bs*vm[i]^2)
    end

    @objective(model, Min,
        PENALIDADE * sum(sl_v[i]^2 for i in keys(sl_v)) +
        PENALIDADE * sum(sl_d[l]^2 for l in keys(sl_d)))

    println("5. Resolvendo...")
    optimize!(model)

    status = string(termination_status(model))
    solve_time_s = solve_time(model)
    println("Status=$status  solve_time=$solve_time_s")

    if status != "LOCALLY_SOLVED"
        write_failure_row(case=PIBIC_CASE_ID, script=PIBIC_SCRIPT, out=PIBIC_CSV_DIR,
                          termination_status=status)
        println("[variant_16] não convergiu; somente convergencia.csv.")
        return
    end

    obj = objective_value(model)
    iters = try_get_iters_jump(model)

    # ----- df_barras canônico -----
    df_barras = DataFrame(
        caso = String[], script = String[],
        bus_id = Int[], vm_pu = Float64[], va_rad = Float64[],
        pd_pu = Float64[], qd_pu = Float64[],
        pg_pu = Float64[], qg_pu = Float64[],
        bus_type = Int[],
    )
    for (i, bus) in ref[:bus]
        bus_gens = ref[:bus_gens][i]
        bus_loads = ref[:bus_loads][i]
        pg_v = isempty(bus_gens) ? 0.0 : sum(value(pg[g]) for g in bus_gens)
        qg_v = isempty(bus_gens) ? 0.0 : sum(value(qg[g]) for g in bus_gens)
        pd_v = isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["pd"] for l in bus_loads)
        qd_v = isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["qd"] for l in bus_loads)
        push!(df_barras, (PIBIC_CASE_ID, PIBIC_SCRIPT, i, value(vm[i]), value(va[i]),
                          pd_v, qd_v, pg_v, qg_v, bus["bus_type"]))
    end
    sort!(df_barras, :bus_id)

    # ----- df_ramos canônico -----
    df_ramos = DataFrame(
        caso = String[], script = String[],
        branch_id = Int[], f_bus = Int[], t_bus = Int[],
        pf_pu = Float64[], qf_pu = Float64[],
        pt_pu = Float64[], qt_pu = Float64[],
        loss_p_pu = Float64[], loss_q_pu = Float64[],
    )
    for (l, branch) in ref[:branch]
        f = branch["f_bus"]; t = branch["t_bus"]
        pf = value(p[(l, f, t)]); qf = value(q[(l, f, t)])
        pt = value(p[(l, t, f)]); qt = value(q[(l, t, f)])
        push!(df_ramos, (PIBIC_CASE_ID, PIBIC_SCRIPT, l, f, t, pf, qf, pt, qt, pf + pt, qf + qt))
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
    println("[variant_16] OK  barras=$(nrow(df_barras))  ramos=$(nrow(df_ramos))  p_loss_total=$(sum(df_ramos.loss_p_pu))")
end

try
    resolver_fluxo_controlado(PIBIC_PWF)
catch e
    @warn "[variant_16] OTHER_ERROR" exception=(e, catch_backtrace())
    write_failure_row(case=PIBIC_CASE_ID, script=PIBIC_SCRIPT, out=PIBIC_CSV_DIR,
                      termination_status="OTHER_ERROR")
end
