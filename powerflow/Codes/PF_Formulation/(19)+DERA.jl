using PWF
using PowerModels
using JuMP
using Ipopt
using CSV
using DataFrames

print("\033c") # Limpa o terminal

# Pasta dedicada aos CSVs (criada automaticamente se não existir)
PASTA_CSV = joinpath(@__DIR__, "resultados_csv") 
mkpath(PASTA_CSV) 

function resolver_fluxo_controlado(caminho_arquivo)
    # =========================================================================
    # 0. LEITURA DE DADOS E TOPOLOGIA
    # =========================================================================
    println("1. Lendo arquivo PWF...")
    
    data = PWF.parse_file(caminho_arquivo, add_control_data=true)
    base_mva = data["baseMVA"] 
    PowerModels.select_largest_component!(data)
    println("-> Ilhas isoladas removidas! Mantendo apenas a rede principal conectada.")

    # Identifica todas as barras definidas como referência (bus_type == 3)
    ref_buses = [b_dict for (b_id, b_dict) in data["bus"] if b_dict["bus_type"] == 3]

    # Se houver mais de 1, mantemos apenas a primeira e convertemos o resto para PV (Tipo 2)
    if length(ref_buses) > 1
        println("-> Aviso: Múltiplas barras de referência detectadas. Convertendo excedentes para PV (Tipo 2)...")
        for i in 2:length(ref_buses)
            ref_buses[i]["bus_type"] = 2
        end
    end

    PowerModels.standardize_cost_terms!(data, order=2) 
 
    # ---> PATCH DE LIMPEZA <---
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

    # =========================================================================
    # 1. INICIALIZAÇÃO DO MODELO E SOLVER
    # =========================================================================
    model = Model(optimizer_with_attributes(Ipopt.Optimizer, 
        "max_iter" => 3000, 
        "tol" => 1e-5,
        "print_level" => 5
    ))

    # =========================================================================
    # 2. VARIÁVEIS DE ESTADO FÍSICO, ELOS DC, SHUNTS E TAPS (CTAP)
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

    # Variáveis dos Shunts (CSCA) 
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

    # Variáveis de Tap dos Transformadores (CTAP)
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
    # 4. VARIÁVEIS E RESTRIÇÕES DE CONTROLE (QLIM e VLIM)
    # =========================================================================
    PENALIDADE = 1e6 
    PENALIDADE_MENOR = 1e4 

    gen_buses = [gen["gen_bus"] for (i,gen) in ref[:gen]]
    shunt_buses = [
        shunt["shunt_bus"] for (i,shunt) in ref[:shunt] 
        if haskey(shunt, "control_data") && haskey(shunt["control_data"], "bsmin") && shunt["control_data"]["bsmin"] != shunt["control_data"]["bsmax"]
    ]
    controlled_buses = unique(vcat(gen_buses, shunt_buses))

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
    
    # =========================================================================
    # 4.1 VARIÁVEIS DE CORTE DE CARGA (DERA)
    # =========================================================================
    println("Criando variáveis de Corte de Carga (DERA)...")
    
    @variable(model, 0.0 <= corte_p[l in keys(ref[:load])] <= max(0.0, ref[:load][l]["pd"]), start=0.0) 
    @variable(model, corte_q[l in keys(ref[:load])], start=0.0)

    # Restrição para manter o fator de potência da carga constante durante o corte
    for (l, load) in ref[:load]
        if load["pd"] > 1e-4
            @constraint(model, corte_q[l] == corte_p[l] * (load["qd"] / load["pd"]))
        else
            fix(corte_p[l], 0.0; force=true)
            fix(corte_q[l], 0.0; force=true)
        end
    end

    # Estrutura de penalidade baseada no nível de tensão (kV) da barra
    peso_corte = Dict()
    for (l, load) in ref[:load]
        bus_id = load["load_bus"]
        base_kv = get(ref[:bus][bus_id], "base_kv", 1.0)
        
        if base_kv < 69.0
            peso_corte[l] = 1e7 # Subtransmissão e Distribuição (Prioridade de Corte)
        elseif base_kv <= 230.0
            peso_corte[l] = 5e7 # Transmissão (Maior peso)
        else
            peso_corte[l] = 1e8 # Extra Alta Tensão - EAT (Último recurso de corte)
        end
    end

    # =========================================================================
    # 5. EQUAÇÕES DE FLUXO NOS RAMOS AC
    # =========================================================================
    println("3. Montando equações de fluxo de potência (AC Polar)...")
    p = Dict(); q = Dict()

    for (l, branch) in ref[:branch]
        f = branch["f_bus"]; t = branch["t_bus"]
        g, b = PowerModels.calc_branch_y(branch)
        
        g_fr = branch["g_fr"]; b_fr = branch["b_fr"]
        g_to = branch["g_to"]; b_to = branch["b_to"]

        shift = branch["shift"]
        cos_phi = cos(shift)
        sin_phi = sin(shift)

        # Fluxos do lado 'from' (f -> t)
        p[(l, f, t)] = @NLexpression(model, 
            (g + g_fr) / tm_var[l]^2 * vm[f]^2 + 
            (-g * cos_phi + b * sin_phi) / tm_var[l] * (vm[f] * vm[t] * cos(va[f] - va[t])) + 
            (-b * cos_phi - g * sin_phi) / tm_var[l] * (vm[f] * vm[t] * sin(va[f] - va[t]))
        )
        q[(l, f, t)] = @NLexpression(model, 
            -(b + b_fr) / tm_var[l]^2 * vm[f]^2 - 
            (-b * cos_phi - g * sin_phi) / tm_var[l] * (vm[f] * vm[t] * cos(va[f] - va[t])) + 
            (-g * cos_phi + b * sin_phi) / tm_var[l] * (vm[f] * vm[t] * sin(va[f] - va[t]))
        )
        
        # Fluxos do lado 'to' (t -> f)
        p[(l, t, f)] = @NLexpression(model, 
            (g + g_to) * vm[t]^2 + 
            (-g * cos_phi - b * sin_phi) / tm_var[l] * (vm[t] * vm[f] * cos(va[t] - va[f])) + 
            (-b * cos_phi + g * sin_phi) / tm_var[l] * (vm[t] * vm[f] * sin(va[t] - va[f]))
        )
        q[(l, t, f)] = @NLexpression(model, 
            -(b + b_to) * vm[t]^2 - 
            (-b * cos_phi + g * sin_phi) / tm_var[l] * (vm[t] * vm[f] * cos(va[t] - va[f])) + 
            (-g * cos_phi - b * sin_phi) / tm_var[l] * (vm[t] * vm[f] * sin(va[t] - va[f]))
        )
    end

    # =========================================================================
    # 6. LEIS DE KIRCHHOFF DOS NÓS COM DERA
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

        # Integração das variáveis do DERA no balanço nodal
        corte_p_total = isempty(bus_loads) ? 0.0 : sum(corte_p[l] for l in bus_loads)
        corte_q_total = isempty(bus_loads) ? 0.0 : sum(corte_q[l] for l in bus_loads)

        p_gen_total = isempty(bus_gens) ? 0.0 : sum(pg[g] for g in bus_gens)
        q_gen_total = isempty(bus_gens) ? 0.0 : sum(qg[g] for g in bus_gens)
        
        p_dcline_total = isempty(bus_arcs_dc) ? 0.0 : sum(p_dc[a] for a in bus_arcs_dc)
        q_dcline_total = isempty(bus_arcs_dc) ? 0.0 : sum(q_dc[a] for a in bus_arcs_dc)

        slack_vlim  = isempty(bus_loads) ? 0.0 : sum(sl_d[l] for l in bus_loads)
        gs_total = isempty(bus_shunts) ? 0.0 : sum(ref[:shunt][k]["gs"] for k in bus_shunts)

        # Balanço Ativo
        @NLconstraint(model, 
            sum(p[a] for a in bus_arcs) + p_dcline_total == p_gen_total - (pd_nominal - corte_p_total) - gs_total*vm[i]^2 
        )

        # Balanço Reativo 
        if isempty(bus_shunts)
            @NLconstraint(model, 
                sum(q[a] for a in bus_arcs) + q_dcline_total == q_gen_total - (qd_nominal - corte_q_total + slack_vlim)
            )
        else
            @NLconstraint(model, 
                sum(q[a] for a in bus_arcs) + q_dcline_total == q_gen_total - (qd_nominal - corte_q_total + slack_vlim) + sum(bs_var[k]*vm[i]^2 for k in bus_shunts) 
            )
        end
    end

    # =========================================================================
    # 7. FUNÇÃO OBJETIVO COM PENALIZAÇÃO HIERÁRQUICA
    # =========================================================================
    println("Montando a Função Objetivo...")
    
    @objective(model, Min, 
        PENALIDADE * sum(sl_v[i]^2 for i in controlled_buses) + 
        PENALIDADE * sum(sl_v_upp[i]^2 + sl_v_low[i]^2 for i in controlled_buses) +
        PENALIDADE * sum(sl_d[l]^2 for l in keys(ref[:load])) +
        PENALIDADE_MENOR * sum(sl_bsh[k]^2 for k in keys(ref[:shunt])) +
        # Penalidade hierárquica baseada nos níveis de tensão (linear)
        sum(peso_corte[l] * corte_p[l] for l in keys(ref[:load]))
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
    println("Valor da Função Objetivo: ", objective_value(model))

    # =========================================================================
    # 9. RESUMO OPERACIONAL E FÍSICO
    # =========================================================================
    vetor_tensoes = [value(vm[i]) for i in keys(ref[:bus])]
    tensao_min = minimum(vetor_tensoes)
    tensao_max = maximum(vetor_tensoes)

    geracao_p_total = sum(value(pg[g]) for g in keys(ref[:gen]); init=0.0)
    geracao_q_total = sum(value(qg[g]) for g in keys(ref[:gen]); init=0.0)
    
    corte_p_global = sum(value(corte_p[l]) for l in keys(corte_p); init=0.0)
    
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
    println("Corte de Carga DERA (pu):   ", round(corte_p_global, digits=4))

    println("\n--- RESUMO EM UNIDADES REAIS (Base = $base_mva MVA) ---")
    println("Geração Ativa Total (MW):   ", round(geracao_p_total * base_mva, digits=2))
    println("Geração Reativa Total (MVAr):", round(geracao_q_total * base_mva, digits=2))
    println("Perdas Ativas Totais (MW):  ", round(perda_p_total * base_mva, digits=2))
    println("Corte de Carga Total (MW):  ", round(corte_p_global * base_mva, digits=2))

    # =========================================================================
    # 10. EXPORTAÇÃO DOS RESULTADOS PARA CSV
    # =========================================================================
    println("\n6. Estruturando dados e gerando arquivos CSV...")

    df_barras = DataFrame(
        ID_Barra = Int[], Tipo_Barra = Int[], Tensao_Base_kV = Float64[],
        Tensao_Mag_pu = Float64[], Tensao_Ang_graus = Float64[],
        P_Geracao_pu = Float64[], Q_Geracao_pu = Float64[],
        P_Carga_pu = Float64[], Q_Carga_pu = Float64[],
        Desvio_Tensao_QLIM_pu = Float64[], Corte_Reativo_VLIM_pu = Float64[],
        Corte_Ativo_DERA_pu = Float64[], Corte_Reativo_DERA_pu = Float64[]
    )

    for (i, bus) in ref[:bus]
        bus_gens = ref[:bus_gens][i]
        bus_loads = ref[:bus_loads][i]
        push!(df_barras, (
            i, bus["bus_type"], get(bus, "base_kv", 1.0),
            value(vm[i]), value(va[i]) * (180.0 / pi),
            isempty(bus_gens) ? 0.0 : sum(value(pg[g]) for g in bus_gens),
            isempty(bus_gens) ? 0.0 : sum(value(qg[g]) for g in bus_gens),
            isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["pd"] for l in bus_loads),
            isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["qd"] for l in bus_loads),
            (i in keys(sl_v)) ? value(sl_v[i]) : 0.0,
            isempty(bus_loads) ? 0.0 : sum(value(sl_d[l]) for l in bus_loads),
            isempty(bus_loads) ? 0.0 : sum(value(corte_p[l]) for l in bus_loads),
            isempty(bus_loads) ? 0.0 : sum(value(corte_q[l]) for l in bus_loads)
        ))
    end
    sort!(df_barras, :ID_Barra)
    CSV.write(joinpath(PASTA_CSV, "resultados_barras_SIN.csv"), df_barras)

    df_linhas = DataFrame(
        ID_Linha = Int[], Barra_De = Int[], Barra_Para = Int[],
        P_Fluxo_De_Para_pu = Float64[], Q_Fluxo_De_Para_pu = Float64[],
        P_Fluxo_Para_De_pu = Float64[], Q_Fluxo_Para_De_pu = Float64[],
        Perda_Ativa_pu = Float64[], Tap_pu = Float64[] 
    )

    for (l, branch) in ref[:branch]
        f = branch["f_bus"]; t = branch["t_bus"]
        val_p_from = value(p[(l, f, t)]); val_q_from = value(q[(l, f, t)])
        val_p_to   = value(p[(l, t, f)]); val_q_to   = value(q[(l, t, f)])
        val_tap    = value(tm_var[l])
        push!(df_linhas, (l, f, t, val_p_from, val_q_from, val_p_to, val_q_to, val_p_from + val_p_to, val_tap))
    end
    sort!(df_linhas, :ID_Linha)
    CSV.write(joinpath(PASTA_CSV, "resultados_fluxos_linhas_SIN.csv"), df_linhas)
    println("-> Arquivos CSV gerados em $PASTA_CSV")
end

# -------------------------------------------------------------
# EXECUÇÃO PRINCIPAL
# -------------------------------------------------------------
arquivo = joinpath(@__DIR__, "..", "data", "01 MAXIMA NOTURNA_DEZ25.PWF")
resolver_fluxo_controlado(arquivo)