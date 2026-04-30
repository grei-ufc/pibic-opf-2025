using PowerModels
using JuMP
using InfrastructureModels
using Ipopt

# =========================================================================
# 0. INICIALIZAÇÃO
# =========================================================================
data = PowerModels.parse_file("./powerflow/Codes/PowerModels/case5.m")
pm = InitializeInfrastructureModel(ACPPowerModel, data, Set(["per_unit"]), :pm) # Cria a estrutura do modelo de otimização matemática.
ref_add_core!(pm.ref)

nw = PowerModels.nw_id_default 
n  = nw

# =========================================================================
# 1. DECLARAÇÃO DAS VARIÁVEIS DE DECISÃO
# =========================================================================
# Cria variáveis de tensão (vm, va)
PowerModels.variable_bus_voltage(pm) 

# CORREÇÃO: Cria variáveis de geração (pg, qg)
PowerModels.variable_gen_power(pm)   

# Cria variáveis de fluxo nos ramos (p, q)
PowerModels.variable_branch_power(pm)

# =========================================================================
# 2. RECUPERANDO VARIÁVEIS
# =========================================================================
vm   = PowerModels.var(pm, n, :vm) #Magnitude de tensão
va   = PowerModels.var(pm, n, :va) #Ângulo de tensão
p    = get(PowerModels.var(pm, n), :p, Dict()) #Potência Ativa
q    = get(PowerModels.var(pm, n), :q, Dict()) #Potência Reatiava
pg   = get(PowerModels.var(pm, n), :pg, Dict()) #Potência Ativa Gerada
qg   = get(PowerModels.var(pm, n), :qg, Dict()) #Potência Reativa Gerada
ps   = get(PowerModels.var(pm, n), :ps, Dict()) #Potência...
qs   = get(PowerModels.var(pm, n), :qs, Dict())
psw  = get(PowerModels.var(pm, n), :psw, Dict())
qsw  = get(PowerModels.var(pm, n), :qsw, Dict())
p_dc = get(PowerModels.var(pm, n), :p_dc, Dict())
q_dc = get(PowerModels.var(pm, n), :q_dc, Dict())

# =========================================================================
# 3. RESTRIÇÕES NODAL
# =========================================================================
for (i, bus) in PowerModels.ref(pm, nw, :bus)
    bus_arcs    = PowerModels.ref(pm, nw, :bus_arcs, i)
    bus_arcs_dc = PowerModels.ref(pm, nw, :bus_arcs_dc, i)
    bus_arcs_sw = PowerModels.ref(pm, nw, :bus_arcs_sw, i)
    bus_gens    = PowerModels.ref(pm, nw, :bus_gens, i)
    bus_loads   = PowerModels.ref(pm, nw, :bus_loads, i)
    bus_shunts  = PowerModels.ref(pm, nw, :bus_shunts, i)
    bus_storage = PowerModels.ref(pm, nw, :bus_storage, i)

    bus_pd = sum(PowerModels.ref(pm, nw, :load, k, "pd") for k in bus_loads; init=0.0)
    bus_qd = sum(PowerModels.ref(pm, nw, :load, k, "qd") for k in bus_loads; init=0.0)
    bus_gs = sum(PowerModels.ref(pm, nw, :shunt, k, "gs") for k in bus_shunts; init=0.0)
    bus_bs = sum(PowerModels.ref(pm, nw, :shunt, k, "bs") for k in bus_shunts; init=0.0)

    # Equação 8.1 (Potência Ativa)
    JuMP.@constraint(pm.model,
        sum(p[a] for a in bus_arcs)
        + sum(p_dc[a_dc] for a_dc in bus_arcs_dc)
        + sum(psw[a_sw] for a_sw in bus_arcs_sw)
        ==
        sum(pg[g] for g in bus_gens)
        - sum(ps[s] for s in bus_storage)
        - bus_pd
        - bus_gs * vm[i]^2
    )

    # Equação 8.2 (Potência Reativa)   
    JuMP.@constraint(pm.model,
        sum(q[a] for a in bus_arcs)
        + sum(q_dc[a_dc] for a_dc in bus_arcs_dc)
        + sum(qsw[a_sw] for a_sw in bus_arcs_sw)
        ==
        sum(qg[g] for g in bus_gens)
        - sum(qs[s] for s in bus_storage)
        - bus_qd
        + bus_bs * vm[i]^2
    )
end

# =========================================================================
# 4. RESTRIÇÕES DE RAMOS (Corrigido para @NLconstraint)
# =========================================================================
for (i, branch) in PowerModels.ref(pm, nw, :branch)
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    g, b = PowerModels.calc_branch_y(branch) #Condutância e Susceptância da linha (parte real e imaginária da Admitância Y_ij)
    tr, ti = PowerModels.calc_branch_t(branch)
    
    # É boa prática extrair os parâmetros para variáveis locais simples 
    # para garantir que o JuMP capture o valor numérico, não a referência.
    g_fr = branch["g_fr"] #Admitância shunt (capacitância/perdas para terra) no lado de origem "From" Y_{ij}^c)
    b_fr = branch["b_fr"] #///
    g_to = branch["g_to"]
    b_to = branch["b_to"]
    tm   = branch["tap"]

    # ATENÇÃO: Variáveis dentro de @NLconstraint devem ser referenciadas diretamente.
    # O uso de dicionários p[...] dentro da macro NL às vezes requer cuidado,
    # mas geralmente funciona se os índices forem números.
    
    # Equações de Fluxo Ativo e Reativo (Origem -> Destino) (Equação 9)
    JuMP.@NLconstraint(pm.model, p[f_idx] ==  
        (g+g_fr)/tm^2 * vm[f_bus]^2 + 
        (-g*tr+b*ti)/tm^2 * (vm[f_bus]*vm[t_bus]*cos(va[f_bus]-va[t_bus])) + 
        (-b*tr-g*ti)/tm^2 * (vm[f_bus]*vm[t_bus]*sin(va[f_bus]-va[t_bus])) 
    )
    
    JuMP.@NLconstraint(pm.model, q[f_idx] == 
        -(b+b_fr)/tm^2 * vm[f_bus]^2 - 
        (-b*tr-g*ti)/tm^2 * (vm[f_bus]*vm[t_bus]*cos(va[f_bus]-va[t_bus])) + 
        (-g*tr+b*ti)/tm^2 * (vm[f_bus]*vm[t_bus]*sin(va[f_bus]-va[t_bus])) 
    )

    # Equações de Fluxo Ativo e Reativo (Destino -> Origem) (Equação 10)
    JuMP.@NLconstraint(pm.model, p[t_idx] ==  
        (g+g_to) * vm[t_bus]^2 + 
        (-g*tr-b*ti)/tm^2 * (vm[t_bus]*vm[f_bus]*cos(va[t_bus]-va[f_bus])) + 
        (-b*tr+g*ti)/tm^2 * (vm[t_bus]*vm[f_bus]*sin(va[t_bus]-va[f_bus])) 
    )
    
    JuMP.@NLconstraint(pm.model, q[t_idx] == 
        -(b+b_to) * vm[t_bus]^2 - 
        (-b*tr+g*ti)/tm^2 * (vm[t_bus]*vm[f_bus]*cos(va[t_bus]-va[f_bus])) + 
        (-g*tr-b*ti)/tm^2 * (vm[t_bus]*vm[f_bus]*sin(va[t_bus]-va[f_bus])) 
    )

    # Limite Térmico (Aparente) - Isso é quadrático, então @constraint funciona,
    # mas @NLconstraint também aceita. Manteremos @constraint por ser mais eficiente se for convexo.
    # Equação 11 e 12
    if haskey(branch, "rate_a")
        rate_a = branch["rate_a"] 
        JuMP.@constraint(pm.model, p[f_idx]^2 + q[f_idx]^2 <= rate_a^2)
        JuMP.@constraint(pm.model, p[t_idx]^2 + q[t_idx]^2 <= rate_a^2)
    end

    # Limites Angulares (Lineares) - Use @constraint (Equação 13)
    JuMP.@constraint(pm.model, branch["angmin"] <= va[f_bus] - va[t_bus])
    JuMP.@constraint(pm.model, va[f_bus] - va[t_bus] <= branch["angmax"])
end

# =========================================================================
# 5. RESTRIÇÃO DA BARRA DE REFERÊNCIA (SLACK BUS) - MUITO IMPORTANTE!
# =========================================================================
for (i, bus) in PowerModels.ref(pm, nw, :ref_buses) #Esta função busca dentro dos dados do modelo quais barras foram marcadas como "tipo 3" (código padrão para Slack Bus no formato MATPOWER/IEEE)
    JuMP.@constraint(pm.model, va[i] == bus["va"]) #Cria uma restrição de igualdade.
end

# =========================================================================
# 6. FUNÇÃO OBJETIVO E OTIMIZAÇÃO
# =========================================================================
custo_total = JuMP.AffExpr(0.0)

for (i, gen) in PowerModels.ref(pm, nw, :gen)
    cost_pts = gen["cost"]
    if length(cost_pts) == 3
        c2, c1, c0 = cost_pts[1], cost_pts[2], cost_pts[3]
        JuMP.add_to_expression!(custo_total, c2*pg[i]^2 + c1*pg[i] + c0)
    elseif length(cost_pts) == 2
        c1, c0 = cost_pts[1], cost_pts[2]
        JuMP.add_to_expression!(custo_total, c1*pg[i] + c0)
    end
end

JuMP.@objective(pm.model, Min, custo_total)

println("Problema montado! Resolvendo com Ipopt...\n")
JuMP.set_optimizer(pm.model, Ipopt.Optimizer)
JuMP.optimize!(pm.model)

status = JuMP.termination_status(pm.model)
println("Status: ", status)
if status == JuMP.LOCALLY_SOLVED || status == JuMP.OPTIMAL
    println("Custo (Nosso): \$", round(JuMP.objective_value(pm.model), digits=2))
end

# Benchmark
resultado_pm = PowerModels.solve_opf(data, ACPPowerModel, Ipopt.Optimizer)
println("Custo (PM Oficial): \$", round(resultado_pm["objective"], digits=2))