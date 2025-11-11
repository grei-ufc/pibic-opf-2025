import Pkg
Pkg.add("JuMP")
Pkg.add("HiGHS")
Pkg.add("CSV")
Pkg.add("DataFrames")
Pkg.add("Test")


using JuMP
import CSV
import DataFrames
import HiGHS
import Test

print("\033c") # Clear Terminal

dir = mktempdir() # write CSV files to a temporary directory from Julia

#"/tmp/jl_ASwJfa" we could also use a path to an existing directory

food_csv_filename = joinpath(dir, "diet_foods.csv") #takes the complete path to directory and file name into a variable

open(food_csv_filename, "w") do io #open file, "w" stands for "write mode" so it will change the file. io stands for "InputOutput" everything between "do" and "end" will be executed with the file open
    write(
        io,
        """
        name,cost,calories,protein,fat,sodium
        hamburger,2.49,410,24,26,730
        chicken,2.89,420,32,10,1190
        hot dog,1.50,560,20,32,1800
        fries,1.89,380,4,19,270
        macaroni,2.09,320,12,10,930
        pizza,1.99,320,15,12,820
        salad,2.49,320,31,12,1230
        milk,0.89,100,8,2.5,125
        ice cream,1.59,330,8,10,180
        """,
    )
    return
end #closes the file
foods = CSV.read(food_csv_filename, DataFrames.DataFrame)


nutrient_csv_filename = joinpath(dir, "diet_nutrient.csv") #takes the complete path to directory and file name into a variable
open(nutrient_csv_filename, "w") do io
    write(
        io,
        """
        nutrient,min,max
        calories,1800,2200
        protein,91,
        fat,0,65
        sodium,0,1779
        """,
    )
    return
end
limits = CSV.read(nutrient_csv_filename, DataFrames.DataFrame)

limits.max = coalesce.(limits.max, Inf) # sets infinity as max for variables that does not have a max
limits

model = Model(HiGHS.Optimizer) #Creates model
set_silent(model) # Does not print the messages on the terminal

@variable(model, x[foods.name] >= 0) #Variable to be optimzed (Quantities of each food)

foods.x = Array(x) #Store as a new collumn 

@objective(model, Min, sum(foods.cost .* foods.x)); #Minimize the total cost

@constraint(
    model,
    [row in eachrow(limits)],
    row.min <= sum(foods[!, row.nutrient] .* foods.x) <= row.max,
); # 

print(model)

optimize!(model) # minimizes variables
assert_is_solved_and_feasible(model)
solution_summary(model)

for row in eachrow(foods)
    println(row.name, " = ", value(row.x))
end

table = Containers.rowtable(value, x; header = [:food, :quantity])
solution = DataFrames.DataFrame(table)

filter!(row -> row.quantity > 0.0, solution)

