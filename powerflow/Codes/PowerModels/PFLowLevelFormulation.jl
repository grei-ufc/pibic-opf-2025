using PowerModels
using JuMP
using InfrastructureModels
using Ipopt

data = PowerModels.parse_file("./powerflow/Codes/PowerModels/case5.m")

pm = InitializeInfrastructureModel(ACPPowerModel, data, Set(["per_unit"]), :pm)

ref_add_core!(pm.ref)

PowerModels.ref(pm, :arcs_from)
PowerModels.ref(pm, :arcs_to)
PowerModels.ref(pm, :arcs)
PowerModels.ref(pm, :bus_arcs)

variable_bus_voltage(pm)
variable_gen_power(pm)
variable_branch_power(pm)

constraint_model_voltage(pm)

for i in PowerModels.ids(pm, :ref_buses)
    constraint_theta_ref(pm, i)
end

for i in PowerModels.ids(pm, :bus)
    constraint_power_balance(pm, i) # call in constraint_template.jl
end

for i in PowerModels.ids(pm, :branch)
    constraint_ohms_yt_from(pm, i)
    constraint_ohms_yt_to(pm, i)

    constraint_voltage_angle_difference(pm, i)

    constraint_thermal_limit_from(pm, i)
    constraint_thermal_limit_to(pm, i)

     constraint_current_limit_from(pm, i)
     constraint_current_limit_to(pm, i)
end

objective_min_fuel_cost(pm)