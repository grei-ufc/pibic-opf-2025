using Pkg
using PWF, PowerModels, Ipopt, Printf, PowerPlots

print("\033c")

# --- Carregar o arquivo ---
file = joinpath(@__DIR__, "30_PD 2034 - MÁXIMA DIURNA.PWF")

# 1. Parse do arquivo PWF para o dicionário do PowerModels
network_data = PWF.parse_pwf_to_powermodels(file)

# 2. Verificar e corrigir a topologia
println("Removendo ilhas isoladas e componentes desconectados...")
PowerModels.select_largest_component!(network_data)
PowerModels.propagate_topology_status!(network_data)

# 3. Ajuste de Solver
optimizer = optimizer_with_attributes(Ipopt.Optimizer, "print_level"=>0, "max_iter"=>3000)

println("Executando Fluxo de Potência AC...")

# 4. Rodar o Fluxo de Potência
result = run_ac_pf(network_data, optimizer)

# --- Verificação de Convergência ---
if result["termination_status"] == LOCALLY_SOLVED || result["termination_status"] == OPTIMAL
    println(">>> Convergência bem-sucedida! <<<")
else
    println(">>> O solver falhou: $(result["termination_status"]) <<<")
    # Se falhar, você pode adicionar lógica de saída aqui se desejar
end

println("Gerando arquivos CSV...")

# =======================================================
# EXPORTAÇÃO PARA CSV
# =======================================================

# 1. Exportar Tensão nas Barras (Buses)
open("resultados_barras.csv", "w") do io
    # Cabeçalho do CSV
    println(io, "Barra,Tensao_pu,Angulo_graus")
    
    buses = sort(collect(keys(result["solution"]["bus"])), by=x->parse(Int, x))

    for bus_id in buses
        data = result["solution"]["bus"][bus_id]
        vm = data["vm"]
        va_deg = rad2deg(data["va"])
        
        # Escreve no arquivo 'io' separado por vírgulas
        @printf(io, "%s,%.4f,%.4f\n", bus_id, vm, va_deg)
    end
end
println("-> Arquivo 'resultados_barras.csv' criado.")

# 2. Exportar Geração
open("resultados_geracao.csv", "w") do io
    println(io, "ID_Gerador,Pot_Ativa_pu,Pot_Reativa_pu")

    if haskey(result["solution"], "gen")
        gens = sort(collect(keys(result["solution"]["gen"])), by=x->parse(Int, x))
        for gen_id in gens
            data = result["solution"]["gen"][gen_id]
            pg_pu = data["pg"]
            qg_pu = data["qg"]
            
            @printf(io, "%s,%.4f,%.4f\n", gen_id, pg_pu, qg_pu)
        end
    else
        println(io, "Nenhum gerador encontrado")
    end
end
println("-> Arquivo 'resultados_geracao.csv' criado.")

# 3. Exportar Fluxo nas Linhas (Branches)
# Primeiro calculamos os fluxos (lógica mantida do seu código original)
PowerModels.update_data!(network_data, result["solution"])
flows = PowerModels.calc_branch_flow_ac(network_data)

open("resultados_linhas.csv", "w") do io
    println(io, "ID_Linha,De_Barra,Para_Barra,P_origem_pu,Q_origem_pu,P_destino_pu,Q_destino_pu")

    branch_ids = sort(collect(keys(network_data["branch"])), by=x->parse(Int, x))

    for i in branch_ids
        branch_topo = network_data["branch"][i]
        f_bus = branch_topo["f_bus"]
        t_bus = branch_topo["t_bus"]
        
        if haskey(flows["branch"], i)
            branch_res = flows["branch"][i]
            pf = branch_res["pf"]
            qf = branch_res["qf"]
            pt = branch_res["pt"]
            qt = branch_res["qt"]
            
            @printf(io, "%s,%d,%d,%.4f,%.4f,%.4f,%.4f\n", 
                    i, f_bus, t_bus, pf, qf, pt, qt)
        else
            # Caso não haja fluxo calculado (ex: linha desligada), preenche com NaN ou zero
            @printf(io, "%s,%d,%d,NaN,NaN,NaN,NaN\n", i, f_bus, t_bus)
        end
    end
end
println("-> Arquivo 'resultados_linhas.csv' criado.")

println("\nProcesso finalizado com sucesso.")










println("=======================================================")

# ==========================================
# PARTE GRÁFICA: Visualização da Topologia
# ==========================================

#=
println("\nGerando gráfico da rede...")

p = powerplot(network_data, basic=true, width=600, height=500)

display(p)
=#
