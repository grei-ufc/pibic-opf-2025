# Step 1: Import the necessary libraries
using PowerModels
using Ipopt
using JuMP 


# Step 2: Clear the terminal for clean output
print("\033c")
println("Starting PowerModels.jl AC-OPF Test Example")


# Step 3: Define the solver
optimizer = Ipopt.Optimizer                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 


# Step 4: Find the path to a test data file
pm_path = dirname(pathof(PowerModels)) 
case_file = joinpath(pm_path, "..", "test", "data", "matpower", "case3.m")
println("Running optimization on test file: ", case_file)


# Step 5: Run the optimization
result = solve_ac_opf(case_file, Ipopt.Optimizer) #result = solve_opf(case_file, ACPPowerModel, Ipopt.Optimizer)


# Step 6: Display the results
println("\n--- Optimization Results ---")


# 'print_summary' gives a human-readable table [6]
println("Solution Summary:")
print_summary(result["solution"])


# Access specific data points from the result dictionary [6]
println("\nSolver solvetime: ", result["solve_time"], "seconds")
println("Final objective value: ", result["objective"])



#=
println(result)
Dict(name => data["va"] for (name, data) in result["solution"]["bus"]) #bus voltage angles in the solution
=#