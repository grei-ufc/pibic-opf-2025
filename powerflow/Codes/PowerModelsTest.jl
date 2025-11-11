import Pkg
Pkg.add("PowerModels")
Pkg.add("Ipopt")

using PowerModels
using Ipopt

print("\033c") #Clear Terminal                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       

pm_path = dirname(pathof(PowerModels)) #println("Folder 'src' of PowerModels: ", pm_path)

case3_file = joinpath(pm_path, "..", "test", "data", "matpower", "case3.m")

# Use the file path you just found
result = solve_ac_opf(case3_file, Ipopt.Optimizer) #result = solve_opf(case3_file, ACPPowerModel, Ipopt.Optimizer)


#=
How to print results

println(result)
result["solve_time"]
result["objective"]
Dict(name => data["va"] for (name, data) in result["solution"]["bus"]) #bus voltage angles in the solution

print_summary(result["solution"])
=#