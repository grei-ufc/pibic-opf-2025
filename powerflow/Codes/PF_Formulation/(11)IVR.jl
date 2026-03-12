#IVR

using PWF
using PowerModels
using JuMP
using Ipopt
using CSV
using DataFrames

print("\033c")

# =========================================================================
# 0. LEITURA DE DADOS
# =========================================================================
println("1. Lendo arquivo PWF...")
caminho_arquivo = joinpath(@__DIR__, "01 MAXIMA NOTURNA_DEZ25.PWF")

data = PWF.parse_file(caminho_arquivo)
base_mva = data["baseMVA"]
PowerModels.standardize_cost_terms!(data, order=2)
ref = PowerModels.build_ref(data)[:it][:pm][:nw][0]

# =========================================================================
# 1. INICIALIZAÇÃO DO MODELO E SOLVER
# =========================================================================
model = Model(optimizer_with_attributes(Ipopt.Optimizer, 
    "max_iter" => 3000, 
    "tol" => 1e-5,
    "print_level" => 5
))

# =========================================================================
# 2. VARIÁVEIS DE ESTADO (FORMULAÇÃO IVR)
# =========================================================================
println("2. Criando variáveis de estado (Retangulares)...")

# WARM START: Convertendo Vm e Va do ANAREDE para Vr e Vi
for (i, bus) in ref[:bus]
    bus["vr_start"] = bus["vm"] * cos(bus["va"])
    bus["vi_start"] = bus["vm"] * sin(bus["va"])
end

# Tensões Retangulares (Limitamos pelo vmax para evitar explosão numérica)
@variable(model, -ref[:bus][i]["vmax"] <= vr[i in keys(ref[:bus])] <= ref[:bus][i]["vmax"], start=ref[:bus][i]["vr_start"])
@variable(model, -ref[:bus][i]["vmax"] <= vi[i in keys(ref[:bus])] <= ref[:bus][i]["vmax"], start=ref[:bus][i]["vi_start"])

# Correntes Retangulares nos Ramos (From e To)
@variable(model, cr_fr[l in keys(ref[:branch])], start=0.0)
@variable(model, ci_fr[l in keys(ref[:branch])], start=0.0)
@variable(model, cr_to[l in keys(ref[:branch])], start=0.0)
@variable(model, ci_to[l in keys(ref[:branch])], start=0.0)

# Potências dos Geradores
@variable(model, ref[:gen][i]["pmin"] <= pg[i in keys(ref[:gen])] <= ref[:gen][i]["pmax"], start=ref[:gen][i]["pg"])
@variable(model, ref[:gen][i]["qmin"] <= qg[i in keys(ref[:gen])] <= ref[:gen][i]["qmax"], start=ref[:gen][i]["qg"])

# =========================================================================
# 3. LÓGICA DO FLUXO DE POTÊNCIA
# =========================================================================
for (i, gen) in ref[:gen]
    bus_id = gen["gen_bus"]
    if bus_id in keys(ref[:ref_buses])
        # Barra Slack: Absorve perdas
        if has_lower_bound(pg[i]); delete_lower_bound(pg[i]); end
        if has_upper_bound(pg[i]); delete_upper_bound(pg[i]); end
    else
        # Barra PV: P fixo
        fix(pg[i], gen["pg"]; force=true)
    end
end

for (i, bus) in ref[:ref_buses]
    # Referência angular: vi = 0. Isso trava o eixo imaginário garantindo theta = 0
    fix(vi[i], 0.0; force=true) 
    set_lower_bound(vr[i], 0.0) # Garante que a magnitude seja positiva
end

# =========================================================================
# 4. VARIÁVEIS DE CONTROLE
# =========================================================================
PENALIDADE = 1e6 

gen_buses = unique([gen["gen_bus"] for (i,gen) in ref[:gen]])
@variable(model, sl_v[i in gen_buses], start=0.0)
@variable(model, sl_d[i in keys(ref[:load])], start=0.0)
@variable(model, sl_p[i in keys(ref[:bus])], start=0.0)

for (i, gen) in ref[:gen]
    bus_id = gen["gen_bus"]
    vm_setpoint = ref[:bus][bus_id]["vm"]
    
    # QLIM na IVR: vr^2 + vi^2 = vm^2
    # O Ipopt aceita equações quadráticas perfeitamente!
    @constraint(model, vr[bus_id]^2 + vi[bus_id]^2 == (vm_setpoint + sl_v[bus_id])^2)
end

# =========================================================================
# 5. EQUAÇÕES DOS RAMOS E LEI DE OHM (IVR)
# =========================================================================
println("3. Montando matrizes de admitância e Lei de Ohm...")
p = Dict(); q = Dict()

for (l, branch) in ref[:branch]
    f = branch["f_bus"]; t = branch["t_bus"]
    
    # Extraindo as condutâncias e susceptâncias da matriz Pi equivalente
    g_s, b_s = PowerModels.calc_branch_y(branch)
    g_fr = branch["g_fr"]; b_fr = branch["b_fr"]
    g_to = branch["g_to"]; b_to = branch["b_to"]
    tr, ti = PowerModels.calc_branch_t(branch)
    tm = branch["tap"]

    # Montagem analítica exata da Matriz Y (Real e Imag)
    G11 = (g_s + g_fr) / tm^2;           B11 = (b_s + b_fr) / tm^2
    G22 = (g_s + g_to);                  B22 = (b_s + b_to)
    G12 = -(g_s*tr - b_s*ti) / tm^2;     B12 = -(b_s*tr + g_s*ti) / tm^2
    G21 = -(g_s*tr + b_s*ti) / tm^2;     B21 = -(b_s*tr - g_s*ti) / tm^2

    # A MAGIA DA IVR: As correntes da linha são dadas por um sistema estritamente LINEAR!
    @constraint(model, cr_fr[l] == G11*vr[f] - B11*vi[f] + G12*vr[t] - B12*vi[t])
    @constraint(model, ci_fr[l] == G11*vi[f] + B11*vr[f] + G12*vi[t] + B12*vr[t])
    @constraint(model, cr_to[l] == G22*vr[t] - B22*vi[t] + G21*vr[f] - B21*vi[f])
    @constraint(model, ci_to[l] == G22*vi[t] + B22*vr[t] + G21*vi[f] + B21*vr[f])

    # A potência é o produto da Tensão pela Corrente Complexa Conjugada (Bilinear)
    p[(l, f, t)] = @expression(model, vr[f]*cr_fr[l] + vi[f]*ci_fr[l])
    q[(l, f, t)] = @expression(model, vi[f]*cr_fr[l] - vr[f]*ci_fr[l])
    p[(l, t, f)] = @expression(model, vr[t]*cr_to[l] + vi[t]*ci_to[l])
    q[(l, t, f)] = @expression(model, vi[t]*cr_to[l] - vr[t]*ci_to[l])
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

    # Shunt Power na IVR: Vm^2 se transforma em (vr^2 + vi^2)
    p_shunt = gs * (vr[i]^2 + vi[i]^2)
    q_shunt = -bs * (vr[i]^2 + vi[i]^2)

    # Note o uso de @constraint (nativa do JuMP para bilineares/quadráticas) no lugar de @NLconstraint!
    @constraint(model, sum(p[a] for a in bus_arcs) == p_gen_total + sl_p[i] - pd_nominal - p_shunt)
    @constraint(model, sum(q[a] for a in bus_arcs) == q_gen_total - (qd_nominal + slack_vlim) - q_shunt)
end

# =========================================================================
# 7. FUNÇÃO OBJETIVO
# =========================================================================
@objective(model, Min, 
    PENALIDADE * sum(sl_v[i]^2 for i in keys(sl_v)) + 
    PENALIDADE * sum(sl_d[l]^2 for l in keys(sl_d)) +
    PENALIDADE * sum(sl_p[i]^2 for i in keys(sl_p))
)

# =========================================================================
# 8. RESOLUÇÃO E ESTATÍSTICAS COMPUTACIONAIS
# =========================================================================
println("5. Resolvendo o Fluxo de Potência Controlado (IVR)...\n")

tempo_total_execucao = @elapsed optimize!(model)
status_convergencia = termination_status(model)

println("\n--- ESTATÍSTICAS DE RESOLUÇÃO ---")
println("Status da Convergência: ", status_convergencia)
println("Tempo interno do Solver: ", round(solve_time(model), digits=4), " segundos")
println("Erro de Controle (Slacks Ponderadas): ", objective_value(model))

# =========================================================================
# 9. EXPORTAÇÃO DOS RESULTADOS PARA CSV
# =========================================================================
println("\n6. Estruturando dados...")

df_barras = DataFrame(
    ID_Barra = Int[], Tensao_Mag_pu = Float64[], Tensao_Ang_graus = Float64[],
    P_Geracao_pu = Float64[], Q_Geracao_pu = Float64[], 
    P_Carga_pu = Float64[], Q_Carga_pu = Float64[],
    Desvio_Tensao_QLIM_pu = Float64[], Corte_Reativo_VLIM_pu = Float64[], Falta_Ativa_PLIM_pu = Float64[]
)

for (i, bus) in ref[:bus]
    # Reconstruímos Vm e Va a partir das coordenadas retangulares ótimas
    v_r = value(vr[i]); v_i = value(vi[i])
    v_m = sqrt(v_r^2 + v_i^2)
    v_a = atan(v_i, v_r) * (180.0 / pi)

    bus_gens = ref[:bus_gens][i]; bus_loads = ref[:bus_loads][i]

    p_gen = isempty(bus_gens) ? 0.0 : sum(value(pg[g]) for g in bus_gens)
    q_gen = isempty(bus_gens) ? 0.0 : sum(value(qg[g]) for g in bus_gens)
    p_load = isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["pd"] for l in bus_loads)
    q_load = isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["qd"] for l in bus_loads)

    slack_tensao = (i in gen_buses) ? value(sl_v[i]) : 0.0
    slack_reativ = isempty(bus_loads) ? 0.0 : sum(value(sl_d[l]) for l in bus_loads)
    slack_ativa  = value(sl_p[i])

    push!(df_barras, (i, v_m, v_a, p_gen, q_gen, p_load, q_load, slack_tensao, slack_reativ, slack_ativa))
end

CSV.write("resultados_barras_SIN_IVR.csv", df_barras)

df_linhas = DataFrame(
    ID_Linha = Int[], Barra_De = Int[], Barra_Para = Int[],
    P_Fluxo_De_Para_pu = Float64[], P_Fluxo_Para_De_pu = Float64[], Perda_Ativa_pu = Float64[]
)

for (l, branch) in ref[:branch]
    local val_p_from = value(p[(l, branch["f_bus"], branch["t_bus"])])
    local val_p_to   = value(p[(l, branch["t_bus"], branch["f_bus"])])
    push!(df_linhas, (l, branch["f_bus"], branch["t_bus"], val_p_from, val_p_to, val_p_from + val_p_to))
end

CSV.write("resultados_fluxos_linhas_SIN_IVR.csv", df_linhas)

# =========================================================================
# 10. RESUMO OPERACIONAL DO SIN
# =========================================================================
println("-> Sucesso! Arquivos CSV gerados (Formato IVR).")

tensao_min = minimum(df_barras.Tensao_Mag_pu)
tensao_max = maximum(df_barras.Tensao_Mag_pu)
geracao_p_total = sum(df_barras.P_Geracao_pu)
perda_p_total = sum(df_linhas.Perda_Ativa_pu)

println("\n--- RESUMO OPERACIONAL GLOBAL (IVR) ---")
println("Tensão Mínima (pu):         ", round(tensao_min, digits=4))
println("Tensão Máxima (pu):         ", round(tensao_max, digits=4))
println("Geração Ativa Total (MW):   ", round(geracao_p_total * base_mva, digits=2))
println("Perdas Ativas Totais (MW):  ", round(perda_p_total * base_mva, digits=2))