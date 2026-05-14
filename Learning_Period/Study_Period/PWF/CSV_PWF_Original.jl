using Pkg
using PWF, PowerModels, Ipopt, Printf, PowerPlots

print("\033c")

# --- Carregar o arquivo ---
file = joinpath(@__DIR__, "3bus.pwf")

# 1. Parse do arquivo PWF
network_data = PWF.parse_pwf_to_powermodels(file)

# 2. Ajuste de Solver
optimizer = Ipopt.Optimizer

println("Executando Fluxo de Potência AC...")

# 3. Rodar o Fluxo de Potência
result = PowerModels.compute_dc_pf(network_data)

# --- Verificação de Convergência ---
if result["termination_status"] == LOCALLY_SOLVED || result["termination_status"] == OPTIMAL
    println(">>> Convergência bem-sucedida! <<<")
else
    println(">>> O solver falhou: $(result["termination_status"]) <<<")
end

println("Atualizando estrutura de dados e gerando CSVs...")

# =======================================================
# CORREÇÃO PRINCIPAL AQUI:
# Atualiza o network_data com a solução ANTES de exportar
# =======================================================
PowerModels.update_data!(network_data, result["solution"])

# =======================================================
# EXPORTAÇÃO PARA CSV
# =======================================================

# 1. Exportar Tensão nas Barras (Buses)
open("resultados_barras.csv", "w") do io
    println(io, "Barra,Tensao_pu,Angulo_graus")
    
    # Agora iteramos sobre network_data, que é garantido ter todos os campos
    buses = sort(collect(keys(network_data["bus"])), by=x->parse(Int, x))

    for bus_id in buses
        data = network_data["bus"][bus_id]
        
        # O update_data! garante que 'vm' e 'va' sejam os valores finais
        vm = data["vm"]
        va_deg = rad2deg(data["va"])
        
        @printf(io, "%s,%.4f,%.4f\n", bus_id, vm, va_deg)
    end
end
println("-> Arquivo 'resultados_barras.csv' criado.")

# 2. Exportar Geração
open("resultados_geracao.csv", "w") do io
    println(io, "ID_Gerador,Pot_Ativa_pu,Pot_Reativa_pu")

    if haskey(network_data, "gen")
        gens = sort(collect(keys(network_data["gen"])), by=x->parse(Int, x))
        for gen_id in gens
            data = network_data["gen"][gen_id]
            
            # Assegura que estamos lendo o valor final (pg e qg são atualizados pelo update_data!)
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
# O network_data já está atualizado, então podemos calcular os fluxos diretamente
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
            @printf(io, "%s,%d,%d,NaN,NaN,NaN,NaN\n", i, f_bus, t_bus)
        end
    end
end
println("-> Arquivo 'resultados_linhas.csv' criado.")

println("\nProcesso finalizado com sucesso.")