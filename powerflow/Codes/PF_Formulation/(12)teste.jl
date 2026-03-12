using PWF
using PowerModels
using JuMP
using Ipopt
using CSV
using DataFrames

print("\033c")

# =========================================================================
# 0. LEITURA E TOPOLOGIA
# =========================================================================
println("1. Lendo arquivo PWF...")
caminho_arquivo = joinpath(@__DIR__, "01 MAXIMA NOTURNA_DEZ25.PWF")
data = PWF.parse_file(caminho_arquivo)
base_mva = data["baseMVA"]

PowerModels.select_largest_component!(data)
PowerModels.standardize_cost_terms!(data, order=2)
ref = PowerModels.build_ref(data)[:it][:pm][:nw][0]

# =========================================================================
# 1. SOLVER
# =========================================================================
model = Model(optimizer_with_attributes(Ipopt.Optimizer, 
    "max_iter" => 3000, 
    "tol" => 1e-5,
    "print_level" => 5
))

# =========================================================================
# 2. VARIÁVEIS DE ESTADO (A GRANDE SACADA)
# =========================================================================
println("2. Criando variáveis de estado...")

# IGNORAMOS os limites do arquivo e impomos os Procedimentos de Rede (0.95 a 1.05 p.u.) globalmente!
@variable(model, 0.95 <= vm[i in keys(ref[:bus])] <= 1.05, start=ref[:bus][i]["vm"])
@variable(model, va[i in keys(ref[:bus])], start=ref[:bus][i]["va"])

@variable(model, ref[:gen][i]["pmin"] <= pg[i in keys(ref[:gen])] <= ref[:gen][i]["pmax"], start=ref[:gen][i]["pg"])
@variable(model, ref[:gen][i]["qmin"] <= qg[i in keys(ref[:gen])] <= ref[:gen][i]["qmax"], start=ref[:gen][i]["qg"])

# =========================================================================
# 3. MÚLTIPLAS BARRAS SLACK (Para os Elos HVDC)
# =========================================================================
for (i, gen) in ref[:gen]
    bus_id = gen["gen_bus"]
    if bus_id in keys(ref[:ref_buses])
        if has_lower_bound(pg[i]); delete_lower_bound(pg[i]); end
        if has_upper_bound(pg[i]); delete_upper_bound(pg[i]); end
    else
        fix(pg[i], gen["pg"]; force=true)
    end
end

for (i, bus) in ref[:ref_buses]
    fix(va[i], ref[:bus][i]["va"]; force=true) # Cada área AC mantém seu ângulo
end

# =========================================================================
# 4. VARIÁVEIS DE CONTROLE (QLIM e VLIM)
# =========================================================================
PENALIDADE = 1e6 

gen_buses = unique([gen["gen_bus"] for (i,gen) in ref[:gen]])
@variable(model, sl_v[i in gen_buses], start=0.0)
@variable(model, sl_d[i in keys(ref[:load])], start=0.0)

for (i, gen) in ref[:gen]
    bus_id = gen["gen_bus"]
    vm_setpoint = ref[:bus][bus_id]["vm"]
    @constraint(model, vm[bus_id] == vm_setpoint + sl_v[bus_id])
end

# =========================================================================
# 5. EQUAÇÕES DE FLUXO (Sem CTAP, super rápido)
# =========================================================================
println("3. Montando equações de fluxo de potência...")
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

# =========================================================================
# 6. LEIS DE KIRCHHOFF DOS NÓS
# =========================================================================
println("4. Montando balanço nodal...")
for (i, bus) in ref[:bus]
    bus_arcs = ref[:bus_arcs][i]
    bus_gens = ref[:bus_gens][i]
    bus_loads = ref[:bus_loads][i]

    gs = sum(shunt["gs"] for (k,shunt) in ref[:shunt] if shunt["shunt_bus"] == i; init=0.0)
    bs = sum(shunt["bs"] for (k,shunt) in ref[:shunt] if shunt["shunt_bus"] == i; init=0.0)
    pd_nominal = sum(load["pd"] for (k,load) in ref[:load] if load["load_bus"] == i; init=0.0)
    qd_nominal = sum(load["qd"] for (k,load) in ref[:load] if load["load_bus"] == i; init=0.0)

    p_gen_total = isempty(bus_gens) ? 0.0 : sum(pg[g] for g in bus_gens)
    q_gen_total = isempty(bus_gens) ? 0.0 : sum(qg[g] for g in bus_gens)
    slack_vlim  = isempty(bus_loads) ? 0.0 : sum(sl_d[l] for l in bus_loads)

    @NLconstraint(model, sum(p[a] for a in bus_arcs) == p_gen_total - pd_nominal - gs*vm[i]^2)
    @NLconstraint(model, sum(q[a] for a in bus_arcs) == q_gen_total - (qd_nominal + slack_vlim) + bs*vm[i]^2)
end

# =========================================================================
# 7. FUNÇÃO OBJETIVO
# =========================================================================
@objective(model, Min, 
    PENALIDADE * sum(sl_v[i]^2 for i in keys(sl_v)) + 
    PENALIDADE * sum(sl_d[l]^2 for l in keys(sl_d))
)

# =========================================================================
# 8. RESOLUÇÃO E EXPORTAÇÃO
# =========================================================================
println("5. Resolvendo o Fluxo de Potência Controlado...\n")
tempo_total_execucao = @elapsed optimize!(model)

println("\n--- ESTATÍSTICAS DE RESOLUÇÃO ---")
println("Status da Convergência: ", termination_status(model))
println("Erro de Controle (Slacks): ", objective_value(model))

df_barras = DataFrame(ID_Barra=Int[], Tensao_Mag_pu=Float64[], Desvio_Tensao_QLIM_pu=Float64[], Corte_Reativo_VLIM_pu=Float64[])
for (i, bus) in ref[:bus]
    bus_loads = ref[:bus_loads][i]
    push!(df_barras, (i, value(vm[i]), (i in gen_buses) ? value(sl_v[i]) : 0.0, isempty(bus_loads) ? 0.0 : sum(value(sl_d[l]) for l in bus_loads)))
end
CSV.write("resultados_barras_SIN.csv", df_barras)

println("\n--- RESUMO OPERACIONAL GLOBAL ---")
println("Tensão Mínima (pu): ", round(minimum(df_barras.Tensao_Mag_pu), digits=4))
println("Tensão Máxima (pu): ", round(maximum(df_barras.Tensao_Mag_pu), digits=4))