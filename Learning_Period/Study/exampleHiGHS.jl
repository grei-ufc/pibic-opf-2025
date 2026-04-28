import Pkg
Pkg.add("JuMP")
Pkg.add("HiGHS")
#import packages if needed


using JuMP
using HiGHS

print("\033c") #Clear Terminal

model = Model(HiGHS.Optimizer) #Type of model used
@variable(model, x >= 0) #Variable declared
@variable(model, 0 <= y <= 30) 
@objective(model, Min, 12x + 20y) #Function to be optimized
@constraint(model, c1, 6x + 8y >= 100) #Constraint to be satisfied
@constraint(model, c2, 7x + 12y >= 120)
print(model) # Print the model to check if it's correctly especified

is_solved_and_feasible(model) # Check if the model is feasible
optimize!(model) # optimize the objective function

termination_status(model) # 1=Found optimal solution
primal_status(model) # 1=Found a primal feasible point
dual_status(model) # 1=Found a dual feasible point
objective_value(model) #value of the optimized objective function
value(x) #optimized value of x
value(y) #optimized value of y
shadow_price(c1) #dual solution
shadow_price(c2)



#commom workflow
optimize!(model)
if !is_solved_and_feasible(model) 
    error("Solver did not find an optimal solution")
end