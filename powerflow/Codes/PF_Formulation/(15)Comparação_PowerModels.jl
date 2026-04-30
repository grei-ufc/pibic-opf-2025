# Roda run_ac_pf oficial e exporta CSVs. Útil para benchmark contra suas formulações.

using PWF
using PowerModels
using Ipopt
using CSV
using DataFrames

print("\033c") # Limpa o terminal

# =========================================================================
# 0. LEITURA DE DADOS
# =========================================================================
println("1. Lendo arquivo PWF...")
caminho_arquivo = joinpath(@__DIR__, "..", "data_CPF", "anarede", "5busfrank_csca.pwf") # Ajuste o caminho se necessário

data = PWF.parse_file(caminho_arquivo)
base_mva = data["baseMVA"]

PowerModels.select_largest_component!(data)
PowerModels.standardize_cost_terms!(data, order=2)

# =========================================================================
# 1. CONFIGURAÇÃO DO SOLVER
# =========================================================================
optimizer = optimizer_with_attributes(Ipopt.Optimizer, 
    "max_iter" => 3000, 
    "tol" => 1e-5,
    "print_level" => 0 # Mudei para 0 para o terminal ficar limpo igual ao seu exemplo
)

# =========================================================================
# 2. RESOLUÇÃO E ESTATÍSTICAS COMPUTACIONAIS
# =========================================================================
println("\n5. Resolvendo o Fluxo de Potência do PowerModels (AC Polar)...\n")

# A macro @elapsed mede o tempo total da chamada da função
tempo_total_execucao = @elapsed begin
    resultado_pm = run_ac_pf(data, optimizer)
end

status_convergencia = resultado_pm["termination_status"]
tempo_solver_interno = resultado_pm["solve_time"]

# No Fluxo de Potência tradicional (sem slacks flexíveis), o objetivo é 0 (dummy variable).
erro_controle = resultado_pm["objective"] 

println("EXIT: Optimal Solution Found.\n")
println("--- ESTATÍSTICAS DE RESOLUÇÃO ---")
println("Status da Convergência: ", status_convergencia)
println("Tempo interno do Solver (Ipopt): ", round(tempo_solver_interno, digits=4), " segundos")
println("Tempo total da execução da função: ", round(tempo_total_execucao, digits=4), " segundos")
println("Erro de Controle (Slacks Ponderadas): ", erro_controle)

# =========================================================================
# 3. EXPORTAÇÃO DOS RESULTADOS PARA CSV
# =========================================================================
println("\n6. Estruturando dados e gerando arquivos CSV...")

# --- A. DataFrame das BARRAS ---
df_barras = DataFrame(
    ID_Barra = Int[], Tipo_Barra = Int[], 
    Tensao_Mag_pu = Float64[], Tensao_Ang_graus = Float64[],
    P_Geracao_pu = Float64[], Q_Geracao_pu = Float64[], 
    P_Carga_pu = Float64[], Q_Carga_pu = Float64[],
    Desvio_Tensao_QLIM_pu = Float64[], Corte_Reativo_VLIM_pu = Float64[]
)

tensao_min = Inf
tensao_max = -Inf

for (i, bus_sol) in resultado_pm["solution"]["bus"]
    bus_id = parse(Int, i)
    v_m = bus_sol["vm"]
    v_a = bus_sol["va"] * (180.0 / pi)
    
    # Atualiza as métricas globais de tensão
    global tensao_min = min(tensao_min, v_m)
    global tensao_max = max(tensao_max, v_m)

    # Coleta Geração conectada à barra
    p_gen = 0.0; q_gen = 0.0
    if haskey(resultado_pm["solution"], "gen")
        for (g, gen_sol) in resultado_pm["solution"]["gen"]
            if data["gen"][g]["gen_bus"] == bus_id
                p_gen += gen_sol["pg"]
                q_gen += gen_sol["qg"]
            end
        end
    end

    # Coleta Carga conectada à barra a partir do dicionário original 'data'
    p_load = 0.0; q_load = 0.0
    for (l, load_data) in data["load"]
        if load_data["load_bus"] == bus_id
            p_load += load_data["pd"]
            q_load += load_data["qd"]
        end
    end

    # As Slacks em uma formulação tradicional (PowerModels puro) não existem (são 0)
    slack_tensao = 0.0
    slack_reativ = 0.0

    push!(df_barras, (bus_id, data["bus"][i]["bus_type"], v_m, v_a, p_gen, q_gen, p_load, q_load, slack_tensao, slack_reativ))
end
sort!(df_barras, :ID_Barra)
CSV.write("resultados_barras_PM.csv", df_barras)

# ---------------------------------------------------------
# B. Criando o DataFrame das LINHAS (Ramos/Fluxos)
# ---------------------------------------------------------
df_linhas = DataFrame(
    ID_Linha = Int[], Barra_De = Int[], Barra_Para = Int[],
    P_Fluxo_De_Para_pu = Float64[], Q_Fluxo_De_Para_pu = Float64[],
    P_Fluxo_Para_De_pu = Float64[], Q_Fluxo_Para_De_pu = Float64[],
    Perda_Ativa_pu = Float64[]
)

perda_p_total = 0.0

# Em vez de ler da solução (que não tem os ramos), lemos do dicionário de dados (topologia original)
for (l, branch) in data["branch"]
    l_idx = parse(Int, l)
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]

    # 1. Pegamos a tensão e o ângulo das barras DE e PARA já solucionadas pelo PowerModels
    v_m_f = resultado_pm["solution"]["bus"][string(f_bus)]["vm"]
    v_a_f = resultado_pm["solution"]["bus"][string(f_bus)]["va"]
    
    v_m_t = resultado_pm["solution"]["bus"][string(t_bus)]["vm"]
    v_a_t = resultado_pm["solution"]["bus"][string(t_bus)]["va"]

    # 2. Extraímos os parâmetros do modelo Pi equivalente da linha (g, b, tap, shunts)
    g, b = PowerModels.calc_branch_y(branch)
    tr, ti = PowerModels.calc_branch_t(branch)
    tm = branch["tap"]
    g_fr = branch["g_fr"]; b_fr = branch["b_fr"]
    g_to = branch["g_to"]; b_to = branch["b_to"]

    # 3. Calculamos manualmente o fluxo (exatamente com as equações AC Polar do seu código JuMP!)
    
    # Sentido De -> Para
    val_p_from =  (g+g_fr)/tm^2 * v_m_f^2 + (-g*tr+b*ti)/tm^2 * (v_m_f*v_m_t*cos(v_a_f-v_a_t)) + (-b*tr-g*ti)/tm^2 * (v_m_f*v_m_t*sin(v_a_f-v_a_t))
    val_q_from = -(b+b_fr)/tm^2 * v_m_f^2 - (-b*tr-g*ti)/tm^2 * (v_m_f*v_m_t*cos(v_a_f-v_a_t)) + (-g*tr+b*ti)/tm^2 * (v_m_f*v_m_t*sin(v_a_f-v_a_t))
    
    # Sentido Para -> De
    val_p_to   =  (g+g_to) * v_m_t^2 + (-g*tr-b*ti)/tm^2 * (v_m_t*v_m_f*cos(v_a_t-v_a_f)) + (-b*tr+g*ti)/tm^2 * (v_m_t*v_m_f*sin(v_a_t-v_a_f))
    val_q_to   = -(b+b_to) * v_m_t^2 - (-b*tr+g*ti)/tm^2 * (v_m_t*v_m_f*cos(v_a_t-v_a_f)) + (-g*tr-b*ti)/tm^2 * (v_m_t*v_m_f*sin(v_a_t-v_a_f))

    # Perda total da linha é a soma algébrica das injeções
    perdas_p = val_p_from + val_p_to 
    global perda_p_total += perdas_p

    push!(df_linhas, (l_idx, f_bus, t_bus, val_p_from, val_q_from, val_p_to, val_q_to, perdas_p))
end

# Ordena o DataFrame pelo ID da Linha
sort!(df_linhas, :ID_Linha)
CSV.write("resultados_fluxos_linhas_PM.csv", df_linhas)

# =========================================================================
# 4. RESUMO OPERACIONAL E FÍSICO
# =========================================================================
# Somatório da geração total usando a solução devolvida pelo solver
geracao_p_total = sum(gen["pg"] for (i, gen) in resultado_pm["solution"]["gen"]; init=0.0)
geracao_q_total = sum(gen["qg"] for (i, gen) in resultado_pm["solution"]["gen"]; init=0.0)

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