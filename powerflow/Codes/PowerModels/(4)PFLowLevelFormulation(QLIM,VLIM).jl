using PowerModels
using JuMP
using Ipopt
print("\033c")

# =========================================================================
# 0. INICIALIZAÇÃO E DADOS
# =========================================================================
# DICA: Para testar QLIM/VLIM, use um caso onde os limites sejam "apertados".
data = PowerModels.parse_file("./powerflow/Codes/PowerModels/case5.m") # Certifique-se que o caminho está correto
PowerModels.standardize_cost_terms!(data, order=2)
PowerModels.calc_thermal_limits!(data)
ref = PowerModels.build_ref(data)[:it][:pm][:nw][0]

# Inicializa o modelo JuMP vazio
model = Model(Ipopt.Optimizer)

# =========================================================================
# 1. VARIÁVEIS DE ESTADO DO SISTEMA (Tensão e Geração)
# =========================================================================
# Tensão (Magnitude e Ângulo)
# Nota: Definimos limites base, mas o VLIM/QLIM atuará sobre eles
vm = @variable(model, ref[:bus][i]["vmin"] <= vm[i in keys(ref[:bus])] <= ref[:bus][i]["vmax"], start=1.0)
va = @variable(model, va[i in keys(ref[:bus])], start=0.0)

# Geração Ativa e Reativa
pg = @variable(model, ref[:gen][i]["pmin"] <= pg[i in keys(ref[:gen])] <= ref[:gen][i]["pmax"])
qg = @variable(model, ref[:gen][i]["qmin"] <= qg[i in keys(ref[:gen])] <= ref[:gen][i]["qmax"])

# =========================================================================
# 2. VARIÁVEIS DE CONTROLE (SLACKS) - O Coração do ControlPowerFlow
# =========================================================================
# Fator de penalidade (Peso na função objetivo)
PENALIDADE = 1e6 

# QLIM: Slack de tensão para barras PV (Gen Bus)
# Conforme Eq 1.3: v = v_spec + sl_v
# Apenas para geradores que controlam tensão (geralmente PV e Slack)
gen_buses = [gen["gen_bus"] for (i,gen) in ref[:gen]]
unique_gen_buses = unique(gen_buses)
sl_v = @variable(model, sl_v[i in unique_gen_buses], start=0.0) 

# VLIM: Slack de carga reativa para barras PQ (Load Bus)
# Conforme Eq 2.4: q_d = q_d_spec + sl_d
# Identificamos cargas em barras PQ
load_buses = [load["load_bus"] for (i,load) in ref[:load]]
sl_d = @variable(model, sl_d[i in keys(ref[:load])], start=0.0)

# =========================================================================
# 3. EXPRESSÕES DE FLUXO DE POTÊNCIA (Formulação Polar ACP)
# =========================================================================
p = Dict()
q = Dict()

for (l, branch) in ref[:branch]
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    
    g, b = PowerModels.calc_branch_y(branch)
    tr, ti = PowerModels.calc_branch_t(branch)
    tm = branch["tap"]
    
    g_fr = branch["g_fr"]
    b_fr = branch["b_fr"]
    g_to = branch["g_to"]
    b_to = branch["b_to"]

    # Fluxo Ativo e Reativo (From -> To) 
    p[(l, f_bus, t_bus)] = @NLexpression(model,
        (g+g_fr)/tm^2 * vm[f_bus]^2 + 
        (-g*tr+b*ti)/tm^2 * (vm[f_bus]*vm[t_bus]*cos(va[f_bus]-va[t_bus])) + 
        (-b*tr-g*ti)/tm^2 * (vm[f_bus]*vm[t_bus]*sin(va[f_bus]-va[t_bus]))
    )
    q[(l, f_bus, t_bus)] = @NLexpression(model,
        -(b+b_fr)/tm^2 * vm[f_bus]^2 - 
        (-b*tr-g*ti)/tm^2 * (vm[f_bus]*vm[t_bus]*cos(va[f_bus]-va[t_bus])) + 
        (-g*tr+b*ti)/tm^2 * (vm[f_bus]*vm[t_bus]*sin(va[f_bus]-va[t_bus]))
    )

    # Fluxo Ativo e Reativo (To -> From) 
    p[(l, t_bus, f_bus)] = @NLexpression(model,
        (g+g_to) * vm[t_bus]^2 + 
        (-g*tr-b*ti)/tm^2 * (vm[t_bus]*vm[f_bus]*cos(va[t_bus]-va[f_bus])) + 
        (-b*tr+g*ti)/tm^2 * (vm[t_bus]*vm[f_bus]*sin(va[t_bus]-va[f_bus]))
    )
    q[(l, t_bus, f_bus)] = @NLexpression(model,
        -(b+b_to) * vm[t_bus]^2 - 
        (-b*tr+g*ti)/tm^2 * (vm[t_bus]*vm[f_bus]*cos(va[t_bus]-va[f_bus])) + 
        (-g*tr-b*ti)/tm^2 * (vm[t_bus]*vm[f_bus]*sin(va[t_bus]-va[f_bus]))
    )
end

# =========================================================================
# 4. RESTRIÇÕES DE BALANÇO DE POTÊNCIA (Com Lógica VLIM)
# =========================================================================
for (i, bus) in ref[:bus]
    # Recupera conexões da barra
    bus_arcs = ref[:bus_arcs][i]
    bus_gens = ref[:bus_gens][i]
    bus_loads = ref[:bus_loads][i]
    bus_shunts = ref[:bus_shunts][i]

    # Cálculos de Shunt Fixo
    gs = sum(shunt["gs"] for (k,shunt) in ref[:shunt] if shunt["shunt_bus"] == i; init=0.0)
    bs = sum(shunt["bs"] for (k,shunt) in ref[:shunt] if shunt["shunt_bus"] == i; init=0.0)

    # Balanço de Potência Ativa (P)
    # Pd é fixo (não tem slack no modelo proposto pelo Iago para Pd, apenas Qd para VLIM)
    pd = sum(load["pd"] for (k,load) in ref[:load] if load["load_bus"] == i; init=0.0)
    
    @NLconstraint(model,
        sum(p[a] for a in bus_arcs) ==
        sum(pg[g] for g in bus_gens) - pd - gs*vm[i]^2
    )

    # Balanço de Potência Reativa (Q) - AQUI ENTRA O VLIM
    # Qd nominal
    qd_nominal = sum(load["qd"] for (k,load) in ref[:load] if load["load_bus"] == i; init=0.0)
    
    # Adiciona a slack VLIM se houver carga nesta barra
    # Eq 2.4: q_consumido = q_nominal + slack 
    # No balanço: Geração - Carga = Fluxo
    # Geração - (q_nominal + slack) = Fluxo
    slack_term = 0.0
    if !isempty(bus_loads)
        # Somamos as slacks de todas as cargas conectadas nesta barra
        slack_term = sum(sl_d[l] for l in bus_loads)
    end

    @NLconstraint(model,
        sum(q[a] for a in bus_arcs) ==
        sum(qg[g] for g in bus_gens) - (qd_nominal + slack_term) + bs*vm[i]^2
    )
end

# =========================================================================
# 5. RESTRIÇÕES ESPECÍFICAS DE CONTROLE (QLIM)
# =========================================================================
# Barras de Referência (Slack Bus) - Ângulo zero
for (i, bus) in ref[:ref_buses]
    @constraint(model, va[i] == 0)
end

# Controle de Tensão em Geradores (QLIM)
# Eq 1.3: vm = vm_spec + sl_v 
# Isso substitui a fixação rígida da tensão em barras PV
for (i, gen) in ref[:gen]
    bus_id = gen["gen_bus"]
    # Valor de setpoint definido no arquivo (geralmente vm de partida)
    vm_setpoint = ref[:bus][bus_id]["vm"] 
    
    # Aplicamos a restrição relaxada
    @constraint(model, vm[bus_id] == vm_setpoint + sl_v[bus_id])
end

# =========================================================================
# 6. FUNÇÃO OBJETIVO
# =========================================================================
# Custo de Geração + Penalização das Slacks (Quadrática para evitar desvios desnecessários)
# Custo = Custo_Gen + ρ * (sum(sl_v^2) + sum(sl_d^2))

custo_gen = JuMP.AffExpr(0.0)
for (i, gen) in ref[:gen]
    cost = gen["cost"]
    if length(cost) >= 2
        add_to_expression!(custo_gen, cost[1]*pg[i] + cost[2]) # Linearização simples ou termo quadrático
    end
end

# Termos de penalidade quadráticos
# O objetivo é minimizar o uso das slacks.
@objective(model, Min, 
    custo_gen + 
    PENALIDADE * sum(sl_v[i]^2 for i in keys(sl_v)) + 
    PENALIDADE * sum(sl_d[l]^2 for l in keys(sl_d))
)

# =========================================================================
# 7. RESOLUÇÃO
# =========================================================================
optimize!(model)

println("Status: ", termination_status(model))
println("Custo Total: ", objective_value(model))

# Exibir uso das slacks (Diagnóstico de Controle)
println("\n--- Ações de Controle Ativadas ---")
for i in keys(sl_v)
    val = value(sl_v[i])
    if abs(val) > 1e-4
        println("QLIM na Barra $i: Desvio de Tensão = $(round(val, digits=4)) p.u.")
    end
end

for i in keys(sl_d)
    val = value(sl_d[i])
    if abs(val) > 1e-4
        println("VLIM na Carga $i: Corte/Injeção de Q = $(round(val, digits=4)) p.u.")
    end
end