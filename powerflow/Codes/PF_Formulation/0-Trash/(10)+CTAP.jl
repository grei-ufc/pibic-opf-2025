using PWF
using PowerModels
using JuMP
using Ipopt
using CSV
using DataFrames

print("\033c") # Limpa o terminal

# Pasta dedicada aos CSVs (criada automaticamente se não existir)
PASTA_CSV = joinpath(@__DIR__, "resultados_csv")
mkpath(PASTA_CSV)

# =========================================================================
# 0. LEITURA DE DADOS (O Sistema Interligado Nacional)
# =========================================================================
println("1. Lendo arquivo PWF...")
caminho_arquivo = joinpath(@__DIR__, "01 MAXIMA NOTURNA_DEZ25.PWF")

# Lemos o arquivo NORMALMENTE (sem o add_control_data, para não quebrar o PowerModels)
data = PWF.parse_file(caminho_arquivo)
base_mva = data["baseMVA"]

# Remove todas as ilhas isoladas e mantém apenas o subgrafo principal
PowerModels.select_largest_component!(data)
println("-> Ilhas isoladas removidas! Mantendo apenas a rede principal conectada.")

PowerModels.standardize_cost_terms!(data, order=2)
ref = PowerModels.build_ref(data)[:it][:pm][:nw][0]

# =========================================================================
# 1. INICIALIZAÇÃO DO MODELO E SOLVER
# =========================================================================
model = Model(optimizer_with_attributes(Ipopt.Optimizer, 
    "max_iter" => 3000, 
    "tol" => 1e-5,
    "print_level" => 5
))

# =========================================================================
# 2. VARIÁVEIS DE ESTADO FÍSICO COM WARM START
# =========================================================================
println("2. Criando variáveis de estado...")

# Limite global de Tensão (0.95 a 1.05 p.u.)
@variable(model, 0.95 <= vm[i in keys(ref[:bus])] <= 1.05, start=ref[:bus][i]["vm"])
@variable(model, va[i in keys(ref[:bus])], start=ref[:bus][i]["va"])

@variable(model, ref[:gen][i]["pmin"] <= pg[i in keys(ref[:gen])] <= ref[:gen][i]["pmax"], start=ref[:gen][i]["pg"])
@variable(model, ref[:gen][i]["qmin"] <= qg[i in keys(ref[:gen])] <= ref[:gen][i]["qmax"], start=ref[:gen][i]["qg"])

# VARIÁVEL CTAP: Relação de Transformação Variável
@variable(model, tm[l in keys(ref[:branch])], start=ref[:branch][l]["tap"])

# =========================================================================
# 3. A LÓGICA DO FLUXO DE POTÊNCIA (Fixando Pg em barras PV)
# =========================================================================
for (i, gen) in ref[:gen]
    bus_id = gen["gen_bus"]
    if bus_id in keys(ref[:ref_buses])
        # É uma das 5 barras Slack (Áreas AC distintas). Removemos os limites!
        if has_lower_bound(pg[i]); delete_lower_bound(pg[i]); end
        if has_upper_bound(pg[i]); delete_upper_bound(pg[i]); end
    else
        # É barra PV. Fixamos a geração ativa.
        fix(pg[i], gen["pg"]; force=true)
    end
end

for (i, bus) in ref[:ref_buses]
    # Ao invés de forçar todas em zero, cravamos no ângulo original do ANAREDE
    # Isso evita conflitos de fase entre os subsistemas
    fix(va[i], ref[:bus][i]["va"]; force=true) 
end

# =========================================================================
# 4. VARIÁVEIS DE CONTROLE (QLIM, VLIM e limites do CTAP)
# =========================================================================
PENALIDADE = 1e6 

gen_buses = unique([gen["gen_bus"] for (i,gen) in ref[:gen]])
@variable(model, sl_v[i in gen_buses], start=0.0)
@variable(model, sl_d[i in keys(ref[:load])], start=0.0)

for (i, gen) in ref[:gen]
    bus_id = gen["gen_bus"]
    vm_setpoint = ref[:bus][bus_id]["vm"]
    @constraint(model, vm[bus_id] == vm_setpoint + sl_v[bus_id])
end

# CTAP: Atribuindo os limites operacionais dos transformadores (+/- 10%)
for (l, branch) in ref[:branch]
    if branch["transformer"] == true
        tap_nominal = branch["tap"]
        
        # Regra prática de Engenharia: Liberamos a variação do Tap em +/- 10%
        t_min = tap_nominal * 0.90
        t_max = tap_nominal * 1.10
        
        # Avisamos o solver que ele pode mover essa variável livremente nesta faixa
        set_lower_bound(tm[l], t_min)
        set_upper_bound(tm[l], t_max)
    else
        # Se for uma linha de transmissão convencional, o TAP é rigidamente 1.0 (ou o valor fixo)
        fix(tm[l], branch["tap"]; force=true)
    end
end

# =========================================================================
# 5. EQUAÇÕES DE FLUXO NOS RAMOS (Formulação AC Polar com CTAP)
# =========================================================================
println("3. Montando equações de fluxo de potência (AC Polar com CTAP)...")

p = Dict(); q = Dict()

for (l, branch) in ref[:branch]
    f = branch["f_bus"]; t = branch["t_bus"]
    
    # Extrai os parâmetros físicos puros
    g, b = PowerModels.calc_branch_y(branch)
    g_fr = branch["g_fr"]; b_fr = branch["b_fr"]
    g_to = branch["g_to"]; b_to = branch["b_to"]
    
    # Isola o ângulo de defasagem (Phase Shifters)
    shift = branch["shift"]
    cs = cos(shift)
    ss = sin(shift)

    # Note que agora dividimos por tm[l] APENAS UMA VEZ nos termos cruzados, 
    # mantendo a coerência exata com a matriz de admitância Pi-equivalente!
    p[(l, f, t)] = @NLexpression(model, 
        (g + g_fr)/tm[l]^2 * vm[f]^2 + 
        (-g*cs + b*ss)/tm[l] * (vm[f]*vm[t]*cos(va[f]-va[t])) + 
        (-b*cs - g*ss)/tm[l] * (vm[f]*vm[t]*sin(va[f]-va[t]))
    )
    q[(l, f, t)] = @NLexpression(model, 
        -(b + b_fr)/tm[l]^2 * vm[f]^2 - 
        (-b*cs - g*ss)/tm[l] * (vm[f]*vm[t]*cos(va[f]-va[t])) + 
        (-g*cs + b*ss)/tm[l] * (vm[f]*vm[t]*sin(va[f]-va[t]))
    )
    
    p[(l, t, f)] = @NLexpression(model, 
        (g + g_to) * vm[t]^2 + 
        (-g*cs - b*ss)/tm[l] * (vm[t]*vm[f]*cos(va[t]-va[f])) + 
        (-b*cs + g*ss)/tm[l] * (vm[t]*vm[f]*sin(va[t]-va[f]))
    )
    q[(l, t, f)] = @NLexpression(model, 
        -(b + b_to) * vm[t]^2 - 
        (-b*cs + g*ss)/tm[l] * (vm[t]*vm[f]*cos(va[t]-va[f])) + 
        (-g*cs - b*ss)/tm[l] * (vm[t]*vm[f]*sin(va[t]-va[f]))
    )
end

# =========================================================================
# 6. LEIS DE KIRCHHOFF DOS NÓS
# =========================================================================
println("4. Montando balanço nodal (Leis de Kirchhoff)...")
for (i, bus) in ref[:bus]
    bus_arcs = ref[:bus_arcs][i]
    bus_gens = ref[:bus_gens][i]
    bus_loads = ref[:bus_loads][i]

    gs = sum(shunt["gs"] for (k,shunt) in ref[:shunt] if shunt["shunt_bus"] == i; init=0.0)
    bs = sum(shunt["bs"] for (k,shunt) in ref[:shunt] if shunt["shunt_bus"] == i; init=0.0)

    pd_nominal = sum(load["pd"] for (k,load) in ref[:load] if load["load_bus"] == i; init=0.0)
    qd_nominal = sum(load["qd"] for (k,load) in ref[:load] if load["load_bus"] == i; init=0.0)

    p_gen_total = isempty(bus_gens) ? 0.0 : sum(pg[g] for g in bus_gens)
    q_gen_total = isempty(bus_gens) ? 0.0 : sum(qg[g] for g in bus_gens)
    slack_vlim  = isempty(bus_loads) ? 0.0 : sum(sl_d[l] for l in bus_loads)

    @NLconstraint(model, sum(p[a] for a in bus_arcs) == p_gen_total - pd_nominal - gs*vm[i]^2)
    @NLconstraint(model, sum(q[a] for a in bus_arcs) == q_gen_total - (qd_nominal + slack_vlim) + bs*vm[i]^2)
end

# =========================================================================
# 7. FUNÇÃO OBJETIVO DE SOFT-CONSTRAINTS
# =========================================================================
# A "Mola" (100.0) diz ao solver: use os TAPs para salvar as tensões,
# mas não os gire aleatoriamente. Isso estabiliza o Hessiano!
@objective(model, Min, 
    PENALIDADE * sum(sl_v[i]^2 for i in keys(sl_v)) + 
    PENALIDADE * sum(sl_d[l]^2 for l in keys(sl_d)) +
    100.0 * sum((tm[l] - ref[:branch][l]["tap"])^2 for l in keys(ref[:branch]) if ref[:branch][l]["transformer"] == true)
)

# =========================================================================
# 8. RESOLUÇÃO E ESTATÍSTICAS COMPUTACIONAIS
# =========================================================================
println("5. Resolvendo o Fluxo de Potência Controlado...\n")

tempo_total_execucao = @elapsed optimize!(model)
status_convergencia = termination_status(model)

println("\n--- ESTATÍSTICAS DE RESOLUÇÃO ---")
println("Status da Convergência: ", status_convergencia)
println("Tempo interno do Solver (Ipopt): ", round(solve_time(model), digits=4), " segundos")
println("Tempo total da execução da função: ", round(tempo_total_execucao, digits=4), " segundos")
println("Erro de Controle (Slacks Ponderadas): ", objective_value(model))

# =========================================================================
# 9. EXPORTAÇÃO DOS RESULTADOS PARA CSV
# =========================================================================
println("\n6. Estruturando dados e gerando arquivos CSV...")

df_barras = DataFrame(
    ID_Barra = Int[], Tipo_Barra = Int[], 
    Tensao_Mag_pu = Float64[], Tensao_Ang_graus = Float64[],
    P_Geracao_pu = Float64[], Q_Geracao_pu = Float64[], 
    P_Carga_pu = Float64[], Q_Carga_pu = Float64[],
    Desvio_Tensao_QLIM_pu = Float64[], Corte_Reativo_VLIM_pu = Float64[]
)

for (i, bus) in ref[:bus]
    bus_gens = ref[:bus_gens][i]; bus_loads = ref[:bus_loads][i]
    push!(df_barras, (
        i, bus["bus_type"], value(vm[i]), value(va[i]) * (180.0 / pi),
        isempty(bus_gens) ? 0.0 : sum(value(pg[g]) for g in bus_gens),
        isempty(bus_gens) ? 0.0 : sum(value(qg[g]) for g in bus_gens),
        isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["pd"] for l in bus_loads),
        isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["qd"] for l in bus_loads),
        (i in gen_buses) ? value(sl_v[i]) : 0.0,
        isempty(bus_loads) ? 0.0 : sum(value(sl_d[l]) for l in bus_loads)
    ))
end
CSV.write(joinpath(PASTA_CSV, "resultados_barras_SIN.csv"), df_barras)

df_linhas = DataFrame(
    ID_Linha = Int[], Barra_De = Int[], Barra_Para = Int[],
    Tap_Otimizado_pu = Float64[],
    P_Fluxo_De_Para_pu = Float64[], Q_Fluxo_De_Para_pu = Float64[],
    P_Fluxo_Para_De_pu = Float64[], Q_Fluxo_Para_De_pu = Float64[],
    Perda_Ativa_pu = Float64[]
)

for (l, branch) in ref[:branch]
    f = branch["f_bus"]; t = branch["t_bus"]
    local val_p_from = value(p[(l, f, t)]); local val_q_from = value(q[(l, f, t)])
    local val_p_to   = value(p[(l, t, f)]); local val_q_to   = value(q[(l, t, f)])
    local tap_final  = value(tm[l])

    push!(df_linhas, (l, f, t, tap_final, val_p_from, val_q_from, val_p_to, val_q_to, val_p_from + val_p_to))
end
CSV.write(joinpath(PASTA_CSV, "resultados_fluxos_linhas_SIN.csv"), df_linhas)
println("-> Sucesso! Arquivos CSV gerados na pasta do projeto.")

# =========================================================================
# 10. RESUMO OPERACIONAL DO SIN
# =========================================================================
println("\n--- RESUMO OPERACIONAL GLOBAL ---")
tensao_min = minimum(df_barras.Tensao_Mag_pu)
tensao_max = maximum(df_barras.Tensao_Mag_pu)
geracao_p_total = sum(df_barras.P_Geracao_pu)
geracao_q_total = sum(df_barras.Q_Geracao_pu)
perda_p_total = sum(df_linhas.Perda_Ativa_pu)

println("Tensão Mínima (pu):         ", round(tensao_min, digits=4))
println("Tensão Máxima (pu):         ", round(tensao_max, digits=4))
println("Geração Ativa Total (pu):   ", round(geracao_p_total, digits=4))
println("Geração Reativa Total (pu): ", round(geracao_q_total, digits=4))
println("Perdas Ativas (Total pu):   ", round(perda_p_total, digits=4))
println("\n--- RESUMO EM UNIDADES REAIS (Base = $base_mva MVA) ---")
println("Geração Ativa Total (MW):   ", round(geracao_p_total * base_mva, digits=2))
println("Geração Reativa Total (MVAr):", round(geracao_q_total * base_mva, digits=2))
println("Perdas Ativas Totais (MW):  ", round(perda_p_total * base_mva, digits=2))