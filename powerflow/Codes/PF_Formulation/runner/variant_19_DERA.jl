# variant_19_DERA.jl — adaptação do (19)+DERA.jl original para o runner.
# Original em ../(19)+DERA.jl é IMUTÁVEL.

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
                          joinpath(@__DIR__, "out_default", "19"))
const PIBIC_CASE_ID = get(ENV, "PIBIC_CASE_ID", basename(PIBIC_PWF))
const PIBIC_SCRIPT  = "19"
mkpath(PIBIC_CSV_DIR)

println("[variant_19] case=$PIBIC_CASE_ID  out=$PIBIC_CSV_DIR")

function resolver_fluxo_controlado(caminho_arquivo)
    println("1. Lendo arquivo PWF: $caminho_arquivo")
    data = PWF.parse_file(caminho_arquivo, add_control_data=true)
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

    for (_, comp_dict) in data
        if comp_dict isa Dict
            chaves_para_remover = String[]
            for (k, v) in comp_dict
                if typeof(v) == Dict{String, Any} && tryparse(Int, k) === nothing
                    push!(chaves_para_remover, k)
                end
            end
            for k in chaves_para_remover
                delete!(comp_dict, k)
            end
        end
    end

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

    @variable(model, bs_var[i in keys(ref[:shunt])])
    @variable(model, sl_bsh[i in keys(ref[:shunt])], start=0.0)
    for (i, shunt) in ref[:shunt]
        bs_nom = shunt["bs"]
        bmin, bmax = bs_nom, bs_nom
        if haskey(shunt, "control_data")
            ctrl = shunt["control_data"]
            bmin = isnothing(get(ctrl, "bsmin", nothing)) ? bs_nom : ctrl["bsmin"]
            bmax = isnothing(get(ctrl, "bsmax", nothing)) ? bs_nom : ctrl["bsmax"]
        end
        real_bmin = min(bmin, bmax, bs_nom)
        real_bmax = max(bmin, bmax, bs_nom)
        set_lower_bound(bs_var[i], real_bmin)
        set_upper_bound(bs_var[i], real_bmax)
        set_start_value(bs_var[i], bs_nom)
        @constraint(model, bs_var[i] == bs_nom + sl_bsh[i])
        if real_bmin == real_bmax
            fix(bs_var[i], bs_nom; force=true)
        end
    end

    @variable(model, tm_var[l in keys(ref[:branch])])
    for (l, branch) in ref[:branch]
        tap_nominal = branch["tap"]
        tmin, tmax = tap_nominal, tap_nominal
        if haskey(branch, "control_data")
            ctrl = branch["control_data"]
            tmin = isnothing(get(ctrl, "tapmin", nothing)) ? tap_nominal : ctrl["tapmin"]
            tmax = isnothing(get(ctrl, "tapmax", nothing)) ? tap_nominal : ctrl["tapmax"]
        end
        real_tmin = min(tmin, tmax, tap_nominal)
        real_tmax = max(tmin, tmax, tap_nominal)
        if real_tmin < real_tmax
            set_lower_bound(tm_var[l], real_tmin)
            set_upper_bound(tm_var[l], real_tmax)
            set_start_value(tm_var[l], tap_nominal)
        else
            fix(tm_var[l], tap_nominal; force=true)
        end
    end

    for (i, gen) in ref[:gen]
        if gen["gen_bus"] in keys(ref[:ref_buses])
            if has_lower_bound(pg[i]) delete_lower_bound(pg[i]) end
            if has_upper_bound(pg[i]) delete_upper_bound(pg[i]) end
        else
            fix(pg[i], gen["pg"]; force=true)
        end
    end
    for (i, _b) in ref[:ref_buses]
        fix(va[i], 0.0; force=true)
    end

    PENALIDADE = 1e6
    PENALIDADE_MENOR = 1e4

    gen_buses_list = [gen["gen_bus"] for (_, gen) in ref[:gen]]
    shunt_buses = [
        shunt["shunt_bus"] for (_, shunt) in ref[:shunt]
        if haskey(shunt, "control_data") && haskey(shunt["control_data"], "bsmin") && shunt["control_data"]["bsmin"] != shunt["control_data"]["bsmax"]
    ]
    controlled_buses = unique(vcat(gen_buses_list, shunt_buses))

    @variable(model, sl_v[i in controlled_buses], start=0.0)
    @variable(model, sl_v_upp[i in controlled_buses] >= 0.0, start=0.0)
    @variable(model, sl_v_low[i in controlled_buses] >= 0.0, start=0.0)

    for bus_id in controlled_buses
        bus_data = ref[:bus][bus_id]
        if haskey(bus_data, "control_data") && haskey(bus_data["control_data"], "vmmin")
            vm_min_ctrl = bus_data["control_data"]["vmmin"]
            vm_max_ctrl = bus_data["control_data"]["vmmax"]
        else
            vm_min_ctrl = bus_data["vm"]
            vm_max_ctrl = bus_data["vm"]
        end
        if abs(vm_max_ctrl - vm_min_ctrl) < 1e-5
            @constraint(model, vm[bus_id] == vm_max_ctrl + sl_v[bus_id])
        else
            @constraint(model, vm[bus_id] >= vm_min_ctrl - sl_v_low[bus_id])
            @constraint(model, vm[bus_id] <= vm_max_ctrl + sl_v_upp[bus_id])
        end
    end

    @variable(model, sl_d[i in keys(ref[:load])], start=0.0)

    # DERA — corte de carga
    println("Criando variáveis de Corte de Carga (DERA)...")
    @variable(model, 0.0 <= corte_p[l in keys(ref[:load])] <= max(0.0, ref[:load][l]["pd"]), start=0.0)
    @variable(model, corte_q[l in keys(ref[:load])], start=0.0)

    for (l, load) in ref[:load]
        if load["pd"] > 1e-4
            @constraint(model, corte_q[l] == corte_p[l] * (load["qd"] / load["pd"]))
        else
            fix(corte_p[l], 0.0; force=true)
            fix(corte_q[l], 0.0; force=true)
        end
    end

    peso_corte = Dict()
    for (l, load) in ref[:load]
        bus_id = load["load_bus"]
        base_kv = get(ref[:bus][bus_id], "base_kv", 1.0)
        if base_kv < 69.0
            peso_corte[l] = 1e7
        elseif base_kv <= 230.0
            peso_corte[l] = 5e7
        else
            peso_corte[l] = 1e8
        end
    end

    println("3. Montando equações de fluxo (AC Polar com CTAP)...")
    p = Dict(); q = Dict()
    for (l, branch) in ref[:branch]
        f = branch["f_bus"]; t = branch["t_bus"]
        g, b = PowerModels.calc_branch_y(branch)
        g_fr = branch["g_fr"]; b_fr = branch["b_fr"]
        g_to = branch["g_to"]; b_to = branch["b_to"]
        shift = branch["shift"]
        cos_phi = cos(shift)
        sin_phi = sin(shift)

        p[(l, f, t)] = @NLexpression(model,
            (g + g_fr) / tm_var[l]^2 * vm[f]^2 +
            (-g * cos_phi + b * sin_phi) / tm_var[l] * (vm[f] * vm[t] * cos(va[f] - va[t])) +
            (-b * cos_phi - g * sin_phi) / tm_var[l] * (vm[f] * vm[t] * sin(va[f] - va[t])))
        q[(l, f, t)] = @NLexpression(model,
            -(b + b_fr) / tm_var[l]^2 * vm[f]^2 -
            (-b * cos_phi - g * sin_phi) / tm_var[l] * (vm[f] * vm[t] * cos(va[f] - va[t])) +
            (-g * cos_phi + b * sin_phi) / tm_var[l] * (vm[f] * vm[t] * sin(va[f] - va[t])))
        p[(l, t, f)] = @NLexpression(model,
            (g + g_to) * vm[t]^2 +
            (-g * cos_phi - b * sin_phi) / tm_var[l] * (vm[t] * vm[f] * cos(va[t] - va[f])) +
            (-b * cos_phi + g * sin_phi) / tm_var[l] * (vm[t] * vm[f] * sin(va[t] - va[f])))
        q[(l, t, f)] = @NLexpression(model,
            -(b + b_to) * vm[t]^2 -
            (-b * cos_phi + g * sin_phi) / tm_var[l] * (vm[t] * vm[f] * cos(va[t] - va[f])) +
            (-g * cos_phi - b * sin_phi) / tm_var[l] * (vm[t] * vm[f] * sin(va[t] - va[f])))
    end

    println("4. Montando balanço nodal com DERA...")
    for (i, _b) in ref[:bus]
        bus_arcs = ref[:bus_arcs][i]
        bus_arcs_dc = ref[:bus_arcs_dc][i]
        bus_gens = ref[:bus_gens][i]
        bus_loads = ref[:bus_loads][i]
        bus_shunts = [k for (k, shunt) in ref[:shunt] if shunt["shunt_bus"] == i]

        pd_nominal = sum(load["pd"] for (_, load) in ref[:load] if load["load_bus"] == i; init=0.0)
        qd_nominal = sum(load["qd"] for (_, load) in ref[:load] if load["load_bus"] == i; init=0.0)
        corte_p_total = isempty(bus_loads) ? 0.0 : sum(corte_p[l] for l in bus_loads)
        corte_q_total = isempty(bus_loads) ? 0.0 : sum(corte_q[l] for l in bus_loads)
        p_gen_total = isempty(bus_gens) ? 0.0 : sum(pg[g] for g in bus_gens)
        q_gen_total = isempty(bus_gens) ? 0.0 : sum(qg[g] for g in bus_gens)
        p_dcline_total = isempty(bus_arcs_dc) ? 0.0 : sum(p_dc[a] for a in bus_arcs_dc)
        q_dcline_total = isempty(bus_arcs_dc) ? 0.0 : sum(q_dc[a] for a in bus_arcs_dc)
        slack_vlim = isempty(bus_loads) ? 0.0 : sum(sl_d[l] for l in bus_loads)
        gs_total = isempty(bus_shunts) ? 0.0 : sum(ref[:shunt][k]["gs"] for k in bus_shunts)

        @NLconstraint(model,
            sum(p[a] for a in bus_arcs) + p_dcline_total == p_gen_total - (pd_nominal - corte_p_total) - gs_total*vm[i]^2)
        if isempty(bus_shunts)
            @NLconstraint(model,
                sum(q[a] for a in bus_arcs) + q_dcline_total == q_gen_total - (qd_nominal - corte_q_total + slack_vlim))
        else
            @NLconstraint(model,
                sum(q[a] for a in bus_arcs) + q_dcline_total == q_gen_total - (qd_nominal - corte_q_total + slack_vlim) + sum(bs_var[k]*vm[i]^2 for k in bus_shunts))
        end
    end

    @objective(model, Min,
        PENALIDADE * sum(sl_v[i]^2 for i in controlled_buses) +
        PENALIDADE * sum(sl_v_upp[i]^2 + sl_v_low[i]^2 for i in controlled_buses) +
        PENALIDADE * sum(sl_d[l]^2 for l in keys(ref[:load])) +
        PENALIDADE_MENOR * sum(sl_bsh[k]^2 for k in keys(ref[:shunt])) +
        sum(peso_corte[l] * corte_p[l] for l in keys(ref[:load])))

    println("5. Resolvendo...")
    optimize!(model)

    status = string(termination_status(model))
    solve_time_s = solve_time(model)
    println("Status=$status  solve_time=$solve_time_s")

    if status != "LOCALLY_SOLVED"
        write_failure_row(case=PIBIC_CASE_ID, script=PIBIC_SCRIPT, out=PIBIC_CSV_DIR,
                          termination_status=status)
        println("[variant_19] não convergiu.")
        return
    end

    obj = objective_value(model)
    iters = try_get_iters_jump(model)

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
    println("[variant_19] OK  barras=$(nrow(df_barras))  ramos=$(nrow(df_ramos))  p_loss_total=$(sum(df_ramos.loss_p_pu))")
end

try
    resolver_fluxo_controlado(PIBIC_PWF)
catch e
    @warn "[variant_19] OTHER_ERROR" exception=(e, catch_backtrace())
    write_failure_row(case=PIBIC_CASE_ID, script=PIBIC_SCRIPT, out=PIBIC_CSV_DIR,
                      termination_status="OTHER_ERROR")
end
