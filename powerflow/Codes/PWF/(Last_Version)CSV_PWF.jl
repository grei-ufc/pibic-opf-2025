using Pkg
using PWF, PowerModels, Ipopt, Printf, PowerPlots

print("\033c")

# --- Carregar o arquivo ---
file = joinpath(@__DIR__, "01 MAXIMA NOTURNA_DEZ25.PWF")

# 1. Parse do arquivo PWF
network_data = PWF.parse_pwf_to_powermodels(file)

# 2. Definição do Método e Solver
optimizer = Ipopt.Optimizer

# --- Mude o método aqui e os arquivos mudarão de nome automaticamente ---
model = ACPPowerModel
# model = DCPPowerModel # Exemplo de outro método

# Captura o nome do método como string (ex: "ACPPowerModel")
model_name = string(model)

println("Executando Fluxo de Potência usando: $model_name ...")

# 3. Rodar o Fluxo de Potência
result = PowerModels.run_pf(network_data, model, optimizer)

# --- Verificação de Convergência ---
if result["termination_status"] == LOCALLY_SOLVED || result["termination_status"] == OPTIMAL
    println(">>> Convergência bem-sucedida! <<<")
else
    println(">>> O solver falhou: $(result["termination_status"]) <<<")
end

println("Atualizando estrutura de dados e gerando CSVs...")

# Atualiza o network_data com a solução
PowerModels.update_data!(network_data, result["solution"])

# =======================================================
# EXPORTAÇÃO PARA CSV (Nomes Dinâmicos)
# =======================================================

# 1. Exportar Tensão nas Barras
# Cria o nome do arquivo dinamicamente
file_barras = "resultados_barras_$(model_name).csv"

open(file_barras, "w") do io
    println(io, "Barra,Tensao_pu,Angulo_graus")
    
    buses = sort(collect(keys(network_data["bus"])), by=x->parse(Int, x))

    for bus_id in buses
        data = network_data["bus"][bus_id]
        
        # Se for DC, 'vm' pode ser sempre 1.0, mas o código funcionará
        vm = data["vm"]
        va_deg = rad2deg(data["va"])
        
        @printf(io, "%s,%.4f,%.4f\n", bus_id, vm, va_deg)
    end
end
println("-> Arquivo '$file_barras' criado.")

# 2. Exportar Geração
file_gen = "resultados_geracao_$(model_name).csv"

open(file_gen, "w") do io
    println(io, "ID_Gerador,Pot_Ativa_pu,Pot_Reativa_pu")

    if haskey(network_data, "gen")
        gens = sort(collect(keys(network_data["gen"])), by=x->parse(Int, x))
        for gen_id in gens
            data = network_data["gen"][gen_id]
            
            pg_pu = data["pg"]
            # Se for DC, qg geralmente é 0 ou ignorado, mas lemos o que estiver lá
            qg_pu = haskey(data, "qg") ? data["qg"] : 0.0
            
            @printf(io, "%s,%.4f,%.4f\n", gen_id, pg_pu, qg_pu)
        end
    else
        println(io, "Nenhum gerador encontrado")
    end
end
println("-> Arquivo '$file_gen' criado.")

# 3. Exportar Fluxo nas Linhas
file_lines = "resultados_linhas_$(model_name).csv"

# Nota: calc_branch_flow_ac é específico para AC. 
# Se usar DC, os valores de Q (reativo) não farão sentido físico ou serão zero/NaN.
flows = PowerModels.calc_branch_flow_ac(network_data)

open(file_lines, "w") do io
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
println("-> Arquivo '$file_lines' criado.")

println("\nProcesso finalizado com sucesso.")