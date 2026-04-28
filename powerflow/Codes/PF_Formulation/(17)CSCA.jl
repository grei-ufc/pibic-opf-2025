# QLIM + VLIM + CSCA (Versão Definitiva com Data Cleaning)

using PWF
using PowerModels
using JuMP
using Ipopt
using CSV
using DataFrames

print("\033c")

function resolver_fluxo_controlado(caminho_arquivo)
    # =========================================================================
    # 0. LEITURA DE DADOS E TOPOLOGIA
    # =========================================================================
    println("1. Lendo arquivo PWF...")
    
    # Lemos o arquivo forçando a extração dos dados de controle (CSCA)
    data = PWF.parse_file(caminho_arquivo, add_control_data=true)
    base_mva = data["baseMVA"]

    PowerModels.select_largest_component!(data)
    println("-> Ilhas isoladas removidas! Mantendo apenas a rede principal conectada.")

    PowerModels.standardize_cost_terms!(data, order=2)

    # ---> PATCH DE LIMPEZA (CORREÇÃO DO BUG DO "parameters") <---
    # Remove chaves não-numéricas que o PWF adiciona e que quebram o PowerModels
    for (comp_name, comp_dict) in data
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

    # Agora o build_ref consegue rodar sem encontrar a letra "p"
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
    # 2. VARIÁVEIS DE ESTADO FÍSICO, ELOS DC E SHUNTS (CSCA)
    # =========================================================================
    println("2. Criando variáveis de estado e controle...")
    @variable(model, ref[:bus][i]["vmin"] <= vm[i in keys(ref[:bus])] <= ref[:bus][i]["vmax"], start=ref[:bus][i]["vm"])
    @variable(model, va[i in keys(ref[:bus])], start=ref[:bus][i]["va"])

    @variable(model, ref[:gen][i]["pmin"] <= pg[i in keys(ref[:gen])] <= ref[:gen][i]["pmax"], start=ref[:gen][i]["pg"])
    @variable(model, ref[:gen][i]["qmin"] <= qg[i in keys(ref[:gen])] <= ref[:gen][i]["qmax"], start=ref[:gen][i]["qg"])

    # Variáveis dos Elos DC
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

    # Variáveis dos Shunts (CSCA - Agora extraindo dados de controle)
    @variable(model, bs_var[i in keys(ref[:shunt])])
    for (i, shunt) in ref[:shunt]
        bmin = shunt["bs"]
        bmax = shunt["bs"]
        
        # Se os dados de controle do ANAREDE existirem, nós atualizamos os limites!
        if haskey(shunt, "control_data") && haskey(shunt["control_data"], "bsmin")
            bmin = shunt["control_data"]["bsmin"]
            bmax = shunt["control_data"]["bsmax"]
        end
        
        real_bmin = min(bmin, bmax, shunt["bs"])
        real_bmax = max(bmin, bmax, shunt["bs"])
        
        set_lower_bound(bs_var[i], real_bmin)
        set_upper_bound(bs_var[i], real_bmax)
        set_start_value(bs_var[i], shunt["bs"])
        
        # Se não houver margem de controle, cravamos o valor fixo original
        if real_bmin == real_bmax
            fix(bs_var[i], shunt["bs"]; force=true)
        end
    end

    # =========================================================================
    # 3. LÓGICA DO FLUXO DE POTÊNCIA NAS MÁQUINAS
    # =========================================================================
    for (i, gen) in ref[:gen]
        if gen["gen_bus"] in keys(ref[:ref_buses])
            if has_lower_bound(pg[i]) delete_lower_bound(pg[i]) end
            if has_upper_bound(pg[i]) delete_upper_bound(pg[i]) end
        else
            fix(pg[i], gen["pg"]; force=true)
        end
    end

    for (i, bus) in ref[:ref_buses]
        fix(va[i], 0.0; force=true)
    end

    # =========================================================================
    # 4. VARIÁVEIS E RESTRIÇÕES DE CONTROLE (QLIM, VLIM e CSCA)
    # =========================================================================
    PENALIDADE = 1e6 

    # Identifica barras com Geradores
    gen_buses = [gen["gen_bus"] for (i,gen) in ref[:gen]]
    
    # Identifica barras com Shunts que possuem margem real de controle (CSCA)
    shunt_buses = [
        shunt["shunt_bus"] for (i,shunt) in ref[:shunt] 
        if haskey(shunt, "control_data") && haskey(shunt["control_data"], "bsmin") && shunt["control_data"]["bsmin"] != shunt["control_data"]["bsmax"]
    ]
    
    controlled_buses = unique(vcat(gen_buses, shunt_buses))

    @variable(model, sl_v[i in controlled_buses], start=0.0)

    for bus_id in controlled_buses
        vm_setpoint = ref[:bus][bus_id]["vm"] 
        @constraint(model, vm[bus_id] == vm_setpoint + sl_v[bus_id])
    end

    @variable(model, sl_d[i in keys(ref[:load])], start=0.0)

    # =========================================================================
    # 5. EQUAÇÕES DE FLUXO NOS RAMOS AC
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

        p[(l, f, t)] = @NLexpression(model, (g+g_fr)/tm^2 * vm[f]^2 + (-g*tr+b*ti)/tm^2 * (vm[f]*vm[t]*cos(va[f]-va[t])) + (-b*tr-g*ti)/tm^2 * (vm[f]*vm[t]*sin(va[f]-va[t])))
        q[(l, f, t)] = @NLexpression(model, -(b+b_fr)/tm^2 * vm[f]^2 - (-b*tr-g*ti)/tm^2 * (vm[f]*vm[t]*cos(va[f]-va[t])) + (-g*tr+b*ti)/tm^2 * (vm[f]*vm[t]*sin(va[f]-va[t])))
        
        p[(l, t, f)] = @NLexpression(model, (g+g_to) * vm[t]^2 + (-g*tr-b*ti)/tm^2 * (vm[t]*vm[f]*cos(va[t]-va[f])) + (-b*tr+g*ti)/tm^2 * (vm[t]*vm[f]*sin(va[t]-va[f])))
        q[(l, t, f)] = @NLexpression(model, -(b+b_to) * vm[t]^2 - (-b*tr+g*ti)/tm^2 * (vm[t]*vm[f]*cos(va[t]-va[f])) + (-g*tr-b*ti)/tm^2 * (vm[t]*vm[f]*sin(va[t]-va[f])))
    end

    # =========================================================================
    # 6. LEIS DE KIRCHHOFF DOS NÓS 
    # =========================================================================
    println("4. Montando balanço nodal (Leis de Kirchhoff)...")
    for (i, bus) in ref[:bus]
        bus_arcs = ref[:bus_arcs][i]
        bus_arcs_dc = ref[:bus_arcs_dc][i] 
        bus_gens = ref[:bus_gens][i]
        bus_loads = ref[:bus_loads][i]
        bus_shunts = [k for (k,shunt) in ref[:shunt] if shunt["shunt_bus"] == i]

        pd_nominal = sum(load["pd"] for (k,load) in ref[:load] if load["load_bus"] == i; init=0.0)
        qd_nominal = sum(load["qd"] for (k,load) in ref[:load] if load["load_bus"] == i; init=0.0)

        p_gen_total = isempty(bus_gens) ? 0.0 : sum(pg[g] for g in bus_gens)
        q_gen_total = isempty(bus_gens) ? 0.0 : sum(qg[g] for g in bus_gens)
        
        p_dcline_total = isempty(bus_arcs_dc) ? 0.0 : sum(p_dc[a] for a in bus_arcs_dc)
        q_dcline_total = isempty(bus_arcs_dc) ? 0.0 : sum(q_dc[a] for a in bus_arcs_dc)

        slack_vlim  = isempty(bus_loads) ? 0.0 : sum(sl_d[l] for l in bus_loads)

        gs_total = isempty(bus_shunts) ? 0.0 : sum(ref[:shunt][k]["gs"] for k in bus_shunts)

        # Balanço Ativo
        @NLconstraint(model, 
            sum(p[a] for a in bus_arcs) + p_dcline_total == p_gen_total - pd_nominal - gs_total*vm[i]^2 
        )

        # Balanço Reativo com Susceptância Variável (bs_var)
        if isempty(bus_shunts)
            @NLconstraint(model, 
                sum(q[a] for a in bus_arcs) + q_dcline_total == q_gen_total - (qd_nominal + slack_vlim)
            )
        else
            @NLconstraint(model, 
                sum(q[a] for a in bus_arcs) + q_dcline_total == q_gen_total - (qd_nominal + slack_vlim) + sum(bs_var[k]*vm[i]^2 for k in bus_shunts) 
            )
        end
    end

    # =========================================================================
    # 7. FUNÇÃO OBJETIVO DE SOFT-CONSTRAINTS
    # =========================================================================
    @objective(model, Min, 
        PENALIDADE * sum(sl_v[i]^2 for i in keys(sl_v)) + 
        PENALIDADE * sum(sl_d[l]^2 for l in keys(sl_d))
    )

    # =========================================================================
    # 8. RESOLUÇÃO 
    # =========================================================================
    println("5. Resolvendo o Fluxo de Potência Controlado...\n")
    tempo_total_execucao = @elapsed optimize!(model)

    println("\n--- ESTATÍSTICAS DE RESOLUÇÃO ---")
    println("Status da Convergência: ", termination_status(model))
    println("Tempo interno do Solver (Ipopt): ", round(solve_time(model), digits=4), " segundos")
    println("Tempo total da execução da função: ", round(tempo_total_execucao, digits=4), " segundos")
    println("Erro de Controle (Slacks Ponderadas): ", objective_value(model))

    # =========================================================================
    # 9. RESUMO OPERACIONAL E FÍSICO
    # =========================================================================
    vetor_tensoes = [value(vm[i]) for i in keys(ref[:bus])]
    tensao_min = minimum(vetor_tensoes)
    tensao_max = maximum(vetor_tensoes)

    geracao_p_total = sum(value(pg[g]) for g in keys(ref[:gen]); init=0.0)
    geracao_q_total = sum(value(qg[g]) for g in keys(ref[:gen]); init=0.0)
    
    perda_p_total = sum(
        value(p[(l, b["f_bus"], b["t_bus"])]) + value(p[(l, b["t_bus"], b["f_bus"])]) 
        for (l, b) in ref[:branch]; init=0.0
    )

    println("\n--- RESUMO OPERACIONAL GLOBAL ---")
    println("Tensão Mínima (pu):         ", round(tensao_min, digits=4))
    println("Tensão Máxima (pu):         ", round(tensao_max, digits=4))
    println("Geração Ativa Total (pu):   ", round(geracao_p_total, digits=4))
    println("Geração Reativa Total (pu): ", round(geracao_q_total, digits=4))
    println("Perdas Ativas (Total pu):   ", round(perda_p_total, digits=4))

    println("\n--- RESUMO EM UNIDADES REAIS (Base = $base_mva MVA) ---")
    println("Geração Ativa Total (MW):   ", round(geracao_p_total * base_mva, digits=2))
    println("Geração Reativa Total (MVAr):", round(geracao_q_total * base_mva, digits=2))
    println("Perdas Ativas Totais (MW):  ", round(perda_p_total * base_mva, digits=2))
end

# -------------------------------------------------------------
# EXECUÇÃO PRINCIPAL
# -------------------------------------------------------------
#arquivo = joinpath(@__DIR__, "..", "data_CPF", "anarede", "5busfrank_csca.pwf") # Ajuste o caminho se necessário
arquivo = joinpath(@__DIR__, "..", "data_CPF", "anarede", "5busfrank_csca.pwf")
resolver_fluxo_controlado(arquivo)