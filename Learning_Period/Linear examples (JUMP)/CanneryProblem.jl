using JuMP
import HiGHS
import JSON
import Test

print("\033c") # Clear Terminal

data = JSON.parse("""
{
    "plants": {
        "Seattle": {"capacity": 350},
        "San-Diego": {"capacity": 600}
    },
    "markets": {
        "New-York": {"demand": 300},
        "Chicago": {"demand": 300},
        "Topeka": {"demand": 300}
    },
    "distances": {
        "Seattle => New-York": 2.5,
        "Seattle => Chicago": 1.7,
        "Seattle => Topeka": 1.8,
        "San-Diego => New-York": 2.5,
        "San-Diego => Chicago": 1.8,
        "San-Diego => Topeka": 1.4
    }
} 
""") #

P = keys(data["plants"]) # Vectro Plants
M = keys(data["markets"]) # Vector Markets

distance(p::String, m::String) = data["distances"]["$(p) => $(m)"] # Distance function

model = Model(HiGHS.Optimizer)

@variable(model, x[P, M] >= 0) # Plants can't send less than 0 products

@constraint(model, [p in P], sum(x[p, :]) <= data["plants"][p]["capacity"]) # Plants can't send less then their capacity

@constraint(model, [m in M], sum(x[:, m]) >= data["markets"][m]["demand"]) # Markets have to get at least the demand

@objective(model, Min, sum(distance(p, m) * x[p, m] for p in P, m in M)); # Minimize total distance (cost)

optimize!(model)
solution_summary(model)

assert_is_solved_and_feasible(model)
for p in P, m in M
    println(p, " => ", m, ": ", value(x[p, m]))
end