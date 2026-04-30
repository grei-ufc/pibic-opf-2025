# QLIM + VLIM + CSCA (Versão Definitiva com Data Cleaning)

using PWF
using PowerModels
using JuMP
using Ipopt
using CSV
using DataFrames

print("\033c") # Limpa o terminal

# Pasta dedicada aos CSVs (criada automaticamente se não existir)
PASTA_CSV = joinpath(@__DIR__, "resultados_csv") # Caminho da pasta
mkpath(PASTA_CSV) # Cria a pasta caso ela não exista

function resolver_fluxo_controlado(caminho_arquivo)
    # =========================================================================
    # 0. LEITURA DE DADOS E TOPOLOGIA
    # =========================================================================
    println("1. Lendo arquivo PWF...")
    
    # Lemos o arquivo forçando a extração dos dados de controle (CSCA)
    data = PWF.parse_file(caminho_arquivo, add_control_data=true)
    base_mva = data["baseMVA"] # Geralmente 100 MVA
    println(data)
    PowerModels.select_largest_component!(data)
    println("-> Ilhas isoladas removidas! Mantendo apenas a rede principal conectada.")

    PowerModels.standardize_cost_terms!(data, order=2) # Padroniza as funções de custo dos geradores para polinômios de segunda ordem. Embora o foco seja minimizar slacks de controle, o PowerModels exige essa padronização interna para evitar erros durante a montagem do modelo.
 
    # ---> PATCH DE LIMPEZA <---
    # Remove chaves não-numéricas que o PWF adiciona e que quebram o PowerModels (Nenhuma dessas chaves não-numéricas serão importantes para nós, exemplos são "parameters" e "actions")
    for (_, comp_dict) in data # Utilizamos o '_' para a chave, pois apenas o 'comp_dict' (valor) nos interessa
        if comp_dict isa Dict
            chaves_para_remover = String[]
            for (k, v) in comp_dict # Chave k e valor v
                if typeof(v) == Dict{String, Any} && tryparse(Int, k) === nothing #Converte a chave de string para um número Inteiro. Se a chave for "10", ela retorna 10. Se a chave for "parameters", ela retorna nothing.
                    push!(chaves_para_remover, k)
                end
            end
            for k in chaves_para_remover
                delete!(comp_dict, k)
            end
        end
    end

    # Agora o build_ref consegue rodar sem encontrar a letra "p"
    ref = PowerModels.build_ref(data)[:it][:pm][:nw][0] # Processa o dicionário e realiza um mapeamento topológico reverso de alta performance, criando ponteiros $O(1)$

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

    # os valores de "start" vem do arquivo PWF
    @variable(model, ref[:bus][i]["vmin"] <= vm[i in keys(ref[:bus])] <= ref[:bus][i]["vmax"], start=ref[:bus][i]["vm"]) # Magnitude de tensão (Vm) declarada respeitando os limites do arquivo PWF.
    @variable(model, va[i in keys(ref[:bus])], start=ref[:bus][i]["va"]) # Ângulo da Tensão (Va) declarada sem limites definidos

    @variable(model, ref[:gen][i]["pmin"] <= pg[i in keys(ref[:gen])] <= ref[:gen][i]["pmax"], start=ref[:gen][i]["pg"]) # Potência Geração Ativa (Pg) declarada respeitando os limites do arquivo PWF.
    @variable(model, ref[:gen][i]["qmin"] <= qg[i in keys(ref[:gen])] <= ref[:gen][i]["qmax"], start=ref[:gen][i]["qg"]) # Potência Geração Reativa (Pg) declarada respeitando os limites do arquivo PWF.


    # Variáveis dos Elos DC (note-1)
    p_dc = Dict(); q_dc = Dict() # Cria os dicionarios de potencias ativas e reativas
    for (l, dcline) in ref[:dcline] # "l" é o ID da linha e "dcline" é o dicionário contendo os parâmetros físicos dela.
        f = dcline["f_bus"]; t = dcline["t_bus"] # Extrai os identificadores das barras "from" (retificadora) e "to" (inversora).
        
        p_dc[(l, f, t)] = @variable(model, start=dcline["pf"]) # Cria uma variável de injeção de potência ativa para o lado from do elo.
        p_dc[(l, t, f)] = @variable(model, start=dcline["pt"]) # // to do elo
        q_dc[(l, f, t)] = @variable(model, start=dcline["qf"]) # // potência reativa para o lado from do elo
        q_dc[(l, t, f)] = @variable(model, start=dcline["qt"]) # // to do elo
        
        # A função fix do JuMP transforma uma variável recém-criada em uma constante, cravando seu valor e removendo-a dos graus de liberdade do otimizador. O force=true assegura que, mesmo se a variável tivesse limites definidos anteriormente, o valor cravado se sobrepõe a eles.
        fix(p_dc[(l, f, t)], dcline["pf"]; force=true) 
        fix(p_dc[(l, t, f)], dcline["pt"]; force=true)
        fix(q_dc[(l, f, t)], dcline["qf"]; force=true)
        fix(q_dc[(l, t, f)], dcline["qt"]; force=true)
    end

    # Variáveis dos Shunts (CSCA - Agora extraindo dados de controle) (note-2)
    @variable(model, bs_var[i in keys(ref[:shunt])]) # Cria um vetor de variáveis de decisão contínuas, indexado pelos IDs de todos os elementos shunt da rede.
    @variable(model, sl_bsh[i in keys(ref[:shunt])], start=0.0) # Slack de variação do shuntn do seu valor padrão
    for (i, shunt) in ref[:shunt]
        bmin = shunt["bs"] # primeiro assumimos os valores do shunt fixos e iguais ao valor inicial caso não exista a informação no arquivo PWF sobre min e max.
        bmax = shunt["bs"]
        
        # Se os dados de controle do ANAREDE existirem, nós atualizamos os limites!
        if haskey(shunt, "control_data") && haskey(shunt["control_data"], "bsmin")
            bmin = shunt["control_data"]["bsmin"]
            bmax = shunt["control_data"]["bsmax"]
        end
        
        real_bmin = min(bmin, bmax, shunt["bs"])
        real_bmax = max(bmin, bmax, shunt["bs"])
        
        set_lower_bound(bs_var[i], real_bmin) # seta o lower bound de bs_var para cada i
        set_upper_bound(bs_var[i], real_bmax)
        set_start_value(bs_var[i], shunt["bs"]) # warm start no valor inicial presente no PWF

        # (Eq. 3.4 do artigo): Conecta a variável física ao slack
        @constraint(model, bs_var[i] == shunt["bs"] + sl_bsh[i])  
        
        # Se não houver margem de controle, cravamos o valor fixo original
        if real_bmin == real_bmax
            fix(bs_var[i], shunt["bs"]; force=true)
        end
    end

    # =========================================================================
    # 3. LÓGICA DO FLUXO DE POTÊNCIA NAS MÁQUINAS
    # =========================================================================
    for (i, gen) in ref[:gen] # Itera sobre todos os geradores físicos da rede.
        if gen["gen_bus"] in keys(ref[:ref_buses]) # verifica se o gerador é uma barra slack e se for deleta os limites de potência.
            if has_lower_bound(pg[i]) delete_lower_bound(pg[i]) end
            if has_upper_bound(pg[i]) delete_upper_bound(pg[i]) end
        else
            fix(pg[i], gen["pg"]; force=true) # se não for slack fixa sua potência no valor presente no PWF
        end
    end

    for (i, bus) in ref[:ref_buses]
        fix(va[i], 0.0; force=true) # Fixa o angulo das barras slack em zero.
    end

    # =========================================================================
    # 4. VARIÁVEIS E RESTRIÇÕES DE CONTROLE (QLIM, VLIM e CSCA)
    # =========================================================================
    PENALIDADE = 1e6 
    PENALIDADE_MENOR = 1e4 # Para garantir que o solver prefira mover o shunt a violar tensão

    # Identifica barras com Geradores
    gen_buses = [gen["gen_bus"] for (i,gen) in ref[:gen]]
    
    # Identifica barras com Shunts que possuem margem real de controle (CSCA)
    shunt_buses = [
        shunt["shunt_bus"] for (i,shunt) in ref[:shunt] 
        if haskey(shunt, "control_data") && haskey(shunt["control_data"], "bsmin") && shunt["control_data"]["bsmin"] != shunt["control_data"]["bsmax"]
    ]
    
    controlled_buses = unique(vcat(gen_buses, shunt_buses))

    # --- DECLARAÇÃO DOS SLACKS DE TENSÃO ---
    @variable(model, sl_v[i in controlled_buses], start=0.0) # Modo contínuo (setpoint)
    @variable(model, sl_v_upp[i in controlled_buses] >= 0.0, start=0.0) # Modo discreto (limite superior)
    @variable(model, sl_v_low[i in controlled_buses] >= 0.0, start=0.0) # Modo discreto (limite inferior)

    # --- PASSO B: SEPARAÇÃO DOS MODOS CONTÍNUO E DISCRETO ---
    for bus_id in controlled_buses
        bus_data = ref[:bus][bus_id]
        
        # Extrai os limites de tensão de controle se existirem no dicionário da barra
        if haskey(bus_data, "control_data") && haskey(bus_data["control_data"], "vmmin")
            vm_min_ctrl = bus_data["control_data"]["vmmin"]
            vm_max_ctrl = bus_data["control_data"]["vmmax"]
        else
            # Para geradores (QLIM) ou se não houver dados específicos, assume o setpoint nominal
            vm_min_ctrl = bus_data["vm"]
            vm_max_ctrl = bus_data["vm"]
        end

        # Lógica de Separação: 
        # Se a diferença entre o min e o max for muito pequena, é um setpoint cravado (Modo Contínuo)
        if abs(vm_max_ctrl - vm_min_ctrl) < 1e-5
            @constraint(model, vm[bus_id] == vm_max_ctrl + sl_v[bus_id])
        else
            # Se houver uma faixa, aplica a banda de controle (Modo Discreto)
            @constraint(model, vm[bus_id] >= vm_min_ctrl - sl_v_low[bus_id])
            @constraint(model, vm[bus_id] <= vm_max_ctrl + sl_v_upp[bus_id])
        end
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
    PENALIDADE * sum(sl_v_upp[i]^2 + sl_v_low[i]^2 for i in keys(sl_v_upp)) +
    PENALIDADE * sum(sl_d[l]^2 for l in keys(sl_d)) +
    PENALIDADE_MENOR * sum(sl_bsh[k]^2 for k in keys(sl_bsh)) 
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

    # =========================================================================
    # 10. EXPORTAÇÃO DOS RESULTADOS PARA CSV
    # =========================================================================
    println("\n6. Estruturando dados e gerando arquivos CSV...")

    gen_buses_set = unique([gen["gen_bus"] for (i, gen) in ref[:gen]])

    df_barras = DataFrame(
        ID_Barra = Int[], Tipo_Barra = Int[],
        Tensao_Mag_pu = Float64[], Tensao_Ang_graus = Float64[],
        P_Geracao_pu = Float64[], Q_Geracao_pu = Float64[],
        P_Carga_pu = Float64[], Q_Carga_pu = Float64[],
        Desvio_Tensao_QLIM_pu = Float64[], Corte_Reativo_VLIM_pu = Float64[]
    )

    for (i, bus) in ref[:bus]
        bus_gens = ref[:bus_gens][i]
        bus_loads = ref[:bus_loads][i]
        push!(df_barras, (
            i, bus["bus_type"], value(vm[i]), value(va[i]) * (180.0 / pi),
            isempty(bus_gens) ? 0.0 : sum(value(pg[g]) for g in bus_gens),
            isempty(bus_gens) ? 0.0 : sum(value(qg[g]) for g in bus_gens),
            isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["pd"] for l in bus_loads),
            isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["qd"] for l in bus_loads),
            (i in keys(sl_v)) ? value(sl_v[i]) : 0.0,
            isempty(bus_loads) ? 0.0 : sum(value(sl_d[l]) for l in bus_loads)
        ))
    end
    sort!(df_barras, :ID_Barra)
    CSV.write(joinpath(PASTA_CSV, "resultados_barras_SIN.csv"), df_barras)

    df_linhas = DataFrame(
        ID_Linha = Int[], Barra_De = Int[], Barra_Para = Int[],
        P_Fluxo_De_Para_pu = Float64[], Q_Fluxo_De_Para_pu = Float64[],
        P_Fluxo_Para_De_pu = Float64[], Q_Fluxo_Para_De_pu = Float64[],
        Perda_Ativa_pu = Float64[]
    )

    for (l, branch) in ref[:branch]
        f = branch["f_bus"]; t = branch["t_bus"]
        val_p_from = value(p[(l, f, t)]); val_q_from = value(q[(l, f, t)])
        val_p_to   = value(p[(l, t, f)]); val_q_to   = value(q[(l, t, f)])
        push!(df_linhas, (l, f, t, val_p_from, val_q_from, val_p_to, val_q_to, val_p_from + val_p_to))
    end
    sort!(df_linhas, :ID_Linha)
    CSV.write(joinpath(PASTA_CSV, "resultados_fluxos_linhas_SIN.csv"), df_linhas)
    println("-> Arquivos CSV gerados em $PASTA_CSV")
end

# -------------------------------------------------------------
# EXECUÇÃO PRINCIPAL
# -------------------------------------------------------------
#arquivo = joinpath(@__DIR__, "..", "data_CPF", "anarede", "5busfrank_csca.pwf") # Ajuste o caminho se necessário
arquivo = joinpath(@__DIR__, "..", "data_CPF", "anarede", "5busfrank_csca.pwf")
resolver_fluxo_controlado(arquivo)