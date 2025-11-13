using PowerModels, Ipopt, JuMP

print("\033c")
println("Starting Formulation Comparison on case5.m...")

# --- Setup ---
pm_path = dirname(pathof(PowerModels))
case_file = joinpath(pm_path, "..", "test", "data", "matpower", "case5.m")
nl_solver = optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0)

# --- 1. Solve AC-OPF (The "Ground Truth") ---
# We use the generic solve_model, passing the Formulation (ACPPowerModel)
# and the Problem (build_opf) explicitly.
result_ac = solve_model(case_file, ACPPowerModel, nl_solver, build_opf)

println("AC-OPF (Exact, Non-Convex)")
println("  Status: ", result_ac["termination_status"])
println("  Objective: ", result_ac["objective"])

# --- 2. Solve DC-OPF (The Linear Approximation) ---
result_dc = solve_model(case_file, DCPPowerModel, nl_solver, build_opf)

println("\nDC-OPF (Linear Approximation)")
println("  Status: ", result_dc["termination_status"])
println("  Objective: ", result_dc["objective"])

# --- 3. Solve SOC-OPF (The Convex Relaxation) ---
result_soc = solve_model(case_file, SOCWRPowerModel, nl_solver, build_opf)

println("\nSOC-OPF (Convex Relaxation)")
println("  Status: ", result_soc["termination_status"])
println("  Objective: ", result_soc["objective"])

# --- 4. Analysis ---
println("\n--- Comparison Insight ---")
println("The SOC objective (", result_soc["objective"], ")")
println("is a provable *lower bound* for the AC objective (", result_ac["objective"], ").")
