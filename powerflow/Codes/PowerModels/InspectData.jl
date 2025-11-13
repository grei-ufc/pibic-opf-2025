using PowerModels

print("\033c")
println("Starting PowerModels.jl AC-OPF Test Example")

pm_path = dirname(pathof(PowerModels))
case_file = joinpath(pm_path, "..", "test", "data", "matpower", "case14.m")

# 1. Parse the file into a dictionary
network_data = PowerModels.parse_file(case_file)

# 2. Get a high-level summary (counts of components)
println("--- Network Summary (case14) ---")
print_summary(network_data)

# 3. Use component_table for a clean, targeted view
println("\n--- Bus Voltage Limits ---")
print(PowerModels.component_table(network_data, "bus", ["vmin", "vmax"]))