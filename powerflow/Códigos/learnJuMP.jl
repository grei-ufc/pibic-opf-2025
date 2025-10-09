import Pkg
Pkg.add("HiGHS")

using JuMP
using HiGHS

model = Model(HiGHS.Optimizer)
set_attribute(model, "output_flag", false)
set_attribute(model, "primal_feasibility_tolerance", 1e-8)