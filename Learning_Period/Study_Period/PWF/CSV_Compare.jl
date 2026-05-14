# pega os dados iniciais do arquivo para usar de comparação com os dados após o calculo do fluxo de potência

using PWF, PowerModels, Printf

print("\033c")

# --- Seu código de carregamento (mantido) ---
file = joinpath(@__DIR__, "01 MAXIMA NOTURNA_DEZ25.PWF")
network_data = PWF.parse_pwf_to_powermodels(file)

# Pega a base de potência do sistema (geralmente 100 MVA)
baseMVA = network_data["baseMVA"]

println("Extraindo dados para CSV...")

# =======================================================
# 1. EXTRAÇÃO DE DADOS DAS BARRAS (BUSES)
# =======================================================
open("dados_barras.csv", "w") do io
    # Cabeçalho
    println(io, "ID_Barra,Nome_Barra,Tipo,Tensao_Mag_pu,Angulo_graus,Base_kV")
    
    # Ordena as barras pelo ID numérico para o CSV ficar organizado
    bus_ids = sort(collect(keys(network_data["bus"])), by=x->parse(Int, x))

    for id in bus_ids
        bus = network_data["bus"][id]
        
        # Extração de variáveis
        bus_i = bus["bus_i"]
        name  = strip(bus["name"]) # Remove espaços em branco extras do nome
        type  = bus["bus_type"]    # 1=PQ, 2=PV, 3=Ref
        vm    = bus["vm"]          # Tensão Magnitude
        va    = rad2deg(bus["va"]) # Tensão Ângulo (convertido para graus)
        kv    = bus["base_kv"]
        
        @printf(io, "%d,%s,%d,%.4f,%.4f,%.1f\n", 
                bus_i, name, type, vm, va, kv)
    end
end
println("-> Arquivo 'dados_barras.csv' criado com sucesso.")

# =======================================================
# 2. EXTRAÇÃO DE DADOS DOS GERADORES (GENS)
# =======================================================
open("dados_geradores.csv", "w") do io
    # Cabeçalho
    println(io, "ID_Gerador,ID_Barra,Pot_Ativa_MW,Pot_Reativa_Mvar,P_Max_MW,P_Min_MW,Status")
    
    # Ordena os geradores
    gen_ids = sort(collect(keys(network_data["gen"])), by=x->parse(Int, x))

    for id in gen_ids
        gen = network_data["gen"][id]
        
        # Extração
        gen_i   = gen["index"]
        gen_bus = gen["gen_bus"]
        status  = gen["gen_status"]
        
        # Conversão de pu para MW/Mvar usando a baseMVA
        # (Se quiser em pu, basta remover o `* baseMVA`)
        pg_mw   = gen["pg"] * baseMVA
        qg_mvar = gen["qg"] * baseMVA
        pmax_mw = gen["pmax"] * baseMVA # Cuidado: as vezes o PWF lê pmax direto em MW. Verifique o valor.
        pmin_mw = gen["pmin"] * baseMVA
        
        # Nota sobre PMAX: No seu log, pmax aparece como 999.99 ou 99999.0. 
        # Se parecer alto demais no CSV, é porque o valor original já era um "infinito" prático.
        
        @printf(io, "%d,%d,%.4f,%.4f,%.4f,%.4f,%d\n", 
                gen_i, gen_bus, pg_mw, qg_mvar, pmax_mw, pmin_mw, status)
    end
end
println("-> Arquivo 'dados_geradores.csv' criado com sucesso.")

println("\nProcesso concluído.")