print("\033c") # Clear Terminal

# 1. DEFININDO O MODELO PRIMAL
model = Model(HiGHS.Optimizer)

@variable(model, x >= 0)
@variable(model, y >= 0)

# 'c_madeira' é uma restrição PRIMAL
@constraint(model, c_madeira, 2x + y <= 100) 

@objective(model, Max, 40x + 30y)

optimize!(model)

# 2. ACESSANDO AS SOLUÇÕES

# Solução PRIMAL (Quanto produzir de x e y)
primal_x = value(x)
primal_y = value(y)

# Solução DUAL (O valor da restrição 'c_madeira')
dual_madeira = shadow_price(c_madeira) 

# Quanto X tem que melhorar
custo_x = reduced_cost(x) 


println(primal_x)
println(primal_y)
println(dual_madeira)
println(custo_x)