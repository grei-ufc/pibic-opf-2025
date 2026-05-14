# Esse codigo eu tento remover ilhas isoladas e componentes desconectados para tentar rodar a simulação

using Pkg, PWF, PowerModels, Ipopt, Printf, PowerPlots

print("\033c")

# --- Carregar o arquivo ---
file = joinpath(@__DIR__, "30_PD 2034 - MÁXIMA DIURNA.PWF")

# 1. Parse do arquivo PWF para o dicionário do PowerModels
network_data = PWF.parse_pwf_to_powermodels(file)

# 2. Verificar e corrigir a topologia
# Casos do ONS frequentemente têm ilhas desconectadas. 
# A função abaixo remove componentes isolados e mantém apenas a rede principal.
println("Removendo ilhas isoladas e componentes desconectados...")
PowerModels.select_largest_component!(network_data)

# (Opcional) Propagar status de desligamento se houver chaves abertas mal definidas
PowerModels.propagate_topology_status!(network_data)

# 3. Ajuste de Solver (Opcional, mas recomendado para casos grandes)
# Aumentar tolerância ou iterações pode ajudar, mas o principal é a topologia acima.
optimizer = optimizer_with_attributes(Ipopt.Optimizer, "print_level"=>0, "max_iter"=>3000)

println("Executando Fluxo de Potência AC...")

# 4. Rodar o Fluxo de Potência
result = run_ac_pf(network_data, optimizer, setting=Dict("output" => Dict("branch_flows" => true)))

# --- Verificação de Convergência ---
if result["termination_status"] == LOCALLY_SOLVED || result["termination_status"] == OPTIMAL
    println(">>> Convergência bem-sucedida! <<<")
else
    println(">>> O solver falhou: $(result["termination_status"]) <<<")
    # Tente rodar com restrições relaxadas se falhar
    # result = run_ac_pf(network_data, optimizer, setting=Dict("output" => Dict("branch_flows" => true)))
end


println("\n--- Optimization Results ---")

# --- Extração e Impressão de Resultados ---

println("\n=======================================================")
println("RESULTADOS DETALHADOS DO FLUXO DE POTÊNCIA")
println("=======================================================")

# 1. Resultados de Tensão nas Barras (Buses)
println("\n--- Tensão nas Barras (Buses) ---")
println("Barra | Tensão (pu) | Ângulo (graus)")
println("-------------------------------------")

# O dicionário de resultados geralmente usa chaves string, então ordenamos para imprimir bonito
buses = sort(collect(keys(result["solution"]["bus"])), by=x->parse(Int, x))

for bus_id in buses
    data = result["solution"]["bus"][bus_id]
    vm = data["vm"]            # Magnitude da tensão
    va_deg = rad2deg(data["va"]) # Converter radianos para graus
    
    # Formatação com printf para ficar alinhado
    @printf("%5s | %11.4f | %14.4f\n", bus_id, vm, va_deg)
end

# 2. Resultados de Geração
println("\n--- Geração de Potência ---")
println("Gerador @ Barra | Pot. Ativa (MW) | Pot. Reativa (Mvar)")
println("-------------------------------------------------------")

if haskey(result["solution"], "gen")
    gens = sort(collect(keys(result["solution"]["gen"])), by=x->parse(Int, x))
    for gen_id in gens
        data = result["solution"]["gen"][gen_id]
        pg = data["pg"] * result["solution"]["baseMVA"] # Convertendo pu para MW (se baseMVA estiver disp.)
        # Nota: PowerModels geralmente retorna em pu. Multiplicamos pela base (geralmente 100) se quiser MW.
        # Caso baseMVA não esteja direto no result, assumimos 100 ou imprimimos em pu.
        # Vamos imprimir em pu (padrão) para garantir, ou multiplicar por 100 se for o padrão do sistema.
        
        # Simplesmente imprimindo em pu (per unit) para evitar confusão de base, 
        # mas rotulando como pu. Se quiser MW, multiplique por 100.
        pg_pu = data["pg"]
        qg_pu = data["qg"]
        
        @printf("%15s | %15.4f pu | %19.4f pu\n", gen_id, pg_pu, qg_pu)
    end
else
    println("Nenhum dado de geração encontrado na solução.")
end

# 3. Fluxo nas Linhas (Branches)

# 1- Atualiza o modelo original (network_data) com as tensões calculadas no result
PowerModels.update_data!(network_data, result["solution"])

# 2- Força o cálculo dos fluxos AC baseados nessas tensões
# Isso gera um novo dicionário contendo apenas os fluxos das linhas
flows = PowerModels.calc_branch_flow_ac(network_data)

# 3-c  Agora imprimimos usando a variável 'flows' e não 'result'
println("\n--- Fluxo nas Linhas (Branches) ---")
println("Linha | De -> Para | P_origem (pu) | Q_origem (pu) | P_destino (pu) | Q_destino (pu)")
println("-------------------------------------------------------------------------------------")

# Pegamos os IDs das linhas do arquivo original
branch_ids = sort(collect(keys(network_data["branch"])), by=x->parse(Int, x))

for i in branch_ids
    # Dados da topologia (quem liga quem)
    branch_topo = network_data["branch"][i]
    f_bus = branch_topo["f_bus"]
    t_bus = branch_topo["t_bus"]
    
    # Dados do fluxo (calculados agora)
    # O calc_branch_flow_ac retorna estrutura: Dict("branch" => Dict("1" => ...))
    if haskey(flows["branch"], i)
        branch_res = flows["branch"][i]
        
        pf = branch_res["pf"]
        qf = branch_res["qf"]
        pt = branch_res["pt"]
        qt = branch_res["qt"]
        
        @printf("%5s | %4d -> %-4d | %13.4f | %13.4f | %14.4f | %14.4f\n", 
                i, f_bus, t_bus, pf, qf, pt, qt)
    else
        println("Aviso: Fluxo não calculado para linha $i")
    end
end
println("=======================================================")

# ==========================================
# PARTE GRÁFICA: Visualização da Topologia
# ==========================================

println("\nGerando gráfico da rede...")

#p = powerplot(network_data, basic=true, width=600, height=500)

#display(p)
