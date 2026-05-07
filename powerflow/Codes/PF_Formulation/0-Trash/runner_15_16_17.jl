# =========================================================================
# RUNNER: roda (15)PowerModels, (16)QLIM+VLIM e (17)QLIM+VLIM+CSCA em todos
# os arquivos .pwf da pasta powerflow/Codes/data/ e gera:
#   - <case>__pm.csv, <case>__1617_qv.csv, <case>__1617_csca.csv (barras)
#   - sumario_runner.csv  (uma linha por caso × formulação)
# =========================================================================

using PWF
using PowerModels
using JuMP
using Ipopt
using CSV
using DataFrames

print("\033c")

PASTA_DADOS  = normpath(joinpath(@__DIR__, "..", "data"))
PASTA_CSV    = joinpath(@__DIR__, "resultados_csv")
mkpath(PASTA_CSV)
println("PASTA_DADOS = ", PASTA_DADOS, "  (existe? ", isdir(PASTA_DADOS), ")")

# Configuração comum do solver
function fazer_solver(; print_level = 0)
    optimizer_with_attributes(Ipopt.Optimizer,
        "max_iter"    => 3000,
        "tol"         => 1e-5,
        "print_level" => print_level,
    )
end

# -------------------------------------------------------------------------
# Patch de limpeza para o build_ref engasgado em chaves não-numéricas
# (necessário quando o PWF expõe "control_data", "parameters" etc.)
# -------------------------------------------------------------------------
function limpar_chaves_nao_numericas!(data::Dict)
    for (_, comp_dict) in data
        if comp_dict isa Dict
            chaves = String[]
            for (k, v) in comp_dict
                if v isa Dict && tryparse(Int, k) === nothing
                    push!(chaves, k)
                end
            end
            for k in chaves
                delete!(comp_dict, k)
            end
        end
    end
end

# =========================================================================
# (15) PowerModels.run_ac_pf - fluxo de potência tradicional
# =========================================================================
function rodar_pm(caminho_arquivo::String, case_name::String)
    data = PWF.parse_file(caminho_arquivo)
    base_mva = get(data, "baseMVA", 100.0)

    PowerModels.select_largest_component!(data)
    PowerModels.standardize_cost_terms!(data, order = 2)

    tempo = @elapsed res = run_ac_pf(data, fazer_solver())
    status = res["termination_status"]

    df_barras = DataFrame(
        ID_Barra = Int[], Tipo_Barra = Int[],
        Vm_pu = Float64[], Va_graus = Float64[],
        Pg_pu = Float64[], Qg_pu = Float64[],
        Pd_pu = Float64[], Qd_pu = Float64[],
    )

    if status in (LOCALLY_SOLVED, OPTIMAL)
        for (i_str, sol) in res["solution"]["bus"]
            i = parse(Int, i_str)
            pg = qg = 0.0
            for (g, gs) in res["solution"]["gen"]
                if data["gen"][g]["gen_bus"] == i
                    pg += gs["pg"]; qg += gs["qg"]
                end
            end
            pd = sum(l["pd"] for (_, l) in data["load"] if l["load_bus"] == i; init = 0.0)
            qd = sum(l["qd"] for (_, l) in data["load"] if l["load_bus"] == i; init = 0.0)
            push!(df_barras, (i, data["bus"][i_str]["bus_type"],
                              sol["vm"], sol["va"] * 180/π,
                              pg, qg, pd, qd))
        end
        sort!(df_barras, :ID_Barra)
        CSV.write(joinpath(PASTA_CSV, "$(case_name)__pm.csv"), df_barras)
    end

    if nrow(df_barras) == 0
        return (status = string(status), tempo = tempo,
                vmin = NaN, vmax = NaN, pg_total = NaN, qg_total = NaN,
                slacks = 0.0, n_barras = 0)
    end

    pg_tot = sum(df_barras.Pg_pu)
    qg_tot = sum(df_barras.Qg_pu)
    return (status = string(status), tempo = tempo,
            vmin = minimum(df_barras.Vm_pu),
            vmax = maximum(df_barras.Vm_pu),
            pg_total = pg_tot * base_mva,
            qg_total = qg_tot * base_mva,
            slacks = 0.0,
            n_barras = nrow(df_barras))
end

# =========================================================================
# (16) QLIM+VLIM (formulação JuMP, com elos DC)
# =========================================================================
function rodar_qlim_vlim(caminho_arquivo::String, case_name::String)
    data = PWF.parse_file(caminho_arquivo)
    base_mva = get(data, "baseMVA", 100.0)

    PowerModels.select_largest_component!(data)
    PowerModels.standardize_cost_terms!(data, order = 2)
    ref = PowerModels.build_ref(data)[:it][:pm][:nw][0]

    model = Model(fazer_solver())

    @variable(model, ref[:bus][i]["vmin"] <= vm[i in keys(ref[:bus])] <= ref[:bus][i]["vmax"], start = ref[:bus][i]["vm"])
    @variable(model, va[i in keys(ref[:bus])], start = ref[:bus][i]["va"])
    @variable(model, ref[:gen][i]["pmin"] <= pg[i in keys(ref[:gen])] <= ref[:gen][i]["pmax"], start = ref[:gen][i]["pg"])
    @variable(model, ref[:gen][i]["qmin"] <= qg[i in keys(ref[:gen])] <= ref[:gen][i]["qmax"], start = ref[:gen][i]["qg"])

    p_dc = Dict(); q_dc = Dict()
    for (l, dcline) in ref[:dcline]
        f = dcline["f_bus"]; t = dcline["t_bus"]
        p_dc[(l, f, t)] = @variable(model, start = dcline["pf"])
        p_dc[(l, t, f)] = @variable(model, start = dcline["pt"])
        q_dc[(l, f, t)] = @variable(model, start = dcline["qf"])
        q_dc[(l, t, f)] = @variable(model, start = dcline["qt"])
        fix(p_dc[(l, f, t)], dcline["pf"]; force = true)
        fix(p_dc[(l, t, f)], dcline["pt"]; force = true)
        fix(q_dc[(l, f, t)], dcline["qf"]; force = true)
        fix(q_dc[(l, t, f)], dcline["qt"]; force = true)
    end

    for (i, gen) in ref[:gen]
        if gen["gen_bus"] in keys(ref[:ref_buses])
            if has_lower_bound(pg[i]); delete_lower_bound(pg[i]); end
            if has_upper_bound(pg[i]); delete_upper_bound(pg[i]); end
        else
            fix(pg[i], gen["pg"]; force = true)
        end
    end
    for (i, _) in ref[:ref_buses]; fix(va[i], 0.0; force = true); end

    PEN = 1e6
    gen_buses = unique([gen["gen_bus"] for (_, gen) in ref[:gen]])
    @variable(model, sl_v[i in gen_buses], start = 0.0)
    for bus_id in gen_buses
        @constraint(model, vm[bus_id] == ref[:bus][bus_id]["vm"] + sl_v[bus_id])
    end
    @variable(model, sl_d[i in keys(ref[:load])], start = 0.0)

    p = Dict(); q = Dict()
    for (l, branch) in ref[:branch]
        f = branch["f_bus"]; t = branch["t_bus"]
        g, b = PowerModels.calc_branch_y(branch)
        tr, ti = PowerModels.calc_branch_t(branch)
        tm = branch["tap"]
        g_fr = branch["g_fr"]; b_fr = branch["b_fr"]
        g_to = branch["g_to"]; b_to = branch["b_to"]
        p[(l, f, t)] = @NLexpression(model, (g+g_fr)/tm^2*vm[f]^2 + (-g*tr+b*ti)/tm^2*(vm[f]*vm[t]*cos(va[f]-va[t])) + (-b*tr-g*ti)/tm^2*(vm[f]*vm[t]*sin(va[f]-va[t])))
        q[(l, f, t)] = @NLexpression(model, -(b+b_fr)/tm^2*vm[f]^2 - (-b*tr-g*ti)/tm^2*(vm[f]*vm[t]*cos(va[f]-va[t])) + (-g*tr+b*ti)/tm^2*(vm[f]*vm[t]*sin(va[f]-va[t])))
        p[(l, t, f)] = @NLexpression(model, (g+g_to)*vm[t]^2 + (-g*tr-b*ti)/tm^2*(vm[t]*vm[f]*cos(va[t]-va[f])) + (-b*tr+g*ti)/tm^2*(vm[t]*vm[f]*sin(va[t]-va[f])))
        q[(l, t, f)] = @NLexpression(model, -(b+b_to)*vm[t]^2 - (-b*tr+g*ti)/tm^2*(vm[t]*vm[f]*cos(va[t]-va[f])) + (-g*tr-b*ti)/tm^2*(vm[t]*vm[f]*sin(va[t]-va[f])))
    end

    for (i, _) in ref[:bus]
        bus_arcs    = ref[:bus_arcs][i]
        bus_arcs_dc = ref[:bus_arcs_dc][i]
        bus_gens    = ref[:bus_gens][i]
        bus_loads   = ref[:bus_loads][i]
        gs = sum(s["gs"] for (_, s) in ref[:shunt] if s["shunt_bus"] == i; init = 0.0)
        bs = sum(s["bs"] for (_, s) in ref[:shunt] if s["shunt_bus"] == i; init = 0.0)
        pd = sum(l["pd"] for (_, l) in ref[:load] if l["load_bus"] == i; init = 0.0)
        qd = sum(l["qd"] for (_, l) in ref[:load] if l["load_bus"] == i; init = 0.0)
        p_g  = isempty(bus_gens)  ? 0.0 : sum(pg[g] for g in bus_gens)
        q_g  = isempty(bus_gens)  ? 0.0 : sum(qg[g] for g in bus_gens)
        p_dc_t = isempty(bus_arcs_dc) ? 0.0 : sum(p_dc[a] for a in bus_arcs_dc)
        q_dc_t = isempty(bus_arcs_dc) ? 0.0 : sum(q_dc[a] for a in bus_arcs_dc)
        sl_total = isempty(bus_loads) ? 0.0 : sum(sl_d[l] for l in bus_loads)

        @NLconstraint(model, sum(p[a] for a in bus_arcs) + p_dc_t == p_g - pd - gs*vm[i]^2)
        @NLconstraint(model, sum(q[a] for a in bus_arcs) + q_dc_t == q_g - (qd + sl_total) + bs*vm[i]^2)
    end

    @objective(model, Min, PEN*sum(sl_v[i]^2 for i in keys(sl_v)) + PEN*sum(sl_d[l]^2 for l in keys(sl_d)))

    tempo = @elapsed optimize!(model)
    status = termination_status(model)

    df_barras = DataFrame(
        ID_Barra = Int[], Tipo_Barra = Int[],
        Vm_pu = Float64[], Va_graus = Float64[],
        Pg_pu = Float64[], Qg_pu = Float64[],
        Pd_pu = Float64[], Qd_pu = Float64[],
        Slack_QLIM_pu = Float64[], Slack_VLIM_pu = Float64[],
    )

    if status in (LOCALLY_SOLVED, OPTIMAL)
        for (i, bus) in ref[:bus]
            bus_gens  = ref[:bus_gens][i]; bus_loads = ref[:bus_loads][i]
            push!(df_barras, (
                i, bus["bus_type"], value(vm[i]), value(va[i]) * 180/π,
                isempty(bus_gens)  ? 0.0 : sum(value(pg[g]) for g in bus_gens),
                isempty(bus_gens)  ? 0.0 : sum(value(qg[g]) for g in bus_gens),
                isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["pd"] for l in bus_loads),
                isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["qd"] for l in bus_loads),
                (i in gen_buses) ? value(sl_v[i]) : 0.0,
                isempty(bus_loads) ? 0.0 : sum(value(sl_d[l]) for l in bus_loads),
            ))
        end
        sort!(df_barras, :ID_Barra)
        CSV.write(joinpath(PASTA_CSV, "$(case_name)__1617_qv.csv"), df_barras)
    end

    if nrow(df_barras) == 0
        return (status = string(status), tempo = tempo,
                vmin = NaN, vmax = NaN, pg_total = NaN, qg_total = NaN,
                slacks = NaN, n_barras = 0)
    end

    pg_tot = sum(df_barras.Pg_pu)
    qg_tot = sum(df_barras.Qg_pu)
    return (status = string(status), tempo = tempo,
            vmin = minimum(df_barras.Vm_pu),
            vmax = maximum(df_barras.Vm_pu),
            pg_total = pg_tot * base_mva,
            qg_total = qg_tot * base_mva,
            slacks = objective_value(model),
            n_barras = nrow(df_barras))
end

# =========================================================================
# (17) QLIM+VLIM+CSCA (com bs variavel se houver controle)
# =========================================================================
function rodar_csca(caminho_arquivo::String, case_name::String)
    data = PWF.parse_file(caminho_arquivo, add_control_data = true)
    base_mva = get(data, "baseMVA", 100.0)

    PowerModels.select_largest_component!(data)
    PowerModels.standardize_cost_terms!(data, order = 2)
    limpar_chaves_nao_numericas!(data)
    ref = PowerModels.build_ref(data)[:it][:pm][:nw][0]

    model = Model(fazer_solver())

    @variable(model, ref[:bus][i]["vmin"] <= vm[i in keys(ref[:bus])] <= ref[:bus][i]["vmax"], start = ref[:bus][i]["vm"])
    @variable(model, va[i in keys(ref[:bus])], start = ref[:bus][i]["va"])
    @variable(model, ref[:gen][i]["pmin"] <= pg[i in keys(ref[:gen])] <= ref[:gen][i]["pmax"], start = ref[:gen][i]["pg"])
    @variable(model, ref[:gen][i]["qmin"] <= qg[i in keys(ref[:gen])] <= ref[:gen][i]["qmax"], start = ref[:gen][i]["qg"])

    p_dc = Dict(); q_dc = Dict()
    for (l, dcline) in ref[:dcline]
        f = dcline["f_bus"]; t = dcline["t_bus"]
        p_dc[(l, f, t)] = @variable(model, start = dcline["pf"])
        p_dc[(l, t, f)] = @variable(model, start = dcline["pt"])
        q_dc[(l, f, t)] = @variable(model, start = dcline["qf"])
        q_dc[(l, t, f)] = @variable(model, start = dcline["qt"])
        fix(p_dc[(l, f, t)], dcline["pf"]; force = true)
        fix(p_dc[(l, t, f)], dcline["pt"]; force = true)
        fix(q_dc[(l, f, t)], dcline["qf"]; force = true)
        fix(q_dc[(l, t, f)], dcline["qt"]; force = true)
    end

    @variable(model, bs_var[i in keys(ref[:shunt])])
    n_csca_buses = 0
    for (i, shunt) in ref[:shunt]
        bmin = bmax = shunt["bs"]
        if haskey(shunt, "control_data") && haskey(shunt["control_data"], "bsmin")
            bmin = shunt["control_data"]["bsmin"]
            bmax = shunt["control_data"]["bsmax"]
        end
        rmin = min(bmin, bmax, shunt["bs"]); rmax = max(bmin, bmax, shunt["bs"])
        set_lower_bound(bs_var[i], rmin); set_upper_bound(bs_var[i], rmax)
        set_start_value(bs_var[i], shunt["bs"])
        if rmin == rmax
            fix(bs_var[i], shunt["bs"]; force = true)
        else
            n_csca_buses += 1
        end
    end

    for (i, gen) in ref[:gen]
        if gen["gen_bus"] in keys(ref[:ref_buses])
            if has_lower_bound(pg[i]); delete_lower_bound(pg[i]); end
            if has_upper_bound(pg[i]); delete_upper_bound(pg[i]); end
        else
            fix(pg[i], gen["pg"]; force = true)
        end
    end
    for (i, _) in ref[:ref_buses]; fix(va[i], 0.0; force = true); end

    PEN = 1e6
    gen_buses = [gen["gen_bus"] for (_, gen) in ref[:gen]]
    shunt_buses = [s["shunt_bus"] for (_, s) in ref[:shunt]
        if haskey(s, "control_data") && haskey(s["control_data"], "bsmin") && s["control_data"]["bsmin"] != s["control_data"]["bsmax"]]
    controlled_buses = unique(vcat(gen_buses, shunt_buses))

    @variable(model, sl_v[i in controlled_buses], start = 0.0)
    for bus_id in controlled_buses
        @constraint(model, vm[bus_id] == ref[:bus][bus_id]["vm"] + sl_v[bus_id])
    end
    @variable(model, sl_d[i in keys(ref[:load])], start = 0.0)

    p = Dict(); q = Dict()
    for (l, branch) in ref[:branch]
        f = branch["f_bus"]; t = branch["t_bus"]
        g, b = PowerModels.calc_branch_y(branch)
        tr, ti = PowerModels.calc_branch_t(branch)
        tm = branch["tap"]
        g_fr = branch["g_fr"]; b_fr = branch["b_fr"]
        g_to = branch["g_to"]; b_to = branch["b_to"]
        p[(l, f, t)] = @NLexpression(model, (g+g_fr)/tm^2*vm[f]^2 + (-g*tr+b*ti)/tm^2*(vm[f]*vm[t]*cos(va[f]-va[t])) + (-b*tr-g*ti)/tm^2*(vm[f]*vm[t]*sin(va[f]-va[t])))
        q[(l, f, t)] = @NLexpression(model, -(b+b_fr)/tm^2*vm[f]^2 - (-b*tr-g*ti)/tm^2*(vm[f]*vm[t]*cos(va[f]-va[t])) + (-g*tr+b*ti)/tm^2*(vm[f]*vm[t]*sin(va[f]-va[t])))
        p[(l, t, f)] = @NLexpression(model, (g+g_to)*vm[t]^2 + (-g*tr-b*ti)/tm^2*(vm[t]*vm[f]*cos(va[t]-va[f])) + (-b*tr+g*ti)/tm^2*(vm[t]*vm[f]*sin(va[t]-va[f])))
        q[(l, t, f)] = @NLexpression(model, -(b+b_to)*vm[t]^2 - (-b*tr+g*ti)/tm^2*(vm[t]*vm[f]*cos(va[t]-va[f])) + (-g*tr-b*ti)/tm^2*(vm[t]*vm[f]*sin(va[t]-va[f])))
    end

    for (i, _) in ref[:bus]
        bus_arcs    = ref[:bus_arcs][i]
        bus_arcs_dc = ref[:bus_arcs_dc][i]
        bus_gens    = ref[:bus_gens][i]
        bus_loads   = ref[:bus_loads][i]
        bus_shunts  = [k for (k, s) in ref[:shunt] if s["shunt_bus"] == i]
        pd = sum(l["pd"] for (_, l) in ref[:load] if l["load_bus"] == i; init = 0.0)
        qd = sum(l["qd"] for (_, l) in ref[:load] if l["load_bus"] == i; init = 0.0)
        p_g    = isempty(bus_gens) ? 0.0 : sum(pg[g] for g in bus_gens)
        q_g    = isempty(bus_gens) ? 0.0 : sum(qg[g] for g in bus_gens)
        p_dc_t = isempty(bus_arcs_dc) ? 0.0 : sum(p_dc[a] for a in bus_arcs_dc)
        q_dc_t = isempty(bus_arcs_dc) ? 0.0 : sum(q_dc[a] for a in bus_arcs_dc)
        sl_total = isempty(bus_loads) ? 0.0 : sum(sl_d[l] for l in bus_loads)
        gs_tot = isempty(bus_shunts) ? 0.0 : sum(ref[:shunt][k]["gs"] for k in bus_shunts)

        @NLconstraint(model, sum(p[a] for a in bus_arcs) + p_dc_t == p_g - pd - gs_tot*vm[i]^2)
        if isempty(bus_shunts)
            @NLconstraint(model, sum(q[a] for a in bus_arcs) + q_dc_t == q_g - (qd + sl_total))
        else
            @NLconstraint(model, sum(q[a] for a in bus_arcs) + q_dc_t == q_g - (qd + sl_total) + sum(bs_var[k]*vm[i]^2 for k in bus_shunts))
        end
    end

    @objective(model, Min, PEN*sum(sl_v[i]^2 for i in keys(sl_v)) + PEN*sum(sl_d[l]^2 for l in keys(sl_d)))

    tempo = @elapsed optimize!(model)
    status = termination_status(model)

    df_barras = DataFrame(
        ID_Barra = Int[], Tipo_Barra = Int[],
        Vm_pu = Float64[], Va_graus = Float64[],
        Pg_pu = Float64[], Qg_pu = Float64[],
        Pd_pu = Float64[], Qd_pu = Float64[],
        Slack_QLIM_pu = Float64[], Slack_VLIM_pu = Float64[],
    )

    if status in (LOCALLY_SOLVED, OPTIMAL)
        for (i, bus) in ref[:bus]
            bus_gens  = ref[:bus_gens][i]; bus_loads = ref[:bus_loads][i]
            push!(df_barras, (
                i, bus["bus_type"], value(vm[i]), value(va[i]) * 180/π,
                isempty(bus_gens)  ? 0.0 : sum(value(pg[g]) for g in bus_gens),
                isempty(bus_gens)  ? 0.0 : sum(value(qg[g]) for g in bus_gens),
                isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["pd"] for l in bus_loads),
                isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["qd"] for l in bus_loads),
                (i in keys(sl_v)) ? value(sl_v[i]) : 0.0,
                isempty(bus_loads) ? 0.0 : sum(value(sl_d[l]) for l in bus_loads),
            ))
        end
        sort!(df_barras, :ID_Barra)
        CSV.write(joinpath(PASTA_CSV, "$(case_name)__1617_csca.csv"), df_barras)
    end

    if nrow(df_barras) == 0
        return (status = string(status), tempo = tempo,
                vmin = NaN, vmax = NaN, pg_total = NaN, qg_total = NaN,
                slacks = NaN, n_barras = 0, n_csca = n_csca_buses)
    end

    pg_tot = sum(df_barras.Pg_pu)
    qg_tot = sum(df_barras.Qg_pu)
    return (status = string(status), tempo = tempo,
            vmin = minimum(df_barras.Vm_pu),
            vmax = maximum(df_barras.Vm_pu),
            pg_total = pg_tot * base_mva,
            qg_total = qg_tot * base_mva,
            slacks = objective_value(model),
            n_barras = nrow(df_barras),
            n_csca = n_csca_buses)
end

# =========================================================================
# LOOP PRINCIPAL
# =========================================================================

arquivos = String[]
for (root, _, files) in walkdir(PASTA_DADOS)
    for f in files
        if endswith(lowercase(f), ".pwf")
            push!(arquivos, joinpath(root, f))
        end
    end
end
sort!(arquivos)

resumo = DataFrame(
    Caso = String[], Formulacao = String[],
    Status = String[], Tempo_s = Float64[],
    Vmin_pu = Float64[], Vmax_pu = Float64[],
    Pg_total_MW = Float64[], Qg_total_MVAr = Float64[],
    Slacks = Float64[], N_Barras = Int[], N_CSCA = Int[],
)

println("\n>>> Iniciando bateria de testes em $(length(arquivos)) arquivos .pwf ...\n")

for arquivo in arquivos
    case = replace(splitext(basename(arquivo))[1], r"[^A-Za-z0-9_]" => "_")
    println("="^70)
    println("CASO: $case  ($(arquivo))")
    println("="^70)

    println("--- (15) PowerModels run_ac_pf ---")
    try
        r = rodar_pm(arquivo, case)
        push!(resumo, (case, "(15) PM", r.status, r.tempo,
                       r.vmin, r.vmax, r.pg_total, r.qg_total,
                       r.slacks, r.n_barras, 0))
        println("   status=$(r.status), tempo=$(round(r.tempo, digits=3))s")
    catch e
        push!(resumo, (case, "(15) PM", "ERRO: $(typeof(e))", NaN,
                       NaN, NaN, NaN, NaN, NaN, 0, 0))
        println("   ERRO: $e")
    end

    println("--- (16) QLIM+VLIM ---")
    try
        r = rodar_qlim_vlim(arquivo, case)
        push!(resumo, (case, "(16) QLIM+VLIM", r.status, r.tempo,
                       r.vmin, r.vmax, r.pg_total, r.qg_total,
                       r.slacks, r.n_barras, 0))
        println("   status=$(r.status), tempo=$(round(r.tempo, digits=3))s, slacks=$(round(r.slacks, digits=2))")
    catch e
        push!(resumo, (case, "(16) QLIM+VLIM", "ERRO: $(typeof(e))", NaN,
                       NaN, NaN, NaN, NaN, NaN, 0, 0))
        println("   ERRO: $e")
    end

    println("--- (17) QLIM+VLIM+CSCA ---")
    try
        r = rodar_csca(arquivo, case)
        push!(resumo, (case, "(17) CSCA", r.status, r.tempo,
                       r.vmin, r.vmax, r.pg_total, r.qg_total,
                       r.slacks, r.n_barras, r.n_csca))
        println("   status=$(r.status), tempo=$(round(r.tempo, digits=3))s, slacks=$(round(r.slacks, digits=2)), n_csca=$(r.n_csca)")
    catch e
        push!(resumo, (case, "(17) CSCA", "ERRO: $(typeof(e))", NaN,
                       NaN, NaN, NaN, NaN, NaN, 0, 0))
        println("   ERRO: $e")
    end
end

CSV.write(joinpath(PASTA_CSV, "sumario_runner.csv"), resumo)
println("\n>>> SUMÁRIO salvo em $(joinpath(PASTA_CSV, "sumario_runner.csv"))")
println(">>> CSVs por caso salvos em $PASTA_CSV")
