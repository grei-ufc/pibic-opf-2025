print("\033c")
using Pkg

using PWF, PowerModels, Ipopt, Printf, PowerPlots

file = joinpath(@__DIR__, "test_line_shunt.pwf")

# Parse the file
data = PWF.parse_file(file, pm=true, add_control_data = true)

print(data)


#optimizer = Ipopt.Optimizer 

# Run the optimization
#results = run_ac_pf(data, optimizer)

#vm = results["solution"]["bus"]["1"]["vm"] # folution for voltage magniture of bus 1
#va = results["solution"]["bus"]["1"]["va"] # solution for voltage angle     of bus 1
vg = data["shunt"]["1"]["control_data"]

println(vg)

#println(vm)
#println(va)
