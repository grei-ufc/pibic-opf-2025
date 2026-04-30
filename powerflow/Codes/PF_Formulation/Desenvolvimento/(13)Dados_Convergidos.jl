using PowerModels
using PWF
using Printf
print("\033c") # Limpa o terminal



# 1. Leitura do arquivo PWF
# O pacote PWF.jl estende a função parse_file do PowerModels para aceitar extensões .pwf
caminho_arquivo = joinpath(@__DIR__, "01 MAXIMA NOTURNA_DEZ25.PWF")
data = PWF.parse_file(caminho_arquivo) # Lê o arquivo .pwf

# Extrai a base de potência do sistema (geralmente 100.0 MVA no Brasil)
baseMVA = data["baseMVA"]

# 2. Extração de Tensões (pu)
# Coletamos a magnitude da tensão ('vm') de todas as barras
tensoes = [bus["vm"] for (i, bus) in data["bus"]]
v_min = minimum(tensoes)
v_max = maximum(tensoes)

# 3. Cálculo da Geração Total (pu)
# Somatório da geração ativa ('pg') e reativa ('qg')
pg_total = sum(gen["pg"] for (i, gen) in data["gen"]; init=0.0)
qg_total = sum(gen["qg"] for (i, gen) in data["gen"]; init=0.0)

# 4. Estimativa de Perdas Ativas (pu)
# Como não estamos rodando o fluxo de potência, podemos estimar as perdas totais 
# pela diferença entre a Geração Total e a Carga Total (Demanda).
pd_total = sum(load["pd"] for (i, load) in data["load"]; init=0.0)

# Nota acadêmica: Para sistemas reais, a perda exata também desconta a potência 
# consumida pelos shunts (condutâncias). Aqui usamos a aproximação direta:
perdas_ativas = pg_total - pd_total

# 5. Impressão do Relatório
println("--- RESUMO OPERACIONAL GLOBAL ---")
@printf("Tensão Mínima (pu):         %.4f\n", v_min)
@printf("Tensão Máxima (pu):         %.4f\n", v_max)
@printf("Geração Ativa Total (pu):   %.4f\n", pg_total)
@printf("Geração Reativa Total (pu): %.4f\n", qg_total)
@printf("Perdas Ativas (Total pu):   %.4f\n", perdas_ativas)

println("\n--- RESUMO EM UNIDADES REAIS (Base = %.1f MVA) ---", baseMVA)
@printf("Geração Ativa Total (MW):   %.2f\n", pg_total * baseMVA)
@printf("Geração Reativa Total (MVAr):%.2f\n", qg_total * baseMVA)
@printf("Perdas Ativas Totais (MW):  %.2f\n", perdas_ativas * baseMVA)
