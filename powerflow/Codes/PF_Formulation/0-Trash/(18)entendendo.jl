using PWF
using PowerModels
using JuMP
using Ipopt
using CSV
using DataFrames
using JSON

print("\033c")

caminho_arquivo = joinpath(@__DIR__, "..", "data_CPF", "anarede", "5busfrank_csca.pwf")

# Lemos o arquivo forçando a extração dos dados de controle (CSCA)
data = PWF.parse_file(caminho_arquivo, add_control_data=true)
base_mva = data["baseMVA"]

PowerModels.select_largest_component!(data)


# O número 4 indica a quantidade de espaços da indentação, 
# deixando o visual organizado como aquele dicionário que você me enviou antes.
println(JSON.json(data, 4))

#=
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

=#