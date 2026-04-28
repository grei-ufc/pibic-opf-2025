using CSV
using DataFrames

print("\033c")

# 1. Carregar o arquivo
arquivo = "resultados_linhas_DCPPowerModel.csv"
df = CSV.read(arquivo, DataFrame)

# Função auxiliar para tratar o valor:
# Se for 'missing' ou 'NaN', retorna 0.0. Caso contrário, retorna o valor.
tratar_valor(x) = (ismissing(x) || isnan(x)) ? 0.0 : x

# 2. Somar aplicando o tratamento linha a linha
soma_origem = sum(tratar_valor.(df.P_origem_pu))
soma_destino = sum(tratar_valor.(df.P_destino_pu))

# 3. Exibir os resultados
println("Soma P_origem_pu (sem NaNs): ", soma_origem)
println("Soma P_destino_pu (sem NaNs): ", soma_destino)

# BÔNUS: Se você quiser a soma total das duas colunas juntas
soma_total_global = soma_origem + soma_destino
println("Soma combinada das duas colunas: ", soma_total_global)