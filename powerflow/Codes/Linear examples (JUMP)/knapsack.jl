using JuMP
import HiGHS

print("\033c") #Clear Terminal

n = 5; # Number of items
capacity = 10.0; # Bag capacity

profit = [5.0, 3.0, 2.0, 7.0, 4.0]; # Profit of each item
weight = [2.0, 8.0, 4.0, 2.0, 5.0]; # Weight of each item

model = Model(HiGHS.Optimizer)

@variable(model, x[1:n], Bin) #Sets binary variables from 1 to n=5 (1 = we choose the item, 0 = we don't choose the item)

@constraint(model, sum(weight[i] * x[i] for i in 1:n) <= capacity) #Total Weight < Capacity

@objective(model, Max, sum(profit[i] * x[i] for i in 1:n)) #Maximize value

print(model)

optimize!(model)
assert_is_solved_and_feasible(model)
solution_summary(model)

items_chosen = [i for i in 1:n if value(x[i]) > 0.5]
