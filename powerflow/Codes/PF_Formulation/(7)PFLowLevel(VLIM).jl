using PowerModels
using JuMP
using Ipopt
using PWF
using Printf
print("\033c")

# =========================================================================
# 1. LEITURA E PREPARAÇÃO
# =========================================================================
file_name = "01 MAXIMA NOTURNA_DEZ25.PWF"
file_path = joinpath(@__DIR__, file_name)

# Carrega e limpa a rede
data = PWF.parse_pwf_to_powermodels(file_path)
PowerModels.propagate_topology_status!(data)
PowerModels.select_largest_component!(data)
PowerModels.calc_thermal_limits!(data)

ref = PowerModels.build_ref(data)[:it][:pm][:nw][0]

model = Model(Ipopt.Optimizer)
set_optimizer_attribute(model, "print_level", 0) 
set_optimizer_attribute(model, "tol", 1e-4)

# =========================================================================
# 2. DEFINIÇÃO DE VARIÁVEIS
# =========================================================================

# Variáveis de Estado da Rede
# MODIFICAÇÃO VLIM: Retirados os hard bounds (vmin/vmax) da declaração.
# Deixamos limites físicos amplos (0.5 a 1.5) apenas para estabilidade numérica do solver.
@variable(model, 0.5 <= vm[i in keys(ref[:bus])] <= 1.5, start=1.0)
@variable(model, va[i in keys(ref[:bus])], start=0.0)

# Variáveis de Geração
@variable(model, ref[:gen][i]["pmin"] <= pg[i in keys(ref[:gen])] <= ref[:gen][i]["pmax"])
@variable(model, ref[:gen][i]["qmin"] <= qg[i in keys(ref[:gen])] <= ref[:gen][i]["qmax"])

# --- VARIÁVEIS DE CONTROLE (SLACKS) ---

# 1. SLACK DE TENSÃO (QLIM Manual)
gen_buses = unique([gen["gen_bus"] for (i,gen) in ref[:gen]])
@variable(model, sl_v[i in gen_buses], start=0.0) 

# 2. SLACKS DE LIMITES DE TENSÃO (VLIM Manual)
# Variáveis positivas que assumem valor apenas se a tensão sair dos limites
@variable(model, sl_vmin[i in keys(ref[:bus])] >= 0.0, start=0.0)
@variable(model, sl_vmax[i in keys(ref[:bus])] >= 0.0, start=0.0)

# Penalidades
PENALIDADE_V = 1e6    # Penalidade para desvio do setpoint PV (QLIM)
PENALIDADE_VLIM = 1e5 # Penalidade para violação de limites nas barras PQ/PV

# =========================================================================
# 3. RESTRIÇÕES DE FIXAÇÃO E LIMITES
# =========================================================================

# Identifica barra de referência (Slack Bus)
slack_bus_idx = [i for (i, bus) in ref[:bus] if bus["bus_type"] == 3]

for (i, gen) in ref[:gen]
    bus_id = gen["gen_bus"]
    
    if !(bus_id in slack_bus_idx)
        fix(pg[i], gen["pg"]; force=true)
    end

    v_setpoint = get(ref[:bus][bus_id], "vm", 1.0)
    @constraint(model, vm[bus_id] == v_setpoint + sl_v[bus_id])
end

# Fixar ângulo na referência
for i in slack_bus_idx
    fix(va[i], 0.0; force=true)
end

# --- RESTRIÇÕES DO VLIM SUAVE ---
for (i, bus) in ref[:bus]
    v_min_lim = bus["vmin"]
    v_max_lim = bus["vmax"]
    
    # vm deve ser maior que vmin, a menos que sl_vmin atue
    @constraint(model, vm[i] >= v_min_lim - sl_vmin[i])
    
    # vm deve ser menor que vmax, a menos que sl_vmax atue
    @constraint(model, vm[i] <= v_max_lim + sl_vmax[i])
end

# =========================================================================
# 4. EQUAÇÕES DA REDE (KCL e KVL)
# =========================================================================

p_expr = Dict(); q_expr = Dict()

for (l, branch) in ref[:branch]
    f_bus = branch["f_bus"]; t_bus = branch["t_bus"]
    tm = branch["tap"]
    g, b = PowerModels.calc_branch_y(branch)
    tr, ti = PowerModels.calc_branch_t(branch)
    g_fr, b_fr = branch["g_fr"], branch["b_fr"]
    g_to, b_to = branch["g_to"], branch["b_to"]
    
    vm_f = vm[f_bus]; vm_t = vm[t_bus]
    theta = va[f_bus] - va[t_bus]
    
    p_expr[(l, f_bus, t_bus)] = @NLexpression(model, (g+g_fr)/tm^2*vm_f^2 + (-g*tr+b*ti)/tm^2*(vm_f*vm_t*cos(theta)) + (-b*tr-g*ti)/tm^2*(vm_f*vm_t*sin(theta)))
    q_expr[(l, f_bus, t_bus)] = @NLexpression(model, -(b+b_fr)/tm^2*vm_f^2 - (-b*tr-g*ti)/tm^2*(vm_f*vm_t*cos(theta)) + (-g*tr+b*ti)/tm^2*(vm_f*vm_t*sin(theta)))
    
    p_expr[(l, t_bus, f_bus)] = @NLexpression(model, (g+g_to)*vm_t^2 + (-g*tr-b*ti)/tm^2*(vm_t*vm_f*cos(-theta)) + (-b*tr+g*ti)/tm^2*(vm_t*vm_f*sin(-theta)))
    q_expr[(l, t_bus, f_bus)] = @NLexpression(model, -(b+b_to)*vm_t^2 - (-b*tr+g*ti)/tm^2*(vm_t*vm_f*cos(-theta)) + (-g*tr-b*ti)/tm^2*(vm_t*vm_f*sin(-theta)))
end

for (i, bus) in ref[:bus]
    bus_loads = ref[:bus_loads][i]
    bus_gens = ref[:bus_gens][i]
    bus_arcs = ref[:bus_arcs][i]
    
    gs = sum(shunt["gs"] for (k,shunt) in ref[:shunt] if shunt["shunt_bus"] == i; init=0.0)
    bs = sum(shunt["bs"] for (k,shunt) in ref[:shunt] if shunt["shunt_bus"] == i; init=0.0)
    
    pd = sum(load["pd"] for (k,load) in ref[:load] if load["load_bus"] == i; init=0.0)
    qd = sum(load["qd"] for (k,load) in ref[:load] if load["load_bus"] == i; init=0.0)

    @NLconstraint(model, sum(p_expr[a] for a in bus_arcs) == sum(pg[g] for g in bus_gens) - pd - gs*vm[i]^2)
    @NLconstraint(model, sum(q_expr[a] for a in bus_arcs) == sum(qg[g] for g in bus_gens) - qd + bs*vm[i]^2)
end

# =========================================================================
# 5. OBJETIVO: MINIMIZAR DESVIOS
# =========================================================================

# Minimizamos tanto o desvio de setpoint (QLIM) quanto violações de limites (VLIM)
@objective(model, Min, 
    sum(PENALIDADE_V * sl_v[i]^2 for i in keys(sl_v)) + 
    sum(PENALIDADE_VLIM * (sl_vmin[i]^2 + sl_vmax[i]^2) for i in keys(ref[:bus]))
)

println(">> Resolvendo Fluxo de Potência com QLIM e VLIM Suaves...")
optimize!(model)

# =========================================================================
# 6. VERIFICAÇÃO DE RESULTADOS
# =========================================================================

println("Status: ", termination_status(model))

println("\n--- Análise da Barra Slack (Referência) ---")
for i in slack_bus_idx
    p_gen_slack = sum(value(pg[g]) for g in ref[:bus_gens][i])
    println("Barra $i | P Gerado (Slack): ", round(p_gen_slack, digits=4), " pu")
end

println("\n--- Verificação de Atuação do QLIM ---")
for (i, gen) in ref[:gen]
    bus = gen["gen_bus"]
    desvio = value(sl_v[bus])
    q_val = value(qg[i])
    
    if abs(desvio) > 1e-3
        tipo_limite = (abs(q_val - gen["qmax"]) < 1e-3) ? "QMAX" : "QMIN"
        @printf("Barra %d | QLIM ATUOU (%s) | V_Set: %.3f | V_Final: %.3f | Q_Gen: %.3f\n", 
                bus, tipo_limite, ref[:bus][bus]["vm"], value(vm[bus]), q_val)
    end
end

println("\n--- Verificação de Violação de Limites (VLIM) ---")
vlim_violations = false
for (i, bus) in ref[:bus]
    viol_min = value(sl_vmin[i])
    viol_max = value(sl_vmax[i])
    v_atual = value(vm[i])
    
    if viol_min > 1e-3
        @printf("Barra %d | SUBTENSÃO | V_min: %.3f | V_Final: %.3f | Violação: %.3f pu\n", i, bus["vmin"], v_atual, viol_min)
        vlim_violations = true
    elseif viol_max > 1e-3
        @printf("Barra %d | SOBRETENSÃO | V_max: %.3f | V_Final: %.3f | Violação: %.3f pu\n", i, bus["vmax"], v_atual, viol_max)
        vlim_violations = true
    end
end
if !vlim_violations
    println("Nenhuma violação de limite de tensão detectada.")
end

# =========================================================================
# 7. ATUALIZAÇÃO E EXPORTAÇÃO DOS RESULTADOS
# =========================================================================

println("\n>> Gerando arquivos CSV dos resultados...")

# 7.1 Atualizar a estrutura de dados original com a solução do Solver
# Isso é necessário para usar funções auxiliares do PowerModels depois
for (i, bus) in ref[:bus]
    # Atualiza Tensão e Ângulo na estrutura de dados
    data["bus"][string(i)]["vm"] = value(vm[i])
    data["bus"][string(i)]["va"] = value(va[i])
end

for (i, gen) in ref[:gen]
    # Atualiza P e Q na estrutura de dados
    data["gen"][string(i)]["pg"] = value(pg[i])
    data["gen"][string(i)]["qg"] = value(qg[i])
end

# 7.2 CSV de BARRAS (Incluindo atuação do QLIM)
open("resultados_barras.csv", "w") do io
    println(io, "Barra,Tensao_pu,Angulo_graus,Correcao_Tensao_QLIM_pu,Tipo_Barra")
    
    # Ordena as barras para o CSV ficar bonito
    bus_ids = sort(collect(keys(ref[:bus])))
    
    for i in bus_ids
        d_bus = data["bus"][string(i)]
        
        v_val = d_bus["vm"]
        a_deg = rad2deg(d_bus["va"])
        type  = d_bus["bus_type"] # 1=PQ, 2=PV, 3=Slack
        
        # Recupera o valor da variável de slack (se existir para esta barra)
        slack_val = 0.0
        if i in keys(sl_v)
            slack_val = value(sl_v[i])
        end
        
        @printf(io, "%d,%.4f,%.4f,%.6f,%d\n", i, v_val, a_deg, slack_val, type)
    end
end
println("-> Arquivo 'resultados_barras.csv' gerado.")

# 7.3 CSV de GERAÇÃO (Indicando se bateu no limite)
open("resultados_geracao.csv", "w") do io
    println(io, "ID_Gerador,Barra,Pot_Ativa_pu,Pot_Reativa_pu,Limite_Qmin,Limite_Qmax,Status_Q")
    
    gen_ids = sort(collect(keys(ref[:gen])))
    
    for i in gen_ids
        d_gen = data["gen"][string(i)]
        bus_id = d_gen["gen_bus"]
        
        p_val = d_gen["pg"]
        q_val = d_gen["qg"]
        q_min = d_gen["qmin"]
        q_max = d_gen["qmax"]
        
        # Diagnóstico simples do estado do gerador
        status = "OK"
        if abs(q_val - q_max) < 1e-4
            status = "MAX_CAP"
        elseif abs(q_val - q_min) < 1e-4
            status = "MIN_IND"
        end
        
        @printf(io, "%d,%d,%.4f,%.4f,%.4f,%.4f,%s\n", i, bus_id, p_val, q_val, q_min, q_max, status)
    end
end
println("-> Arquivo 'resultados_geracao.csv' gerado.")

# 7.4 CSV de LINHAS (Calculando fluxo com base na solução)
# PowerModels calcula o fluxo AC exato baseado no V e Theta que atualizamos acima
flows = PowerModels.calc_branch_flow_ac(data)

open("resultados_linhas.csv", "w") do io
    println(io, "ID_Linha,De_Barra,Para_Barra,P_origem,Q_origem,P_destino,Q_destino,Carregamento_Pct")
    
    branch_ids = sort(collect(keys(ref[:branch])))
    
    for i in branch_ids
        d_branch = data["branch"][string(i)]
        f_bus = d_branch["f_bus"]
        t_bus = d_branch["t_bus"]
        rate_a = get(d_branch, "rate_a", 0.0)
        
        # Recupera os fluxos calculados
        # Nota: as chaves em 'flows' são strings
        if haskey(flows["branch"], string(i))
            res = flows["branch"][string(i)]
            pf, qf = res["pf"], res["qf"]
            pt, qt = res["pt"], res["qt"]
            
            # Cálculo do carregamento aparente S = sqrt(P^2 + Q^2)
            s_flow = sqrt(pf^2 + qf^2)
            loading = (rate_a > 0.0) ? (s_flow / rate_a) * 100.0 : 0.0
            
            @printf(io, "%d,%d,%d,%.4f,%.4f,%.4f,%.4f,%.2f\n", 
                    i, f_bus, t_bus, pf, qf, pt, qt, loading)
        else
            @printf(io, "%d,%d,%d,NaN,NaN,NaN,NaN,NaN\n", i, f_bus, t_bus)
        end
    end
end
println("-> Arquivo 'resultados_linhas.csv' gerado.")
println(">> Exportação concluída com sucesso!")

