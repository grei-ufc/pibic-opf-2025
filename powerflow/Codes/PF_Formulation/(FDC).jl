# Roda solve_dc_opf oficial sobre CASO_VER_MAXDIU.PWF (PAR/PEL 2027-2031) e exporta CSVs.
# Aproximacao DC do PowerModels com orcamento ampliado de iteracoes (max_iter = 20000).

using PWF
using PowerModels
using Ipopt
using JuMP
using CSV
using DataFrames

print("\033c") # Limpa o terminal

# =========================================================================
# 0. LEITURA DE DADOS
# =========================================================================
println("1. Lendo arquivo PWF...")
caminho_arquivo = joinpath(@__DIR__, "..", "data", "CASO_VER_MAXDIU.PWF")

data = PWF.parse_file(caminho_arquivo)
base_mva = data["baseMVA"]

PowerModels.select_largest_component!(data)

# Identifica todas as barras definidas como referência (bus_type == 3)
ref_buses = [b_dict for (b_id, b_dict) in data["bus"] if b_dict["bus_type"] == 3]

#=
# Se houver mais de 1, mantemos apenas a primeira e convertemos o resto para PV (Tipo 2)
if length(ref_buses) > 1
    println("-> Aviso: Múltiplas barras de referência detectadas. Convertendo excedentes para PV (Tipo 2)...")
    for i in 2:length(ref_buses)
        ref_buses[i]["bus_type"] = 2
    end
end
=#

PowerModels.standardize_cost_terms!(data, order=2)

# =========================================================================
# 1. CONFIGURAÇÃO DO SOLVER
# =========================================================================
optimizer = optimizer_with_attributes(Ipopt.Optimizer,
    "max_iter" => 20000,
    "tol" => 1e-5,
    "print_level" => 5
)

# =========================================================================
# 2. RESOLUÇÃO E ESTATÍSTICAS COMPUTACIONAIS
# =========================================================================
println("\n2. Resolvendo o Fluxo de Potência Ótimo do PowerModels (aproximação DC)...\n")

tempo_total_execucao = @elapsed begin
    resultado_pm = solve_dc_pf(data, optimizer)
end

status_convergencia = resultado_pm["termination_status"]
tempo_solver_interno = resultado_pm["solve_time"]
custo_dc            = resultado_pm["objective"]

println("\n--- ESTATÍSTICAS DE RESOLUÇÃO ---")
println("Status da Convergência: ", status_convergencia)
println("Tempo interno do Solver (Ipopt): ", round(tempo_solver_interno, digits=4), " segundos")
println("Tempo total da execução da função: ", round(tempo_total_execucao, digits=4), " segundos")
println("Custo Total (DC-OPF, US\$/h):    ", custo_dc)

# =========================================================================
# 3. EXPORTAÇÃO DOS RESULTADOS PARA CSV
# =========================================================================
println("\n3. Estruturando dados e gerando arquivos CSV...")

# --- A. DataFrame das BARRAS ---
# Observação: na aproximação DC, vm = 1.0 p.u. para todas as barras e qg não é variável
# de decisão. Os campos de tensão e reativos são preenchidos com esses valores nominais
# para manter a compatibilidade de colunas com os CSVs das demais formulações.
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
    v_m = get(bus_sol, "vm", 1.0)               # DC: tensão assumida = 1.0 p.u.
    v_a = get(bus_sol, "va", 0.0) * (180.0 / pi)

    global tensao_min = min(tensao_min, v_m)
    global tensao_max = max(tensao_max, v_m)

    # Coleta Geração conectada à barra
    p_gen = 0.0; q_gen = 0.0
    if haskey(resultado_pm["solution"], "gen")
        for (g, gen_sol) in resultado_pm["solution"]["gen"]
            if data["gen"][g]["gen_bus"] == bus_id
                p_gen += get(gen_sol, "pg", 0.0)
                q_gen += get(gen_sol, "qg", 0.0)   # DC: ausente, fica 0
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

    # Não há slacks de tensão/reativo em PowerModels puro
    slack_tensao = 0.0
    slack_reativ = 0.0

    push!(df_barras, (bus_id, data["bus"][i]["bus_type"], v_m, v_a, p_gen, q_gen, p_load, q_load, slack_tensao, slack_reativ))
end
sort!(df_barras, :ID_Barra)
CSV.write("resultados_barras_DC.csv", df_barras)

# ---------------------------------------------------------
# B. DataFrame das LINHAS (Ramos/Fluxos) - aproximação DC
# ---------------------------------------------------------
# Na aproximação DC, p_ij = -b * (θ_i - θ_j) e p_ji = -p_ij (sem perdas, sem reativo).
df_linhas = DataFrame(
    ID_Linha = Int[], Barra_De = Int[], Barra_Para = Int[],
    P_Fluxo_De_Para_pu = Float64[], Q_Fluxo_De_Para_pu = Float64[],
    P_Fluxo_Para_De_pu = Float64[], Q_Fluxo_Para_De_pu = Float64[],
    Perda_Ativa_pu = Float64[]
)

perda_p_total = 0.0
bus_sol = resultado_pm["solution"]["bus"]
branch_sol = get(resultado_pm["solution"], "branch", Dict())
ramos_descartados = 0

for (l, branch) in data["branch"]
    l_idx = parse(Int, l)
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]

    # Pula ramos desativados ou cujos terminais foram removidos por select_largest_component!
    if get(branch, "br_status", 1) == 0 || !haskey(bus_sol, string(f_bus)) || !haskey(bus_sol, string(t_bus))
        global ramos_descartados += 1
        continue
    end

    # Prefere o fluxo escrito pelo próprio PowerModels (solution["branch"][l]["pf"]/"pt")
    # Se não estiver disponível, recai sobre o cálculo direto a partir dos ângulos.
    if haskey(branch_sol, l)
        val_p_from = get(branch_sol[l], "pf", NaN)
        val_p_to   = get(branch_sol[l], "pt", -val_p_from)
    else
        v_a_f = get(bus_sol[string(f_bus)], "va", 0.0)
        v_a_t = get(bus_sol[string(t_bus)], "va", 0.0)
        _, b  = PowerModels.calc_branch_y(branch)
        tm    = branch["tap"]
        val_p_from = -b / tm * (v_a_f - v_a_t)
        val_p_to   = -val_p_from
    end

    # DC não modela reativos nem perdas ativas (p_from + p_to ≈ 0).
    val_q_from = 0.0
    val_q_to   = 0.0
    perdas_p   = val_p_from + val_p_to
    global perda_p_total += perdas_p

    push!(df_linhas, (l_idx, f_bus, t_bus, val_p_from, val_q_from, val_p_to, val_q_to, perdas_p))
end

sort!(df_linhas, :ID_Linha)
CSV.write("resultados_fluxos_linhas_DC.csv", df_linhas)
if ramos_descartados > 0
    println("Ramos descartados (status=0 ou barra fora da maior componente): ", ramos_descartados)
end

# =========================================================================
# 4. RESUMO OPERACIONAL E FÍSICO
# =========================================================================
geracao_p_total = sum(get(gen, "pg", 0.0) for (i, gen) in resultado_pm["solution"]["gen"]; init=0.0)
geracao_q_total = sum(get(gen, "qg", 0.0) for (i, gen) in resultado_pm["solution"]["gen"]; init=0.0)

println("\n--- RESUMO OPERACIONAL GLOBAL (DC) ---")
println("Tensão Mínima (pu):         ", round(tensao_min, digits=4), "   (DC: nominal = 1.0)")
println("Tensão Máxima (pu):         ", round(tensao_max, digits=4), "   (DC: nominal = 1.0)")
println("Geração Ativa Total (pu):   ", round(geracao_p_total, digits=4))
println("Geração Reativa Total (pu): ", round(geracao_q_total, digits=4), "   (DC: não modelada)")
println("Perdas Ativas (Total pu):   ", round(perda_p_total, digits=4), "   (DC: desprezadas)")

println("\n--- RESUMO EM UNIDADES REAIS (Base = $base_mva MVA) ---")
println("Geração Ativa Total (MW):    ", round(geracao_p_total * base_mva, digits=2))
println("Geração Reativa Total (MVAr):", round(geracao_q_total * base_mva, digits=2))
println("Perdas Ativas Totais (MW):   ", round(perda_p_total * base_mva, digits=2))
