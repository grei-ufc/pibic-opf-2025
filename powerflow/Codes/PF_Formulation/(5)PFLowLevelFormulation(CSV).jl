using PowerModels
using JuMP
using Ipopt
using PWF
using Printf # Necessário para o @printf
print("\033c")

# =========================================================================
# 1. PREPARAÇÃO E RESOLUÇÃO
# =========================================================================

# Carrega o caso
file_path = joinpath(@__DIR__, "case5.m") # Ajuste para o caminho do seu arquivo
data = PowerModels.parse_file(file_path)
#data = PWF.parse_pwf_to_powermodels(file_path)
PowerModels.standardize_cost_terms!(data, order=2)
PowerModels.calc_thermal_limits!(data)
ref = PowerModels.build_ref(data)[:it][:pm][:nw][0]

model = Model(Ipopt.Optimizer)

# Variáveis
vm = @variable(model, ref[:bus][i]["vmin"] <= vm[i in keys(ref[:bus])] <= ref[:bus][i]["vmax"], start=1.0)
va = @variable(model, va[i in keys(ref[:bus])], start=0.0)
pg = @variable(model, ref[:gen][i]["pmin"] <= pg[i in keys(ref[:gen])] <= ref[:gen][i]["pmax"])
qg = @variable(model, ref[:gen][i]["qmin"] <= qg[i in keys(ref[:gen])] <= ref[:gen][i]["qmax"])

# Slacks de Controle (PENALIDADE ALTA para garantir que só ativem se necessário)
PENALIDADE = 1e6 
gen_buses = unique([gen["gen_bus"] for (i,gen) in ref[:gen]])
sl_v = @variable(model, sl_v[i in gen_buses], start=0.0) # QLIM
sl_d = @variable(model, sl_d[i in keys(ref[:load])], start=0.0) # VLIM

# Expressões de Fluxo
p = Dict(); q = Dict()
for (l, branch) in ref[:branch]
    f_bus = branch["f_bus"]; t_bus = branch["t_bus"]
    g, b = PowerModels.calc_branch_y(branch)
    tr, ti = PowerModels.calc_branch_t(branch)
    tm = branch["tap"]
    g_fr = branch["g_fr"]; b_fr = branch["b_fr"]
    g_to = branch["g_to"]; b_to = branch["b_to"]

    p[(l, f_bus, t_bus)] = @NLexpression(model, (g+g_fr)/tm^2*vm[f_bus]^2 + (-g*tr+b*ti)/tm^2*(vm[f_bus]*vm[t_bus]*cos(va[f_bus]-va[t_bus])) + (-b*tr-g*ti)/tm^2*(vm[f_bus]*vm[t_bus]*sin(va[f_bus]-va[t_bus])))
    q[(l, f_bus, t_bus)] = @NLexpression(model, -(b+b_fr)/tm^2*vm[f_bus]^2 - (-b*tr-g*ti)/tm^2*(vm[f_bus]*vm[t_bus]*cos(va[f_bus]-va[t_bus])) + (-g*tr+b*ti)/tm^2*(vm[f_bus]*vm[t_bus]*sin(va[f_bus]-va[t_bus])))
    p[(l, t_bus, f_bus)] = @NLexpression(model, (g+g_to)*vm[t_bus]^2 + (-g*tr-b*ti)/tm^2*(vm[t_bus]*vm[f_bus]*cos(va[t_bus]-va[f_bus])) + (-b*tr+g*ti)/tm^2*(vm[t_bus]*vm[f_bus]*sin(va[t_bus]-va[f_bus])))
    q[(l, t_bus, f_bus)] = @NLexpression(model, -(b+b_to)*vm[t_bus]^2 - (-b*tr+g*ti)/tm^2*(vm[t_bus]*vm[f_bus]*cos(va[t_bus]-va[f_bus])) + (-g*tr-b*ti)/tm^2*(vm[t_bus]*vm[f_bus]*sin(va[t_bus]-va[f_bus])))
end

# Restrições de Balanço
for (i, bus) in ref[:bus]
    bus_loads = ref[:bus_loads][i]
    bus_gens = ref[:bus_gens][i]
    bus_arcs = ref[:bus_arcs][i]
    
    gs = sum(shunt["gs"] for (k,shunt) in ref[:shunt] if shunt["shunt_bus"] == i; init=0.0)
    bs = sum(shunt["bs"] for (k,shunt) in ref[:shunt] if shunt["shunt_bus"] == i; init=0.0)
    pd = sum(load["pd"] for (k,load) in ref[:load] if load["load_bus"] == i; init=0.0)
    qd = sum(load["qd"] for (k,load) in ref[:load] if load["load_bus"] == i; init=0.0)

    # VLIM Slack logic
    slack_term = isempty(bus_loads) ? 0.0 : sum(sl_d[l] for l in bus_loads)

    @NLconstraint(model, sum(p[a] for a in bus_arcs) == sum(pg[g] for g in bus_gens) - pd - gs*vm[i]^2)
    @NLconstraint(model, sum(q[a] for a in bus_arcs) == sum(qg[g] for g in bus_gens) - (qd + slack_term) + bs*vm[i]^2)
end

# Slack Bus Ref
for (i, bus) in ref[:ref_buses]; @constraint(model, va[i] == 0); end

# QLIM Control
for (i, gen) in ref[:gen]
    bus_id = gen["gen_bus"]
    vm_setpoint = ref[:bus][bus_id]["vm"]
    @constraint(model, vm[bus_id] == vm_setpoint + sl_v[bus_id])
end

# Objetivo
custo_gen = JuMP.AffExpr(0.0)
for (i, gen) in ref[:gen]
    cost = gen["cost"]
    if length(cost) >= 2; add_to_expression!(custo_gen, cost[1]*pg[i] + cost[2]); end
end
@objective(model, Min, custo_gen + PENALIDADE * sum(sl_v[i]^2 for i in keys(sl_v)) + PENALIDADE * sum(sl_d[l]^2 for l in keys(sl_d)))

optimize!(model)

# =========================================================================
# 2. ATUALIZAÇÃO DOS DADOS (A PONTE)
# =========================================================================
println(">> Atualizando estrutura de dados com resultados da otimização...")

# Verificamos se resolveu antes de exportar
if termination_status(model) != LOCALLY_SOLVED && termination_status(model) != OPTIMAL
    warn("Atenção: O modelo não convergiu para um ótimo local. Os CSVs podem conter dados inválidos.")
end

# Usamos 'network_data' como alias para 'data' para manter compatibilidade com seu script
network_data = data 

# 2.1 Atualizar Barras (Tensão e Ângulo)
for (i, bus) in network_data["bus"]
    # Parseia a chave string "1" para int 1 para acessar a variável JuMP
    idx = parse(Int, i)
    bus["vm"] = value(vm[idx])
    bus["va"] = value(va[idx])
end

# 2.2 Atualizar Geradores (Pg e Qg)
for (i, gen) in network_data["gen"]
    idx = parse(Int, i)
    gen["pg"] = value(pg[idx])
    gen["qg"] = value(qg[idx])
end

# =========================================================================
# 3. EXPORTAÇÃO PARA CSV (ADAPTADO COM SLACKS)
# =========================================================================

println(">> Gerando arquivos CSV...")

# 3.1 Exportar Tensão nas Barras + AÇÃO QLIM (Correção de Tensão)
open("resultados_barras.csv", "w") do io
    # Adicionei a coluna 'Slack_QLIM_Correcao_V_pu'
    println(io, "Barra,Tensao_pu,Angulo_graus,Slack_QLIM_Correcao_V_pu")
    
    buses = sort(collect(keys(network_data["bus"])), by=x->parse(Int, x))

    for bus_id in buses
        d_bus = network_data["bus"][bus_id]
        idx = parse(Int, bus_id)
        
        vm_val = d_bus["vm"]
        va_deg = rad2deg(d_bus["va"])
        
        # Verifica se houve ação de QLIM nessa barra (sl_v existe apenas em barras de geração)
        slack_val = 0.0
        if idx in keys(sl_v)
            slack_val = value(sl_v[idx])
        end
        
        @printf(io, "%s,%.4f,%.4f,%.6f\n", bus_id, vm_val, va_deg, slack_val)
    end
end
println("-> Arquivo 'resultados_barras.csv' criado.")

# 3.2 Exportar Cargas + AÇÃO VLIM (Corte/Injeção de Carga Reativa)
# Nota: Criei um CSV específico para cargas, pois o VLIM atua na carga, não no gerador.
open("resultados_cargas_vlim.csv", "w") do io
    println(io, "ID_Carga,Barra,Q_Original_pu,Q_Final_pu,Slack_VLIM_Atuacao_pu")

    loads = sort(collect(keys(network_data["load"])), by=x->parse(Int, x))
    for load_id in loads
        d_load = network_data["load"][load_id]
        idx = parse(Int, load_id)
        
        q_original = d_load["qd"]
        
        # Recupera valor da slack VLIM
        slack_val = value(sl_d[idx])
        
        # O Q final "visto" pela rede é o original + slack
        q_final = q_original + slack_val
        
        @printf(io, "%s,%d,%.4f,%.4f,%.6f\n", load_id, d_load["load_bus"], q_original, q_final, slack_val)
    end
end
println("-> Arquivo 'resultados_cargas_vlim.csv' criado.")

# 3.3 Exportar Geração (Padrão)
open("resultados_geracao.csv", "w") do io
    println(io, "ID_Gerador,Barra,Pot_Ativa_pu,Pot_Reativa_pu")

    if haskey(network_data, "gen")
        gens = sort(collect(keys(network_data["gen"])), by=x->parse(Int, x))
        for gen_id in gens
            d_gen = network_data["gen"][gen_id]
            @printf(io, "%s,%d,%.4f,%.4f\n", gen_id, d_gen["gen_bus"], d_gen["pg"], d_gen["qg"])
        end
    else
        println(io, "Nenhum gerador encontrado")
    end
end
println("-> Arquivo 'resultados_geracao.csv' criado.")

# 3.4 Exportar Fluxo nas Linhas
# Calculamos os fluxos baseados nos valores atualizados de Vm e Va
flows = PowerModels.calc_branch_flow_ac(network_data)

open("resultados_linhas.csv", "w") do io
    println(io, "ID_Linha,De_Barra,Para_Barra,P_origem_pu,Q_origem_pu,P_destino_pu,Q_destino_pu,Carregamento_origem_pct")

    branch_ids = sort(collect(keys(network_data["branch"])), by=x->parse(Int, x))

    for i in branch_ids
        branch_topo = network_data["branch"][i]
        f_bus = branch_topo["f_bus"]
        t_bus = branch_topo["t_bus"]
        rate_a = get(branch_topo, "rate_a", 0.0)
        
        if haskey(flows["branch"], i)
            branch_res = flows["branch"][i]
            pf, qf = branch_res["pf"], branch_res["qf"]
            pt, qt = branch_res["pt"], branch_res["qt"]
            
            s_mag = sqrt(pf^2 + qf^2)
            loading = (rate_a > 0) ? (s_mag/rate_a)*100 : 0.0
            
            @printf(io, "%s,%d,%d,%.4f,%.4f,%.4f,%.4f,%.2f\n", 
                    i, f_bus, t_bus, pf, qf, pt, qt, loading)
        else
            @printf(io, "%s,%d,%d,NaN,NaN,NaN,NaN,NaN\n", i, f_bus, t_bus)
        end
    end
end
println("-> Arquivo 'resultados_linhas.csv' criado.")

println("\nProcesso finalizado com sucesso.")

println("Custo Total: ", objective_value(model))