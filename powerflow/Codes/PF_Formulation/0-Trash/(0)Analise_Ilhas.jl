using PWF
using PowerModels

print("\033c") # Limpa o terminal

# 1. Leitura dos Dados
println("Lendo arquivo PWF para análise topológica...")
caminho_arquivo = joinpath(@__DIR__, "01 MAXIMA NOTURNA_DEZ25.PWF")
data = PWF.parse_file(caminho_arquivo)


# 2. Mapeamento de Ilhas (Componentes Conexos do Grafo)
# Esta função varre a rede e retorna grupos (Sets) de barras que estão fisicamente conectadas
ilhas = PowerModels.calc_connected_components(data)

# Ordenamos as ilhas por tamanho (da maior para a menor)
# A Ilha Principal do SIN será sempre a primeira da lista (a gigante)
ilhas_ordenadas = sort(collect(ilhas), by=length, rev=true)

ilha_principal = ilhas_ordenadas[1]
println("\n✅ TOPOLOGIA MAPEADA!")
println("A Ilha Principal possui $(length(ilha_principal)) barras conectadas entre si.")

# 3. Diagnóstico das Ilhas Isoladas
if length(ilhas_ordenadas) > 1
    qtd_ilhas_isoladas = length(ilhas_ordenadas) - 1
    println("\n⚠️ ALERTA: Foram encontradas $qtd_ilhas_isoladas ilhas fisicamente isoladas da rede principal!")
    
    # Analisando cada ilha isolada
    for (idx, ilha) in enumerate(ilhas_ordenadas[2:end])
        println("\n-------------------------------------------------")
        println("🔴 ILHA ISOLADA $idx (Tamanho: $(length(ilha)) barras)")
        
        # Vamos contar o total de P de carga e P de geração nesta ilha
        carga_total_ilha = 0.0
        geracao_total_ilha = 0.0
        
        println("Barras pertencentes a esta ilha:")
        for bus_id in ilha
            # Descobre o nome da barra no arquivo
            bus_name = haskey(data["bus"], "$bus_id") ? data["bus"]["$bus_id"]["name"] : "Desconhecida"
            
            # Verifica as cargas conectadas a esta barra
            carga_barra = sum(l["pd"] for (k,l) in data["load"] if l["load_bus"] == bus_id; init=0.0)
            carga_total_ilha += carga_barra
            
            # Verifica os geradores conectados a esta barra
            geracao_barra = sum(g["pmax"] for (k,g) in data["gen"] if g["gen_bus"] == bus_id; init=0.0)
            geracao_total_ilha += geracao_barra
            
            println("  -> Barra $bus_id ($bus_name) | Carga: $(round(carga_barra*data["baseMVA"], digits=1)) MW | Geração Max: $(round(geracao_barra*data["baseMVA"], digits=1)) MW")
        end
        
        # O Veredito de Inviabilidade
        println("\nDiagnóstico desta ilha:")
        if carga_total_ilha > 0.0 && geracao_total_ilha == 0.0
            println("❌ ERRO GRAVE: A ilha tem carga mas NENHUM gerador! Isso quebra o Fluxo de Potência.")
        elseif carga_total_ilha > geracao_total_ilha
            println("⚠️ AVISO: A ilha tem geradores, mas a capacidade máxima deles não atende à carga.")
        else
            println("✔️ Microrrede viável: A ilha tem geração suficiente para se sustentar sozinha.")
        end
    end
else
    println("\n✅ Parabéns! O seu sistema é um grafo perfeito e totalmente conectado. Nenhuma barra isolada!")
end