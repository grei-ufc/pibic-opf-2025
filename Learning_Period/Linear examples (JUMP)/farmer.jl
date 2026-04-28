using JuMP
using HiGHS

print("\033c") #Clear Terminal

# 1 e 2: Criar o modelo e anexar o solver
model = Model(HiGHS.Optimizer)

# 3: Declarar variáveis
@variable(model, x >= 0, base_name = "trigo")
@variable(model, y >= 0, base_name = "cevada")

# 4: Definir a função objetivo
@objective(model, Max, 150x + 220y)

# 5: Adicionar as restrições
@constraint(model, c_terra, x + y <= 100)
@constraint(model, c_fertilizante, 20x + 35y <= 2500)
@constraint(model, c_pesticida, 5x + 3y <= 400)

# Imprime o modelo para visualização (opcional)
print(model)

# 6: Otimizar
optimize!(model)

# 7: Analisar os resultados
println("--- Resultados da Otimização ---")
println("Status da solução: ", termination_status(model))
println("Lucro Máximo: ", objective_value(model))
println("\n--- Plano de Plantio ---")
println("Hectares de Trigo (x): ", value(x))
println("Hectares de Cevada (y): ", value(y))