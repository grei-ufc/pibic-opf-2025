# =========================================================================
# 1. Dicionário de Mapeamento de Conexões
# =========================================================================
const bus_key = Dict(:shunt => "shunt_bus", :gen => "gen_bus", :load => "load_bus"). #Este dicionário bus_key serve para automatizar buscas. Se uma função quiser buscar "todos os elementos de um tipo $X$ na barra $Y$", ela usa bus_key[X] para saber qual chave do dicionário de dados deve olhar.


# =========================================================================
# 2. A Hierarquia de Tipos
# =========================================================================
""
abstract type ControlAbstractModel <: _PM.AbstractPowerModel end # O autor cria um tipo abstrato (ControlAbstractModel) que é um "filho" (<:) do AbstractPowerModel (que é a base do PowerModels).

""
abstract type ControlAbstractACRModel <: ControlAbstractModel end

""
mutable struct ControlACRPowerModel <: ControlAbstractACRModel @pm_fields end

""
abstract type ControlAbstractIVRModel <: ControlAbstractACRModel end

""
mutable struct ControlIVRPowerModel <: ControlAbstractIVRModel @pm_fields end

""
abstract type ControlAbstractACPModel <: ControlAbstractModel end

""
mutable struct ControlACPPowerModel <: ControlAbstractACPModel @pm_fields end

ControlAbstractPolarModels = Union{ControlACPPowerModel}


# =========================================================================
# 3. Identificadores Lógicos de Barras
# =========================================================================
pv_bus(pm::_PM.AbstractPowerModel, i::Int) = length(ref(pm, :bus_gens, i)) > 0 && !(i in ids(pm,:ref_buses)) #Retorna true se a barra "i" tem pelo menos 1 gerador conectado & "i" não é a barra de Referência/Slack.

pq_bus(pm::_PM.AbstractPowerModel, i::Int) = length(ref(pm, :bus_gens, i)) == 0 #Retorna true se a barra não possui nenhum gerador (Barra de Carga pura).

controlled_bus(pm::_PM.AbstractPowerModel, i::Int) = _PM.ref(pm, :bus, i, "control_data")["voltage_controlled_bus"] #Retorna um valor booleano ou inteiro lido diretamente dos metadados do arquivo ANAREDE (campo control_data). Informa se aquela barra possui, por exemplo, controle de tensão atrelado a banco de capacitores ou taps.


# =========================================================================
# 4. A Função de Busca Dinâmica e Funcional
# =========================================================================
function elements_from_bus(pm::ControlPowerFlow._PM.AbstractPowerModel, # Busca todos os componentes do tipo element (ex: :gen, :shunt) que estão fisicamente ligados à barra bus no tempo (ou snapshot de rede) nw.
                          element::Symbol, bus::Int, nw::Int; 
                          filters::Vector = [])

    filters = vcat(filters, [shunt->shunt[bus_key[element]] == bus]) # O componente deve estar conectado à barra "bus"
    filtered_keys = findall(
            x -> (
                all([f(x) for f in filters])
            ), 
            ref(pm, nw, element)
        )
    return Dict(k => ref(pm, nw, element, k) for k in filtered_keys)
end