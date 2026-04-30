# =========================================================================
# FLUXO DE POTÊNCIA ÓTIMO - FORMULAÇÃO AC POLAR (QLIM + VLIM)
# Especialização para Grandes Redes (SIN) com Soft-Constraints Nodais
# =========================================================================

using PWF
using PowerModels
using JuMP
using Ipopt
using CSV
using DataFrames

print("\033c") # Limpa o terminal/ecrã

# Pasta dedicada aos CSVs (criada automaticamente se não existir)
PASTA_CSV = joinpath(@__DIR__, "resultados_csv")
mkpath(PASTA_CSV)

# =========================================================================
# 0. LEITURA DE DADOS E TOPOLOGIA
# =========================================================================
println("1. Lendo ficheiro PWF...")
caminho_arquivo = joinpath(@__DIR__, "01 MAXIMA NOTURNA_DEZ25.PWF")

data = PWF.parse_file(caminho_arquivo)
base_mva = data["baseMVA"]

# Remove ilhas isoladas para manter a matriz Jacobiana não-singular
PowerModels.select_largest_component!(data)
println("-> Ilhas isoladas removidas! Mantendo apenas a rede principal conectada.")

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
# 2. VARIÁVEIS DE ESTADO FÍSICO COM WARM START
# =========================================================================
println("2. Criando variáveis de estado...")

# Definindo limites de segurança rígidos para TODAS as barras
v_min_global = 0.95
v_max_global = 1.05

@variable(model, v_min_global <= vm[i in keys(ref[:bus])] <= v_max_global, start=ref[:bus][i]["vm"])
@variable(model, va[i in keys(ref[:bus])], start=ref[:bus][i]["va"])

@variable(model, ref[:gen][i]["pmin"] <= pg[i in keys(ref[:gen])] <= ref[:gen][i]["pmax"], start=ref[:gen][i]["pg"])
@variable(model, ref[:gen][i]["qmin"] <= qg[i in keys(ref[:gen])] <= ref[:gen][i]["qmax"], start=ref[:gen][i]["qg"])

# =========================================================================
# 3. LÓGICA DO FLUXO DE POTÊNCIA (Barras Slack e PV)
# =========================================================================
for (i, gen) in ref[:gen]
    bus_id = gen["gen_bus"]
    if bus_id in keys(ref[:ref_buses])
        # É barra Slack: O Pg fica livre para absorver as perdas do sistema
        if has_lower_bound(pg[i]); delete_lower_bound(pg[i]); end
        if has_upper_bound(pg[i]); delete_upper_bound(pg[i]); end
    else
        # É barra PV: O Pg é rigidamente fixado ao valor despachado
        fix(pg[i], gen["pg"]; force=true)
    end
end

for (i, bus) in ref[:ref_buses]
    # FIX: Trava os ângulos de referência nos valores do caso base (evita conflito HVDC/Defasadores)
    fix(va[i], ref[:bus][i]["va"]; force=true)
end

# =========================================================================
# 4. VARIÁVEIS DE CONTROLE: QLIM E VLIM (CORRIGIDO)
# =========================================================================
PENALIDADE = 1e6 

# QLIM: Mapeia apenas as barras que contêm geradores (evita redundância de equações)
gen_buses = unique([gen["gen_bus"] for (i,gen) in ref[:gen]])
@variable(model, sl_v[i in gen_buses], start=0.0) # Slack do QLIM

# FIX: Aplica a restrição de tensão 1 única vez por barra geradora
for bus_id in gen_buses
    vm_setpoint = ref[:bus][bus_id]["vm"] 
    @constraint(model, vm[bus_id] == vm_setpoint + sl_v[bus_id])
end

# VLIM: Slack de injeção reativa nodal universal (Aplicável a todas as barras, com ou sem carga)
@variable(model, sl_q[i in keys(ref[:bus])], start=0.0)

# =========================================================================
# 5. EQUAÇÕES DE FLUXO NOS RAMOS (Fidelidade AC Polar)
# =========================================================================
println("3. Montando equações de fluxo de potência (AC Polar)...")

p = Dict(); q = Dict()

for (l, branch) in ref[:branch]
    f = branch["f_bus"]; t = branch["t_bus"]
    g, b = PowerModels.calc_branch_y(branch)
    tr, ti = PowerModels.calc_branch_t(branch)
    tm = branch["tap"]
    g_fr = branch["g_fr"]; b_fr = branch["b_fr"]
    g_to = branch["g_to"]; b_to = branch["b_to"]

    # Expressões (Nó de Envio - from)
    p[(l, f, t)] = @NLexpression(model, (g+g_fr)*(vm[f]^2)/tm^2 + (-g*tr+b*ti)/tm^2 * (vm[f]*vm[t]*cos(va[f]-va[t])) + (-b*tr-g*ti)/tm^2 * (vm[f]*vm[t]*sin(va[f]-va[t])))
    q[(l, f, t)] = @NLexpression(model, -(b+b_fr)*(vm[f]^2)/tm^2 - (-b*tr-g*ti)/tm^2 * (vm[f]*vm[t]*cos(va[f]-va[t])) + (-g*tr+b*ti)/tm^2 * (vm[f]*vm[t]*sin(va[f]-va[t])))
    
    # Expressões (Nó de Recebimento - to)
    p[(l, t, f)] = @NLexpression(model, (g+g_to)*(vm[t]^2) + (-g*tr-b*ti)/tm^2 * (vm[t]*vm[f]*cos(va[t]-va[f])) + (-b*tr+g*ti)/tm^2 * (vm[t]*vm[f]*sin(va[t]-va[f])))
    q[(l, t, f)] = @NLexpression(model, -(b+b_to)*(vm[t]^2) - (-b*tr+g*ti)/tm^2 * (vm[t]*vm[f]*cos(va[t]-va[f])) + (-g*tr-b*ti)/tm^2 * (vm[t]*vm[f]*sin(va[t]-va[f])))
end

# =========================================================================
# 6. LEIS DE KIRCHHOFF DOS NÓS (Com injeção nodal direta do VLIM)
# =========================================================================
println("4. Montando balanço nodal (Leis de Kirchhoff)...")
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
    
    # Balanço Ativo
    @NLconstraint(model, sum(p[a] for a in bus_arcs) == p_gen_total - pd_nominal - gs*vm[i]^2)
    
    # FIX: Balanço Reativo com injeção nodal do VLIM (sl_q)
    # Valores positivos de sl_q indicam instalação de bancos de capacitores fictícios
    @NLconstraint(model, sum(q[a] for a in bus_arcs) == q_gen_total - qd_nominal + sl_q[i] + bs*vm[i]^2)
end

# =========================================================================
# 7. FUNÇÃO OBJETIVO DE SOFT-CONSTRAINTS
# =========================================================================
@objective(model, Min, 
    PENALIDADE * sum(sl_v[i]^2 for i in keys(sl_v)) + 
    PENALIDADE * sum(sl_q[i]^2 for i in keys(sl_q))
)

# =========================================================================
# 8. RESOLUÇÃO E ESTATÍSTICAS COMPUTACIONAIS
# =========================================================================
println("5. Resolvendo o Fluxo de Potência Controlado...\n")

tempo_total_execucao = @elapsed optimize!(model)

status_convergencia = termination_status(model)
tempo_solver_interno = solve_time(model)

println("\n--- ESTATÍSTICAS DE RESOLUÇÃO ---")
println("Status da Convergência: ", status_convergencia)
println("Tempo interno do Solver (Ipopt): ", round(tempo_solver_interno, digits=4), " segundos")
println("Tempo total da execução da função: ", round(tempo_total_execucao, digits=4), " segundos")
println("Erro de Controle (Slacks Ponderadas): ", objective_value(model))

# =========================================================================
# 9. EXPORTAÇÃO DOS RESULTADOS PARA CSV
# =========================================================================
println("\n6. Estruturando dados e gerando ficheiros CSV...")

df_barras = DataFrame(
    ID_Barra = Int[], Tipo_Barra = Int[], 
    Tensao_Mag_pu = Float64[], Tensao_Ang_graus = Float64[],
    P_Geracao_pu = Float64[], Q_Geracao_pu = Float64[], 
    P_Carga_pu = Float64[], Q_Carga_pu = Float64[],
    Desvio_Tensao_QLIM_pu = Float64[], Injecao_Reativa_VLIM_pu = Float64[]
)

for (i, bus) in ref[:bus]
    v_m = value(vm[i])
    v_a = value(va[i]) * (180.0 / pi)

    bus_gens = ref[:bus_gens][i]; bus_loads = ref[:bus_loads][i]

    p_gen = isempty(bus_gens) ? 0.0 : sum(value(pg[g]) for g in bus_gens)
    q_gen = isempty(bus_gens) ? 0.0 : sum(value(qg[g]) for g in bus_gens)
    p_load = isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["pd"] for l in bus_loads)
    q_load = isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["qd"] for l in bus_loads)

    slack_tensao = (i in gen_buses) ? value(sl_v[i]) : 0.0
    slack_reativ = value(sl_q[i]) # Agora universal para todas as barras

    push!(df_barras, (i, bus["bus_type"], v_m, v_a, p_gen, q_gen, p_load, q_load, slack_tensao, slack_reativ))
end
CSV.write(joinpath(PASTA_CSV, "resultados_barras_SIN.csv"), df_barras)

df_linhas = DataFrame(
    ID_Linha = Int[], Barra_De = Int[], Barra_Para = Int[],
    P_Fluxo_De_Para_pu = Float64[], Q_Fluxo_De_Para_pu = Float64[],
    P_Fluxo_Para_De_pu = Float64[], Q_Fluxo_Para_De_pu = Float64[],
    Perda_Ativa_pu = Float64[]
)

for (l, branch) in ref[:branch]
    f = branch["f_bus"]; t = branch["t_bus"]
    
    local val_p_from = value(p[(l, f, t)]); local val_q_from = value(q[(l, f, t)])
    local val_p_to   = value(p[(l, t, f)]); local val_q_to   = value(q[(l, t, f)])
    local perdas_p = val_p_from + val_p_to 

    push!(df_linhas, (l, f, t, val_p_from, val_q_from, val_p_to, val_q_to, perdas_p))
end
CSV.write(joinpath(PASTA_CSV, "resultados_fluxos_linhas_SIN.csv"), df_linhas)

# =========================================================================
# 10. RESUMO OPERACIONAL DO SIN
# =========================================================================
println("\n--- RESUMO OPERACIONAL GLOBAL ---")
tensao_min = minimum(df_barras.Tensao_Mag_pu)
tensao_max = maximum(df_barras.Tensao_Mag_pu)
geracao_p_total = sum(df_barras.P_Geracao_pu)
geracao_q_total = sum(df_barras.Q_Geracao_pu)
perda_p_total = sum(df_linhas.Perda_Ativa_pu)

println("Tensão Mínima (pu):         ", round(tensao_min, digits=4))
println("Tensão Máxima (pu):         ", round(tensao_max, digits=4))
println("Geração Ativa Total (pu):   ", round(geracao_p_total, digits=4))
println("Geração Reativa Total (pu): ", round(geracao_q_total, digits=4))
println("Perdas Ativas (Total pu):   ", round(perda_p_total, digits=4))
println("\n--- RESUMO EM UNIDADES REAIS (Base = $base_mva MVA) ---")
println("Geração Ativa Total (MW):   ", round(geracao_p_total * base_mva, digits=2))
println("Geração Reativa Total (MVAr):", round(geracao_q_total * base_mva, digits=2))
println("Perdas Ativas Totais (MW):  ", round(perda_p_total * base_mva, digits=2))