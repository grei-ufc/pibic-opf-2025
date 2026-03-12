file_name = "01 MAXIMA NOTURNA_DEZ25.PWF"
file_path = joinpath(@__DIR__, file_name)

# Carrega e limpa a rede
data = PWF.parse_pwf_to_powermodels(file_path)
PowerModels.propagate_topology_status!(data)
PowerModels.select_largest_component!(data)
PowerModels.calc_thermal_limits!(data)


