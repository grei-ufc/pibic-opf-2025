#---------------------------PWF INIT-------------------------------

using Pkg
# print("\033c") # Optional clear screen

using PWF, PowerModels, Ipopt, Printf, PowerPlots

file = joinpath(@__DIR__, "3bus.pwf")

# Parse the file
file_m = PWF.parse_pwf_to_powermodels(file)

# [CRITICAL STEP FOR OPF]
# Standard .pwf files sometimes lack cost data. 
# PowerModels requires cost models. If missing, we add a default linear cost here.
# This ensures the solver attempts to minimize generation rather than just finding a random feasible point.
for (i, gen) in file_m["gen"]
    # If cost is not defined, add a simple cost: 1.0 * Pg + 0.0
    if !haskey(gen, "cost")
        gen["cost"] = [1000.0, 0.0] # [c1, c0] -> Cost = c1*P + c0
        gen["ncost"] = 2
        gen["model"] = 2 # Polynomial cost
    end
end

#----------------------Optimization Part---------------------------

# Step 1: Define the solver
optimizer = Ipopt.Optimizer 

# Step 2: Run the OPTIMIZATION (AC OPF)
# Changing from run_ac_pf to run_ac_opf
result = solve_ac_opf(file_m, optimizer) 

# Step 3: Display the results
println("\n--- Optimization Results ---")

# Check solver status
status = result["termination_status"]
println("Status da Otimização: $status")

if status != "LOCALLY_SOLVED" && status != "OPTIMAL"
    println("⚠️  Aviso: A otimização não convergiu para uma solução ótima!")
end

# --- Extração e Impressão de Resultados ---

println("\n=======================================================")
println("RESULTADOS DO FLUXO DE POTÊNCIA ÓTIMO (OPF)")
println("=======================================================")

# Print Objective Value (Cost)
if haskey(result, "objective")
    @printf("Função Objetivo (Custo Total): %.4f\n", result["objective"])
end

# 1. Resultados de Tensão nas Barras (Buses)
println("\n--- Tensão nas Barras (Buses) ---")
println("Barra | Tensão (pu) | Ângulo (graus)")
println("-------------------------------------")

buses = sort(collect(keys(result["solution"]["bus"])), by=x->parse(Int, x))

for bus_id in buses
    data = result["solution"]["bus"][bus_id]
    vm = data["vm"]            
    va_deg = rad2deg(data["va"]) 
    
    @printf("%5s | %11.4f | %14.4f\n", bus_id, vm, va_deg)
end

# 2. Resultados de Geração (Agora Otimizados!)
println("\n--- Geração Otimizada ---")
println("Gerador @ Barra | Pot. Ativa (MW/pu)| Pot. Reativa (Mvar/pu)")
println("----------------------------------------------------------")

if haskey(result["solution"], "gen")
    gens = sort(collect(keys(result["solution"]["gen"])), by=x->parse(Int, x))
    for gen_id in gens
        data = result["solution"]["gen"][gen_id]
        
        # PowerModels output is always in Per Unit (pu).
        pg_pu = data["pg"]
        qg_pu = data["qg"]
        
        # Note: In OPF, these values are calculated by the solver, not fixed inputs!
        @printf("%15s | %15.4f pu | %19.4f pu\n", gen_id, pg_pu, qg_pu)
    end
else
    println("Nenhum dado de geração encontrado na solução.")
end

# 3. Fluxo nas Linhas (Branches)

PowerModels.update_data!(file_m, result["solution"])
flows = PowerModels.calc_branch_flow_ac(file_m)

println("\n--- Fluxo nas Linhas (Branches) ---")
println("Linha | De -> Para | P_origem (pu) | Q_origem (pu) | P_destino (pu) | Q_destino (pu)")
println("-------------------------------------------------------------------------------------")

branch_ids = sort(collect(keys(file_m["branch"])), by=x->parse(Int, x))

for i in branch_ids
    branch_topo = file_m["branch"][i]
    f_bus = branch_topo["f_bus"]
    t_bus = branch_topo["t_bus"]
    
    if haskey(flows["branch"], i)
        branch_res = flows["branch"][i]
        pf = branch_res["pf"]
        qf = branch_res["qf"]
        pt = branch_res["pt"]
        qt = branch_res["qt"]
        
        @printf("%5s | %4d -> %-4d | %13.4f | %13.4f | %14.4f | %14.4f\n", 
                i, f_bus, t_bus, pf, qf, pt, qt)
    end
end
println("=======================================================")

# ==========================================
# PARTE GRÁFICA
# ==========================================
println("\nGerando gráfico da rede otimizada...")
p = powerplot(file_m, basic=true, width=600, height=500)
display(p)