###############################################################################
# (21) QLIM + VLIM + CSCA + CTAP — versão robusta para o SIN
#
# Diagnóstico do "Locally Infeasible" do (18) no caso 01 MAXIMA NOTURNA:
#   - Não é restrição apertada (os controles ANAREDE já preveem folga).
#   - É PONTO DE PARTIDA ruim para o NLP do SIN inteiro: o Ipopt parte
#     dos vm/va/pg/qg do PWF (que NÃO estão no ponto de operação real)
#     e cai em restoration sem conseguir sair.
#
# Correção: warm start em duas etapas.
#   Etapa A — solve_ac_pf do PowerModels (sabidamente converge neste caso,
#             é exatamente o que o (15) faz). Resultado vira ponto de partida.
#   Etapa B — modelo controlado com soft constraints + Ipopt escalonado,
#             partindo do warm start (Ipopt agora só "corrige" para
#             respeitar QLIM/VLIM/CSCA/CTAP, não busca um PF do zero).
###############################################################################

using PWF
using PowerModels
using JuMP
using Ipopt
using CSV
using DataFrames

print("\033c")

PASTA_CSV = joinpath(@__DIR__, "resultados_csv")
mkpath(PASTA_CSV)

const STATUS_OK = (
    MOI.LOCALLY_SOLVED, MOI.OPTIMAL,
    MOI.ALMOST_LOCALLY_SOLVED, MOI.ALMOST_OPTIMAL,
)

# -----------------------------------------------------------------------------
# Etapa A: warm start via solve_ac_pf (mesma chamada do (15))
# -----------------------------------------------------------------------------
function aplicar_warm_start!(data)
    println("\n--- Etapa A: warm start via solve_ac_pf ---")
    opt_ws = optimizer_with_attributes(Ipopt.Optimizer,
        "max_iter"            => 3000,
        "tol"                 => 1e-5,
        "nlp_scaling_method"  => "gradient-based",
        "mu_strategy"         => "adaptive",
        "print_level"         => 0,
    )

    res = try
        solve_ac_pf(data, opt_ws)
    catch err
        @warn "solve_ac_pf falhou: $err. Mantendo valores do PWF."
        return false
    end

    status = res["termination_status"]
    if !(status in STATUS_OK)
        @warn "solve_ac_pf não convergiu (status=$status). Mantendo valores do PWF."
        return false
    end

    sol = res["solution"]
    # Atualiza dados de barra (vm, va) — keys do PowerModels são strings
    for (k, bus_sol) in sol["bus"]
        haskey(data["bus"], k) || continue
        data["bus"][k]["vm"] = bus_sol["vm"]
        data["bus"][k]["va"] = bus_sol["va"]
    end
    # Atualiza dados de geração (pg, qg)
    if haskey(sol, "gen")
        for (k, gen_sol) in sol["gen"]
            haskey(data["gen"], k) || continue
            data["gen"][k]["pg"] = gen_sol["pg"]
            data["gen"][k]["qg"] = gen_sol["qg"]
        end
    end
    println("-> Warm start aplicado (status=$status, objetivo=$(round(res["objective"], digits=4)))")
    return true
end

# -----------------------------------------------------------------------------
# Helper: clamp seguro entre limites; usado para evitar `start` fora de bounds
# -----------------------------------------------------------------------------
clamp_start(x, lo, hi) = isnan(x) ? (lo + hi) / 2 : clamp(x, lo, hi)

# -----------------------------------------------------------------------------
# Etapa B: modelo controlado com soft constraints, partindo do warm start
# -----------------------------------------------------------------------------
function resolver_fluxo_controlado(caminho_arquivo)
    # =========================================================================
    # 0. LEITURA DE DADOS E TOPOLOGIA
    # =========================================================================
    println("1. Lendo arquivo PWF...")

    data = PWF.parse_file(caminho_arquivo, add_control_data=true)
    base_mva = data["baseMVA"]
    PowerModels.select_largest_component!(data)
    println("-> Ilhas isoladas removidas! Mantendo apenas a rede principal conectada.")

    # Múltiplas barras tipo 3 → mantém apenas a primeira; demais viram PV (tipo 2)
    ref_buses_vec = [b_dict for (_, b_dict) in data["bus"] if b_dict["bus_type"] == 3]
    if length(ref_buses_vec) > 1
        println("-> Aviso: $(length(ref_buses_vec)) barras de referência. Convertendo $(length(ref_buses_vec)-1) para PV (Tipo 2)...")
        for bus_dict in Iterators.drop(ref_buses_vec, 1)
            bus_dict["bus_type"] = 2
        end
    end

    PowerModels.standardize_cost_terms!(data, order=2)

    # ---> WARM START (sobrescreve vm/va/pg/qg em data com o PF convergido)
    aplicar_warm_start!(data)

    # Patch de limpeza (idêntico ao (18))
    for (_, comp_dict) in data
        if comp_dict isa Dict
            chaves_para_remover = String[]
            for (k, v) in comp_dict
                if typeof(v) == Dict{String, Any} && tryparse(Int, k) === nothing
                    push!(chaves_para_remover, k)
                end
            end
            for k in chaves_para_remover
                delete!(comp_dict, k)
            end
        end
    end

    ref = PowerModels.build_ref(data)[:it][:pm][:nw][0]

    # =========================================================================
    # 1. SOLVER — escalonamento + mu adaptativo + warm start
    # =========================================================================
    println("\n--- Etapa B: modelo controlado com soft constraints ---")
    model = Model(optimizer_with_attributes(Ipopt.Optimizer,
        "max_iter"               => 5000,
        "tol"                    => 1e-5,
        "acceptable_tol"         => 1e-4,
        "acceptable_iter"        => 25,
        "nlp_scaling_method"     => "gradient-based",
        "mu_strategy"            => "adaptive",
        "mu_init"                => 1e-2,
        "bound_push"             => 1e-6,
        "bound_frac"             => 1e-6,
        "warm_start_init_point"  => "yes",
        "warm_start_bound_push"  => 1e-9,
        "warm_start_bound_frac"  => 1e-9,
        "print_level"            => 5,
    ))

    # =========================================================================
    # 2. PENALIDADES — moderadas e relativamente uniformes
    # =========================================================================
    # Diferenças muito grandes entre penalidades atrapalham o gradient-based
    # scaler do Ipopt. Mantemos no máximo 2 ordens de grandeza de spread.
    P_CARGA  = 1e6   # corte de carga (último recurso)
    P_VLIM_H = 1e5   # violação de vmin/vmax físico
    P_QLIM   = 1e5   # violação de qmin/qmax
    P_BSH    = 1e4   # shunt fora dos limites físicos
    P_CTRL   = 1e4   # desvio do setpoint VLIM controlado
    P_SETBSH = 1e2   # desvio do bs nominal (CSCA — manobra desejada)

    # =========================================================================
    # 3. VARIÁVEIS DE ESTADO — vm e qg LIVRES (bounds via slacks)
    # =========================================================================
    println("2. Criando variáveis de estado e controle...")

    @variable(model, vm[i in keys(ref[:bus])], start=ref[:bus][i]["vm"])
    @variable(model, va[i in keys(ref[:bus])], start=ref[:bus][i]["va"])

    # pg respeita [pmin,pmax] (manobra de despacho). Slack ativa nodal cobre desbalanço.
    @variable(model,
        ref[:gen][i]["pmin"] <= pg[i in keys(ref[:gen])] <= ref[:gen][i]["pmax"],
        start = clamp_start(ref[:gen][i]["pg"], ref[:gen][i]["pmin"], ref[:gen][i]["pmax"]))

    # qg LIVRE — limites via soft constraint
    @variable(model, qg[i in keys(ref[:gen])], start=ref[:gen][i]["qg"])
    @variable(model, sl_qg_upp[i in keys(ref[:gen])] >= 0.0, start=0.0)
    @variable(model, sl_qg_low[i in keys(ref[:gen])] >= 0.0, start=0.0)
    for (i, gen) in ref[:gen]
        @constraint(model, qg[i] <= gen["qmax"] + sl_qg_upp[i])
        @constraint(model, qg[i] >= gen["qmin"] - sl_qg_low[i])
    end

    # Violação dos limites físicos de tensão (vmin/vmax do PWF)
    @variable(model, sl_vm_upp[i in keys(ref[:bus])] >= 0.0, start=0.0)
    @variable(model, sl_vm_low[i in keys(ref[:bus])] >= 0.0, start=0.0)
    for (i, bus) in ref[:bus]
        @constraint(model, vm[i] <= bus["vmax"] + sl_vm_upp[i])
        @constraint(model, vm[i] >= bus["vmin"] - sl_vm_low[i])
    end

    # =========================================================================
    # 4. ELOS DC — fixos (mesma lógica do (18))
    # =========================================================================
    p_dc = Dict(); q_dc = Dict()
    for (l, dcline) in ref[:dcline]
        f = dcline["f_bus"]; t = dcline["t_bus"]
        p_dc[(l, f, t)] = @variable(model, start=dcline["pf"])
        p_dc[(l, t, f)] = @variable(model, start=dcline["pt"])
        q_dc[(l, f, t)] = @variable(model, start=dcline["qf"])
        q_dc[(l, t, f)] = @variable(model, start=dcline["qt"])

        fix(p_dc[(l, f, t)], dcline["pf"]; force=true)
        fix(p_dc[(l, t, f)], dcline["pt"]; force=true)
        fix(q_dc[(l, f, t)], dcline["qf"]; force=true)
        fix(q_dc[(l, t, f)], dcline["qt"]; force=true)
    end

    # =========================================================================
    # 5. SHUNTS (CSCA) — bs livre + slack de setpoint + slack além dos limites
    # =========================================================================
    @variable(model, bs_var[i in keys(ref[:shunt])])
    @variable(model, sl_bsh[i in keys(ref[:shunt])], start=0.0)
    @variable(model, sl_bsh_upp[i in keys(ref[:shunt])] >= 0.0, start=0.0)
    @variable(model, sl_bsh_low[i in keys(ref[:shunt])] >= 0.0, start=0.0)

    for (i, shunt) in ref[:shunt]
        bs_nom = shunt["bs"]
        bmin, bmax = bs_nom, bs_nom

        if haskey(shunt, "control_data")
            ctrl = shunt["control_data"]
            bmin = isnothing(get(ctrl, "bsmin", nothing)) ? bs_nom : ctrl["bsmin"]
            bmax = isnothing(get(ctrl, "bsmax", nothing)) ? bs_nom : ctrl["bsmax"]
        end

        real_bmin = min(bmin, bmax, bs_nom)
        real_bmax = max(bmin, bmax, bs_nom)

        set_start_value(bs_var[i], bs_nom)

        if real_bmin == real_bmax
            fix(bs_var[i], bs_nom; force=true)
            fix(sl_bsh[i], 0.0; force=true)
        else
            @constraint(model, bs_var[i] <= real_bmax + sl_bsh_upp[i])
            @constraint(model, bs_var[i] >= real_bmin - sl_bsh_low[i])
            @constraint(model, bs_var[i] == bs_nom + sl_bsh[i])
        end
    end

    # =========================================================================
    # 6. TAPS (CTAP) — [tmin, tmax] hard com proteção contra tap nominal nulo
    # =========================================================================
    @variable(model, tm_var[l in keys(ref[:branch])])
    for (l, branch) in ref[:branch]
        tap_nominal = branch["tap"]
        # Proteção: linhas comuns devem ter tap=1.0; se vier 0, é dado corrompido
        if !(tap_nominal > 0)
            tap_nominal = 1.0
        end
        tmin, tmax = tap_nominal, tap_nominal

        if haskey(branch, "control_data")
            ctrl = branch["control_data"]
            tmin = isnothing(get(ctrl, "tapmin", nothing)) ? tap_nominal : ctrl["tapmin"]
            tmax = isnothing(get(ctrl, "tapmax", nothing)) ? tap_nominal : ctrl["tapmax"]
        end

        real_tmin = max(min(tmin, tmax, tap_nominal), 1e-3)
        real_tmax = max(tmin, tmax, tap_nominal)

        if real_tmin < real_tmax
            set_lower_bound(tm_var[l], real_tmin)
            set_upper_bound(tm_var[l], real_tmax)
            set_start_value(tm_var[l], tap_nominal)
        else
            fix(tm_var[l], tap_nominal; force=true)
        end
    end

    # =========================================================================
    # 7. DESPACHO E REFERÊNCIA ANGULAR
    # =========================================================================
    for (i, gen) in ref[:gen]
        if gen["gen_bus"] in keys(ref[:ref_buses])
            # Barra slack: pg totalmente livre
            if has_lower_bound(pg[i]); delete_lower_bound(pg[i]); end
            if has_upper_bound(pg[i]); delete_upper_bound(pg[i]); end
        else
            fix(pg[i], gen["pg"]; force=true)
        end
    end

    for (i, _) in ref[:ref_buses]
        fix(va[i], 0.0; force=true)
    end

    # =========================================================================
    # 8. SLACK DE VLIM CONTROLADO
    # =========================================================================
    gen_buses = [gen["gen_bus"] for (_, gen) in ref[:gen]]
    shunt_buses = [
        shunt["shunt_bus"] for (_, shunt) in ref[:shunt]
        if haskey(shunt, "control_data") &&
           haskey(shunt["control_data"], "bsmin") &&
           shunt["control_data"]["bsmin"] != shunt["control_data"]["bsmax"]
    ]
    controlled_buses = unique(vcat(gen_buses, shunt_buses))

    @variable(model, sl_v[i in controlled_buses], start=0.0)
    @variable(model, sl_v_upp[i in controlled_buses] >= 0.0, start=0.0)
    @variable(model, sl_v_low[i in controlled_buses] >= 0.0, start=0.0)

    for bus_id in controlled_buses
        bus_data = ref[:bus][bus_id]
        if haskey(bus_data, "control_data") && haskey(bus_data["control_data"], "vmmin")
            vm_min_ctrl = bus_data["control_data"]["vmmin"]
            vm_max_ctrl = bus_data["control_data"]["vmmax"]
        else
            vm_min_ctrl = bus_data["vm"]
            vm_max_ctrl = bus_data["vm"]
        end

        if abs(vm_max_ctrl - vm_min_ctrl) < 1e-5
            @constraint(model, vm[bus_id] == vm_max_ctrl + sl_v[bus_id])
        else
            @constraint(model, vm[bus_id] >= vm_min_ctrl - sl_v_low[bus_id])
            @constraint(model, vm[bus_id] <= vm_max_ctrl + sl_v_upp[bus_id])
        end
    end

    # =========================================================================
    # 9. SLACKS NODAIS DE BALANÇO (corte de carga em último recurso)
    # =========================================================================
    @variable(model, sl_d[i in keys(ref[:load])], start=0.0)    # alívio reativo
    @variable(model, sl_p_d[i in keys(ref[:load])], start=0.0)  # alívio ativo

    # =========================================================================
    # 10. EQUAÇÕES DE FLUXO NOS RAMOS AC
    # =========================================================================
    println("3. Montando equações de fluxo de potência (AC Polar)...")
    p = Dict(); q = Dict()

    for (l, branch) in ref[:branch]
        f = branch["f_bus"]; t = branch["t_bus"]
        g, b = PowerModels.calc_branch_y(branch)
        g_fr = branch["g_fr"]; b_fr = branch["b_fr"]
        g_to = branch["g_to"]; b_to = branch["b_to"]
        shift = branch["shift"]
        cos_phi = cos(shift)
        sin_phi = sin(shift)

        p[(l, f, t)] = @NLexpression(model,
            (g + g_fr) / tm_var[l]^2 * vm[f]^2 +
            (-g * cos_phi + b * sin_phi) / tm_var[l] * (vm[f] * vm[t] * cos(va[f] - va[t])) +
            (-b * cos_phi - g * sin_phi) / tm_var[l] * (vm[f] * vm[t] * sin(va[f] - va[t]))
        )
        q[(l, f, t)] = @NLexpression(model,
            -(b + b_fr) / tm_var[l]^2 * vm[f]^2 -
            (-b * cos_phi - g * sin_phi) / tm_var[l] * (vm[f] * vm[t] * cos(va[f] - va[t])) +
            (-g * cos_phi + b * sin_phi) / tm_var[l] * (vm[f] * vm[t] * sin(va[f] - va[t]))
        )
        p[(l, t, f)] = @NLexpression(model,
            (g + g_to) * vm[t]^2 +
            (-g * cos_phi - b * sin_phi) / tm_var[l] * (vm[t] * vm[f] * cos(va[t] - va[f])) +
            (-b * cos_phi + g * sin_phi) / tm_var[l] * (vm[t] * vm[f] * sin(va[t] - va[f]))
        )
        q[(l, t, f)] = @NLexpression(model,
            -(b + b_to) * vm[t]^2 -
            (-b * cos_phi + g * sin_phi) / tm_var[l] * (vm[t] * vm[f] * cos(va[t] - va[f])) +
            (-g * cos_phi - b * sin_phi) / tm_var[l] * (vm[t] * vm[f] * sin(va[t] - va[f]))
        )
    end

    # =========================================================================
    # 11. LEIS DE KIRCHHOFF — com slack ativa e reativa nodal
    # =========================================================================
    println("4. Montando balanço nodal (Leis de Kirchhoff)...")
    for (i, _) in ref[:bus]
        bus_arcs    = ref[:bus_arcs][i]
        bus_arcs_dc = ref[:bus_arcs_dc][i]
        bus_gens    = ref[:bus_gens][i]
        bus_loads   = ref[:bus_loads][i]
        bus_shunts  = [k for (k, shunt) in ref[:shunt] if shunt["shunt_bus"] == i]

        pd_nominal = sum(load["pd"] for (_, load) in ref[:load] if load["load_bus"] == i; init=0.0)
        qd_nominal = sum(load["qd"] for (_, load) in ref[:load] if load["load_bus"] == i; init=0.0)

        p_gen_total = isempty(bus_gens)    ? 0.0 : sum(pg[g] for g in bus_gens)
        q_gen_total = isempty(bus_gens)    ? 0.0 : sum(qg[g] for g in bus_gens)
        p_dc_total  = isempty(bus_arcs_dc) ? 0.0 : sum(p_dc[a] for a in bus_arcs_dc)
        q_dc_total  = isempty(bus_arcs_dc) ? 0.0 : sum(q_dc[a] for a in bus_arcs_dc)

        slack_p     = isempty(bus_loads)  ? 0.0 : sum(sl_p_d[l] for l in bus_loads)
        slack_q     = isempty(bus_loads)  ? 0.0 : sum(sl_d[l]   for l in bus_loads)
        gs_total    = isempty(bus_shunts) ? 0.0 : sum(ref[:shunt][k]["gs"] for k in bus_shunts)

        @NLconstraint(model,
            sum(p[a] for a in bus_arcs) + p_dc_total ==
                p_gen_total - (pd_nominal + slack_p) - gs_total * vm[i]^2
        )

        if isempty(bus_shunts)
            @NLconstraint(model,
                sum(q[a] for a in bus_arcs) + q_dc_total ==
                    q_gen_total - (qd_nominal + slack_q)
            )
        else
            @NLconstraint(model,
                sum(q[a] for a in bus_arcs) + q_dc_total ==
                    q_gen_total - (qd_nominal + slack_q) +
                    sum(bs_var[k] * vm[i]^2 for k in bus_shunts)
            )
        end
    end

    # =========================================================================
    # 12. OBJETIVO — penalidades moderadas e uniformes
    # =========================================================================
    @objective(model, Min,
        P_CARGA  * sum(sl_p_d[l]^2 + sl_d[l]^2 for l in keys(sl_d)) +
        P_VLIM_H * sum(sl_vm_upp[i]^2 + sl_vm_low[i]^2 for i in keys(ref[:bus])) +
        P_QLIM   * sum(sl_qg_upp[i]^2 + sl_qg_low[i]^2 for i in keys(ref[:gen])) +
        P_BSH    * sum(sl_bsh_upp[i]^2 + sl_bsh_low[i]^2 for i in keys(ref[:shunt])) +
        P_CTRL   * sum(sl_v[i]^2 for i in keys(sl_v)) +
        P_CTRL   * sum(sl_v_upp[i]^2 + sl_v_low[i]^2 for i in keys(sl_v_upp)) +
        P_SETBSH * sum(sl_bsh[k]^2 for k in keys(sl_bsh))
    )

    # =========================================================================
    # 13. RESOLUÇÃO
    # =========================================================================
    println("5. Resolvendo o Fluxo de Potência Controlado...\n")
    tempo_total_execucao = @elapsed optimize!(model)

    status = termination_status(model)
    println("\n--- ESTATÍSTICAS DE RESOLUÇÃO ---")
    println("Status da Convergência: ", status)
    println("Tempo interno do Solver (Ipopt): ", round(solve_time(model), digits=4), " segundos")
    println("Tempo total da execução da função: ", round(tempo_total_execucao, digits=4), " segundos")

    # Fallback automático: se ainda assim falhar, refaça com start_with_resto
    if !(status in STATUS_OK)
        println("\n!! Primeira tentativa não convergiu ($status). Tentando novamente com start_with_resto=yes...")
        set_optimizer_attribute(model, "start_with_resto", "yes")
        set_optimizer_attribute(model, "expect_infeasible_problem", "yes")
        optimize!(model)
        status = termination_status(model)
        println("Status após retentativa: ", status)
        if !(status in STATUS_OK)
            println("!! Solver não convergiu. CSVs podem refletir solução parcial.")
            return
        end
    end

    println("Erro de Controle (Slacks Ponderadas): ", objective_value(model))

    # =========================================================================
    # 14. RESUMO E DIAGNÓSTICO DE SLACKS
    # =========================================================================
    vetor_tensoes = [value(vm[i]) for i in keys(ref[:bus])]
    tensao_min = minimum(vetor_tensoes)
    tensao_max = maximum(vetor_tensoes)

    geracao_p_total = sum(value(pg[g]) for g in keys(ref[:gen]); init=0.0)
    geracao_q_total = sum(value(qg[g]) for g in keys(ref[:gen]); init=0.0)

    perda_p_total = sum(
        value(p[(l, b["f_bus"], b["t_bus"])]) + value(p[(l, b["t_bus"], b["f_bus"])])
        for (l, b) in ref[:branch]; init=0.0
    )

    viol_vlim_fisico = sum(value(sl_vm_upp[i]) + value(sl_vm_low[i]) for i in keys(ref[:bus]); init=0.0)
    viol_qlim        = sum(value(sl_qg_upp[i]) + value(sl_qg_low[i]) for i in keys(ref[:gen]); init=0.0)
    viol_bsh_lim     = sum(value(sl_bsh_upp[i]) + value(sl_bsh_low[i]) for i in keys(ref[:shunt]); init=0.0)
    corte_ativo      = sum(value(sl_p_d[l]) for l in keys(sl_p_d); init=0.0)
    corte_reativo    = sum(value(sl_d[l])   for l in keys(sl_d);   init=0.0)

    println("\n--- RESUMO OPERACIONAL GLOBAL ---")
    println("Tensão Mínima (pu):         ", round(tensao_min, digits=4))
    println("Tensão Máxima (pu):         ", round(tensao_max, digits=4))
    println("Geração Ativa Total (pu):   ", round(geracao_p_total, digits=4))
    println("Geração Reativa Total (pu): ", round(geracao_q_total, digits=4))
    println("Perdas Ativas (Total pu):   ", round(perda_p_total, digits=4))

    println("\n--- DIAGNÓSTICO DE SLACKS (somatório de violações em pu) ---")
    println("Violação VLIM físico:  ", round(viol_vlim_fisico, digits=4))
    println("Violação QLIM:         ", round(viol_qlim, digits=4))
    println("Violação shunt físico: ", round(viol_bsh_lim, digits=4))
    println("Corte de carga ATIVA:  ", round(corte_ativo, digits=4))
    println("Corte de carga REATIVA:", round(corte_reativo, digits=4))

    println("\n--- RESUMO EM UNIDADES REAIS (Base = $base_mva MVA) ---")
    println("Geração Ativa Total (MW):    ", round(geracao_p_total * base_mva, digits=2))
    println("Geração Reativa Total (MVAr):", round(geracao_q_total * base_mva, digits=2))
    println("Perdas Ativas Totais (MW):   ", round(perda_p_total * base_mva, digits=2))

    # =========================================================================
    # 15. EXPORTAÇÃO PARA CSV
    # =========================================================================
    println("\n6. Estruturando dados e gerando arquivos CSV...")

    df_barras = DataFrame(
        ID_Barra = Int[], Tipo_Barra = Int[],
        Tensao_Mag_pu = Float64[], Tensao_Ang_graus = Float64[],
        P_Geracao_pu = Float64[], Q_Geracao_pu = Float64[],
        P_Carga_pu = Float64[], Q_Carga_pu = Float64[],
        Desvio_Tensao_QLIM_pu = Float64[], Corte_Reativo_VLIM_pu = Float64[],
        Corte_Ativo_pu = Float64[], Viol_VmUpp_pu = Float64[], Viol_VmLow_pu = Float64[],
    )

    for (i, bus) in ref[:bus]
        bus_gens = ref[:bus_gens][i]
        bus_loads = ref[:bus_loads][i]
        push!(df_barras, (
            i, bus["bus_type"], value(vm[i]), value(va[i]) * (180.0 / pi),
            isempty(bus_gens)  ? 0.0 : sum(value(pg[g]) for g in bus_gens),
            isempty(bus_gens)  ? 0.0 : sum(value(qg[g]) for g in bus_gens),
            isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["pd"] for l in bus_loads),
            isempty(bus_loads) ? 0.0 : sum(ref[:load][l]["qd"] for l in bus_loads),
            (i in keys(sl_v)) ? value(sl_v[i]) : 0.0,
            isempty(bus_loads) ? 0.0 : sum(value(sl_d[l])   for l in bus_loads),
            isempty(bus_loads) ? 0.0 : sum(value(sl_p_d[l]) for l in bus_loads),
            value(sl_vm_upp[i]),
            value(sl_vm_low[i]),
        ))
    end
    sort!(df_barras, :ID_Barra)
    CSV.write(joinpath(PASTA_CSV, "resultados_barras_SIN.csv"), df_barras)

    df_linhas = DataFrame(
        ID_Linha = Int[], Barra_De = Int[], Barra_Para = Int[],
        P_Fluxo_De_Para_pu = Float64[], Q_Fluxo_De_Para_pu = Float64[],
        P_Fluxo_Para_De_pu = Float64[], Q_Fluxo_Para_De_pu = Float64[],
        Perda_Ativa_pu = Float64[], Tap_pu = Float64[],
    )

    for (l, branch) in ref[:branch]
        f = branch["f_bus"]; t = branch["t_bus"]
        val_p_from = value(p[(l, f, t)]); val_q_from = value(q[(l, f, t)])
        val_p_to   = value(p[(l, t, f)]); val_q_to   = value(q[(l, t, f)])
        val_tap    = value(tm_var[l])
        push!(df_linhas, (l, f, t, val_p_from, val_q_from, val_p_to, val_q_to, val_p_from + val_p_to, val_tap))
    end
    sort!(df_linhas, :ID_Linha)
    CSV.write(joinpath(PASTA_CSV, "resultados_fluxos_linhas_SIN.csv"), df_linhas)
    println("-> Arquivos CSV gerados em $PASTA_CSV")
end

# -----------------------------------------------------------------------------
# EXECUÇÃO PRINCIPAL
# -----------------------------------------------------------------------------
arquivo = joinpath(@__DIR__, "..", "data", "01 MAXIMA NOTURNA_DEZ25.PWF")
resolver_fluxo_controlado(arquivo)
