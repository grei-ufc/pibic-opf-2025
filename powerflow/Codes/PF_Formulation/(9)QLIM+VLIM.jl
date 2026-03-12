#QLIM + VLIM

using PWF
using PowerModels
using JuMP
using Ipopt
using CSV
using DataFrames

print("\033c") # Limpa o terminal

# =========================================================================
# 0. LEITURA DE DADOS (O Sistema Interligado Nacional)
# =========================================================================
println("1. Lendo arquivo PWF...")
caminho_arquivo = joinpath(@__DIR__, "01 MAXIMA NOTURNA_DEZ25.PWF")

# Lemos o arquivo com o PWF.jl
data = PWF.parse_file(caminho_arquivo) # Lê o arquivo .pwf
base_mva = data["baseMVA"]

# ---> A LINHA MÁGICA DE TOPOLOGIA <---
# Remove todas as ilhas isoladas e mantém apenas o subgrafo principal
PowerModels.select_largest_component!(data)
println("-> Ilhas isoladas removidas! Mantendo apenas a rede principal conectada.")

PowerModels.standardize_cost_terms!(data, order=2) # txt
ref = PowerModels.build_ref(data)[:it][:pm][:nw][0] #txt

# =========================================================================
# 1. INICIALIZAÇÃO DO MODELO E SOLVER
# =========================================================================
# Para o SIN, relaxamos um pouco a tolerância e aumentamos as iterações
model = Model(optimizer_with_attributes(Ipopt.Optimizer, 
    "max_iter" => 3000, 
    "tol" => 1e-5,
    "print_level" => 5 #print level padrão
))

# =========================================================================
# 2. VARIÁVEIS DE ESTADO FÍSICO COM WARM START (VITAL PARA O SIN)
# =========================================================================
println("2. Criando variáveis de estado...")

# Tensão (Magnitude e Ângulo). 
# O "start" pega a tensão inicial do .pwf. Se for um "Flat Start" (v=1, theta=0) no SIN, o Ipopt diverge!
@variable(model, ref[:bus][i]["vmin"] <= vm[i in keys(ref[:bus])] <= ref[:bus][i]["vmax"], start=ref[:bus][i]["vm"]) #Magnitude de Tensão
@variable(model, va[i in keys(ref[:bus])], start=ref[:bus][i]["va"]) #Angulo de Tensão

# Geração Ativa e Reativa
@variable(model, ref[:gen][i]["pmin"] <= pg[i in keys(ref[:gen])] <= ref[:gen][i]["pmax"], start=ref[:gen][i]["pg"])
@variable(model, ref[:gen][i]["qmin"] <= qg[i in keys(ref[:gen])] <= ref[:gen][i]["qmax"], start=ref[:gen][i]["qg"])

# =========================================================================
# 3. A LÓGICA DO FLUXO DE POTÊNCIA (Fixando Pg em barras PV)
# =========================================================================
for (i, gen) in ref[:gen]
    bus_id = gen["gen_bus"]
    if bus_id in keys(ref[:ref_buses])
        # É a barra Slack (Referência). Removemos os limites de Pg!
        if has_lower_bound(pg[i])
            delete_lower_bound(pg[i])
        end
        if has_upper_bound(pg[i])
            delete_upper_bound(pg[i])
        end
    else
        # É barra PV. Fixamos a geração ativa no valor lido do arquivo.
        fix(pg[i], gen["pg"]; force=true)
    end
end

# Fixando o ângulo da barra de referência em zero
for (i, bus) in ref[:ref_buses]
    fix(va[i], 0.0; force=true)
end

# =========================================================================
# 4. VARIÁVEIS DE CONTROLE (QLIM e VLIM)
# =========================================================================
PENALIDADE = 1e6 

# QLIM: Slack de tensão nas barras com geradores (Permite PV virar PQ)
gen_buses = unique([gen["gen_bus"] for (i,gen) in ref[:gen]])
@variable(model, sl_v[i in gen_buses], start=0.0)

# Restrição do QLIM: V = V_setpoint + sl_v
for (i, gen) in ref[:gen]
    bus_id = gen["gen_bus"]
    vm_setpoint = ref[:bus][bus_id]["vm"] # O setpoint desejado pelo ANAREDE
    @constraint(model, vm[bus_id] == vm_setpoint + sl_v[bus_id])
end

# VLIM: Slack de demanda reativa (Permite corte/injeção fictícia de Q)
@variable(model, sl_d[i in keys(ref[:load])], start=0.0)

# =========================================================================
# 5. EQUAÇÕES DE FLUXO NOS RAMOS (Formulação AC Polar)
# =========================================================================
println("3. Montando equações de fluxo de potência (AC Polar)...")

# Agora usamos um único dicionário para P e Q (padrão do PowerModels)
p = Dict(); q = Dict()

for (l, branch) in ref[:branch]
    f = branch["f_bus"]; t = branch["t_bus"]
    g, b = PowerModels.calc_branch_y(branch)
    tr, ti = PowerModels.calc_branch_t(branch)
    tm = branch["tap"]
    g_fr = branch["g_fr"]; b_fr = branch["b_fr"]
    g_to = branch["g_to"]; b_to = branch["b_to"]

    # Usando @NLexpression para que o solver aceite o cos() e sin() nativamente
    p[(l, f, t)] = @NLexpression(model, (g+g_fr)/tm^2 * vm[f]^2 + (-g*tr+b*ti)/tm^2 * (vm[f]*vm[t]*cos(va[f]-va[t])) + (-b*tr-g*ti)/tm^2 * (vm[f]*vm[t]*sin(va[f]-va[t]))) #Equação 9.1
    q[(l, f, t)] = @NLexpression(model, -(b+b_fr)/tm^2 * vm[f]^2 - (-b*tr-g*ti)/tm^2 * (vm[f]*vm[t]*cos(va[f]-va[t])) + (-g*tr+b*ti)/tm^2 * (vm[f]*vm[t]*sin(va[f]-va[t]))) #Equação 9.2
    
    p[(l, t, f)] = @NLexpression(model, (g+g_to) * vm[t]^2 + (-g*tr-b*ti)/tm^2 * (vm[t]*vm[f]*cos(va[t]-va[f])) + (-b*tr+g*ti)/tm^2 * (vm[t]*vm[f]*sin(va[t]-va[f]))) #Equação 10.1
    q[(l, t, f)] = @NLexpression(model, -(b+b_to) * vm[t]^2 - (-b*tr+g*ti)/tm^2 * (vm[t]*vm[f]*cos(va[t]-va[f])) + (-g*tr-b*ti)/tm^2 * (vm[t]*vm[f]*sin(va[t]-va[f]))) #Equação 10.2
end

# =========================================================================
# 6. LEIS DE KIRCHHOFF DOS NÓS (Com injeção do VLIM)
# =========================================================================
println("4. Montando balanço nodal (Leis de Kirchhoff)...")
for (i, bus) in ref[:bus]
    bus_arcs = ref[:bus_arcs][i]
    bus_gens = ref[:bus_gens][i]
    bus_loads = ref[:bus_loads][i]

    # Shunts Fixos
    gs = sum(shunt["gs"] for (k,shunt) in ref[:shunt] if shunt["shunt_bus"] == i; init=0.0)
    bs = sum(shunt["bs"] for (k,shunt) in ref[:shunt] if shunt["shunt_bus"] == i; init=0.0)

    # Demanda Padrão
    pd_nominal = sum(load["pd"] for (k,load) in ref[:load] if load["load_bus"] == i; init=0.0)
    qd_nominal = sum(load["qd"] for (k,load) in ref[:load] if load["load_bus"] == i; init=0.0)

    # Pré-calculamos as somas lineares para facilitar a leitura do @NLconstraint
    p_gen_total = isempty(bus_gens) ? 0.0 : sum(pg[g] for g in bus_gens) #If-else elegante, checa p_gen total do sistema
    q_gen_total = isempty(bus_gens) ? 0.0 : sum(qg[g] for g in bus_gens)
    slack_vlim  = isempty(bus_loads) ? 0.0 : sum(sl_d[l] for l in bus_loads) #Slack_vlim total

    # Balanço Ativo (Atualizado para @NLconstraint e dicionário p unificado)
    @NLconstraint(model, 
        sum(p[a] for a in bus_arcs) == p_gen_total - pd_nominal - gs*vm[i]^2 #Equação 8.1
    )

    # Balanço Reativo (Com o Slack VLIM embutido na carga)
    @NLconstraint(model, 
        sum(q[a] for a in bus_arcs) == q_gen_total - (qd_nominal + slack_vlim) + bs*vm[i]^2 #Equação 8.2
    )
end

# =========================================================================
# 7. FUNÇÃO OBJETIVO DE SOFT-CONSTRAINTS
# =========================================================================
# O objetivo minimiza APENAS o uso das slacks. Se for zero, é o Fluxo de Potência exato do ANAREDE.
@objective(model, Min, 
    PENALIDADE * sum(sl_v[i]^2 for i in keys(sl_v)) + 
    PENALIDADE * sum(sl_d[l]^2 for l in keys(sl_d))
)

# =========================================================================
# 8. RESOLUÇÃO E ESTATÍSTICAS COMPUTACIONAIS
# =========================================================================
println("5. Resolvendo o Fluxo de Potência Controlado...\n")

# Mede o tempo exato (em segundos) que a função de otimização leva para rodar
tempo_total_execucao = @elapsed optimize!(model)

# Extrai métricas do Solver
status_convergencia = termination_status(model)
tempo_solver_interno = solve_time(model) # Tempo apenas dentro do núcleo matemático do Ipopt

println("\n--- ESTATÍSTICAS DE RESOLUÇÃO ---")
println("Status da Convergência: ", status_convergencia)
println("Tempo interno do Solver (Ipopt): ", round(tempo_solver_interno, digits=4), " segundos")
println("Tempo total da execução da função: ", round(tempo_total_execucao, digits=4), " segundos")
println("Erro de Controle (Slacks Ponderadas): ", objective_value(model))

# =========================================================================
# 9. EXPORTAÇÃO DOS RESULTADOS PARA CSV
# =========================================================================
println("\n6. Estruturando dados e gerando arquivos CSV...")

# ---------------------------------------------------------
# A. Criando o DataFrame das BARRAS (Nós)
# ---------------------------------------------------------
df_barras = DataFrame(
    ID_Barra = Int[], Tipo_Barra = Int[], 
    Tensao_Mag_pu = Float64[], Tensao_Ang_graus = Float64[],
    P_Geracao_pu = Float64[], Q_Geracao_pu = Float64[], 
    P_Carga_pu = Float64[], Q_Carga_pu = Float64[],
    Desvio_Tensao_QLIM_pu = Float64[], Corte_Reativo_VLIM_pu = Float64[]
)

for (i, bus) in ref[:bus]
    # Extrai os valores das variáveis de otimização
    v_m = value(vm[i])
    v_a = value(va[i]) * (180.0 / pi) # Converte de radianos para graus

    # Identifica componentes conectados nesta barra
    bus_gens = ref[:bus_gens][i]
    bus_loads = ref[:bus_loads][i]

    # Somatórios de geração (Lembrando que pode haver mais de 1 gerador na mesma barra)
    p_gen = isempty(bus_gens) ? 0.0 : sum(value(pg[g]) for g in bus_gens)
    q_gen = isempty(bus_gens) ? 0.0 : sum(value(qg[g]) for g in bus_gens)

    # Somatórios de carga nominal (Dados fixos do sistema)
    p_load = isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["pd"] for l in bus_loads)
    q_load = isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["qd"] for l in bus_loads)

    # Identifica o esforço das variáveis de controle (Slacks)
    slack_tensao = (i in gen_buses) ? value(sl_v[i]) : 0.0
    slack_reativ = isempty(bus_loads) ? 0.0 : sum(value(sl_d[l]) for l in bus_loads)

    # Salva a linha no DataFrame
    push!(df_barras, (i, bus["bus_type"], v_m, v_a, p_gen, q_gen, p_load, q_load, slack_tensao, slack_reativ))
end

# Salva o arquivo no seu computador
CSV.write("resultados_barras_SIN.csv", df_barras)

# ---------------------------------------------------------
# B. Criando o DataFrame das LINHAS (Ramos/Fluxos)
# ---------------------------------------------------------
df_linhas = DataFrame(
    ID_Linha = Int[], Barra_De = Int[], Barra_Para = Int[],
    P_Fluxo_De_Para_pu = Float64[], Q_Fluxo_De_Para_pu = Float64[],
    P_Fluxo_Para_De_pu = Float64[], Q_Fluxo_Para_De_pu = Float64[],
    Perda_Ativa_pu = Float64[]
)

for (l, branch) in ref[:branch]
    f = branch["f_bus"]
    t = branch["t_bus"]
    
    # Adicione a palavra "local" aqui:
    local val_p_from = value(p[(l, f, t)])
    local val_q_from = value(q[(l, f, t)])
    local val_p_to   = value(p[(l, t, f)])
    local val_q_to   = value(q[(l, t, f)])

    local perdas_p = val_p_from + val_p_to 

    push!(df_linhas, (l, f, t, val_p_from, val_q_from, val_p_to, val_q_to, perdas_p))
end
# Salva o arquivo no seu computador
CSV.write("resultados_fluxos_linhas_SIN.csv", df_linhas)

println("-> Sucesso! Arquivos 'resultados_barras_SIN.csv' e 'resultados_fluxos_linhas_SIN.csv' gerados na pasta do projeto.")

# =========================================================================
# 10. RESUMO OPERACIONAL DO SIN
# =========================================================================
println("\n--- RESUMO OPERACIONAL GLOBAL ---")

# 1. Tensão Mínima e Máxima
# Extraímos os valores de tensão de todas as barras e achamos o min e max
vetor_tensoes = [value(vm[i]) for i in keys(ref[:bus])]
tensao_min = minimum(vetor_tensoes)
tensao_max = maximum(vetor_tensoes)

# 2. Geração Total (Ativa e Reativa)
# Somamos a geração de todas as máquinas conectadas ao sistema
geracao_p_total = sum(value(pg[g]) for g in keys(ref[:gen]); init=0.0)
geracao_q_total = sum(value(qg[g]) for g in keys(ref[:gen]); init=0.0)

# 3. Perdas Ativas Totais na Transmissão
# A perda total é a soma algébrica de (Fluxo_De_Para + Fluxo_Para_De) de todas as linhas e transformadores
perda_p_total = sum(
    value(p[(l, branch["f_bus"], branch["t_bus"])]) + value(p[(l, branch["t_bus"], branch["f_bus"])]) 
    for (l, branch) in ref[:branch]; init=0.0
)

# Imprimindo na tela de forma elegante
println("Tensão Mínima (pu):         ", round(tensao_min, digits=4))
println("Tensão Máxima (pu):         ", round(tensao_max, digits=4))
println("Geração Ativa Total (pu):   ", round(geracao_p_total, digits=4))
println("Geração Reativa Total (pu): ", round(geracao_q_total, digits=4))
println("Perdas Ativas (Total pu):   ", round(perda_p_total, digits=4))

# =========================================================================
# (Opcional) Dica extra: Conversão para MW e MVAr
# =========================================================================
# A base de potência do sistema (S_base) no ANAREDE/PowerModels geralmente é 100 MVA.
# Se quiser exibir também em unidades reais de engenharia, basta multiplicar por data["baseMVA"]
base_mva = data["baseMVA"]
println("\n--- RESUMO EM UNIDADES REAIS (Base = $base_mva MVA) ---")
println("Geração Ativa Total (MW):   ", round(geracao_p_total * base_mva, digits=2))
println("Geração Reativa Total (MVAr):", round(geracao_q_total * base_mva, digits=2))
println("Perdas Ativas Totais (MW):  ", round(perda_p_total * base_mva, digits=2))