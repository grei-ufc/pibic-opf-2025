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

bus = ref(pm, nw, :bus, i)
bus_arcs = ref(pm, nw, :bus_arcs, i)
bus_arcs_dc = ref(pm, nw, :bus_arcs_dc, i)
bus_arcs_sw = ref(pm, nw, :bus_arcs_sw, i)
bus_gens = ref(pm, nw, :bus_gens, i)
bus_loads = ref(pm, nw, :bus_loads, i)
bus_shunts = ref(pm, nw, :bus_shunts, i)
bus_storage = ref(pm, nw, :bus_storage, i)

bus_pd = Dict(k => ref(pm, nw, :load, k, "pd") for k in bus_loads)
bus_qd = Dict(k => ref(pm, nw, :load, k, "qd") for k in bus_loads)

bus_gs = Dict(k => ref(pm, nw, :shunt, k, "gs") for k in bus_shunts)
bus_bs = Dict(k => ref(pm, nw, :shunt, k, "bs") for k in bus_shunts)

vm   = var(pm, n, :vm, i)
p    = get(var(pm, n),    :p, Dict()); _check_var_keys(p, bus_arcs, "active power", "branch")
q    = get(var(pm, n),    :q, Dict()); _check_var_keys(q, bus_arcs, "reactive power", "branch")
pg   = get(var(pm, n),   :pg, Dict()); _check_var_keys(pg, bus_gens, "active power", "generator")
qg   = get(var(pm, n),   :qg, Dict()); _check_var_keys(qg, bus_gens, "reactive power", "generator")
ps   = get(var(pm, n),   :ps, Dict()); _check_var_keys(ps, bus_storage, "active power", "storage")
qs   = get(var(pm, n),   :qs, Dict()); _check_var_keys(qs, bus_storage, "reactive power", "storage")
psw  = get(var(pm, n),  :psw, Dict()); _check_var_keys(psw, bus_arcs_sw, "active power", "switch")
qsw  = get(var(pm, n),  :qsw, Dict()); _check_var_keys(qsw, bus_arcs_sw, "reactive power", "switch")
p_dc = get(var(pm, n), :p_dc, Dict()); _check_var_keys(p_dc, bus_arcs_dc, "active power", "dcline")
q_dc = get(var(pm, n), :q_dc, Dict()); _check_var_keys(q_dc, bus_arcs_dc, "reactive power", "dcline")

# 1. Restrição de Balanço de Potência
cstr_p = JuMP.@constraint(pm.model,
    sum(p[a] for a in bus_arcs)
    + sum(p_dc[a_dc] for a_dc in bus_arcs_dc)
    + sum(psw[a_sw] for a_sw in bus_arcs_sw)
    ==
    sum(pg[g] for g in bus_gens)
    - sum(ps[s] for s in bus_storage)
    - sum(pd for (i,pd) in bus_pd)
    - sum(gs for (i,gs) in bus_gs)*vm^2
)

cstr_q = JuMP.@constraint(pm.model,
    sum(q[a] for a in bus_arcs)
    + sum(q_dc[a_dc] for a_dc in bus_arcs_dc)
    + sum(qsw[a_sw] for a_sw in bus_arcs_sw)
    ==
    sum(qg[g] for g in bus_gens)
    - sum(qs[s] for s in bus_storage)
    - sum(qd for (i,qd) in bus_qd)
    + sum(bs for (i,bs) in bus_bs)*vm^2
)

# 2. Restrições de Lei de Ohm

# 2.1 Ohms yt from
branch = ref(pm, nw, :branch, i)
f_bus = branch["f_bus"]
t_bus = branch["t_bus"]
f_idx = (i, f_bus, t_bus)
t_idx = (i, t_bus, f_bus)

g, b = calc_branch_y(branch)
tr, ti = calc_branch_t(branch)
g_fr = branch["g_fr"]
b_fr = branch["b_fr"]
tm = branch["tap"]

p_fr  = var(pm, n,  :p, f_idx)
q_fr  = var(pm, n,  :q, f_idx)
vm_fr = var(pm, n, :vm, f_bus)
vm_to = var(pm, n, :vm, t_bus)
va_fr = var(pm, n, :va, f_bus)
va_to = var(pm, n, :va, t_bus)

JuMP.@constraint(pm.model, p_fr ==  (g+g_fr)/tm^2*vm_fr^2 + (-g*tr+b*ti)/tm^2*(vm_fr*vm_to*cos(va_fr-va_to)) + (-b*tr-g*ti)/tm^2*(vm_fr*vm_to*sin(va_fr-va_to)) )
JuMP.@constraint(pm.model, q_fr == -(b+b_fr)/tm^2*vm_fr^2 - (-b*tr-g*ti)/tm^2*(vm_fr*vm_to*cos(va_fr-va_to)) + (-g*tr+b*ti)/tm^2*(vm_fr*vm_to*sin(va_fr-va_to)) )


# 2.2 Ohms yt to
branch = ref(pm, nw, :branch, i)
f_bus = branch["f_bus"]
t_bus = branch["t_bus"]
f_idx = (i, f_bus, t_bus)
t_idx = (i, t_bus, f_bus)

g, b = calc_branch_y(branch)
tr, ti = calc_branch_t(branch)
g_to = branch["g_to"]
b_to = branch["b_to"]
tm = branch["tap"]

p_to  = var(pm, n,  :p, t_idx)
q_to  = var(pm, n,  :q, t_idx)
vm_fr = var(pm, n, :vm, f_bus)
vm_to = var(pm, n, :vm, t_bus)
va_fr = var(pm, n, :va, f_bus)
va_to = var(pm, n, :va, t_bus)

JuMP.@constraint(pm.model, p_to ==  (g+g_to)*vm_to^2 + (-g*tr-b*ti)/tm^2*(vm_to*vm_fr*cos(va_to-va_fr)) + (-b*tr+g*ti)/tm^2*(vm_to*vm_fr*sin(va_to-va_fr)) )
JuMP.@constraint(pm.model, q_to == -(b+b_to)*vm_to^2 - (-b*tr+g*ti)/tm^2*(vm_to*vm_fr*cos(va_to-va_fr)) + (-g*tr-b*ti)/tm^2*(vm_to*vm_fr*sin(va_to-va_fr)) )

