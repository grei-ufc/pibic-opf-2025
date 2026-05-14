# gerar_relatorio.jl — gera short-report-pibic-opf-DD-MM-YYYY.{md,pdf}
# a partir dos masters CSVs + clusters.csv produzidos por consolidar.jl.
#
# Estrutura conforme spec:
#   1. Tabela Resumo Global de Convergência e Clusters
#   2. Análise Barra-a-Barra (foco em "01 MAXIMA NOTURNA_DEZ25.PWF")
#   3. Fluxos nos Ramos
#   4. Avaliação de Impacto Sistêmico
#   5. Conclusão Técnica

using CSV
using DataFrames
using Dates
using Printf

const OUT_ROOT      = abspath(joinpath(@__DIR__, "..", "resultados_csv"))
const REPORTS_DIR   = abspath(joinpath(@__DIR__, "..", "..", "..", "..", "short-reports"))
const SCRIPT_ORDER  = ["14", "15", "16", "17", "18", "19"]
const SIN_CASE      = "01 MAXIMA NOTURNA_DEZ25.PWF"
const BARRA_TOL     = 1e-4

# Carregar
conv     = CSV.read(joinpath(OUT_ROOT, "convergencia.csv"), DataFrame)
barras   = isfile(joinpath(OUT_ROOT, "barras.csv")) ? CSV.read(joinpath(OUT_ROOT, "barras.csv"), DataFrame) : DataFrame()
ramos    = isfile(joinpath(OUT_ROOT, "ramos.csv")) ? CSV.read(joinpath(OUT_ROOT, "ramos.csv"), DataFrame) : DataFrame()
clusters = CSV.read(joinpath(OUT_ROOT, "clusters.csv"), DataFrame)

conv.script = string.(conv.script)
conv.caso = string.(conv.caso)
if !isempty(barras); barras.script = string.(barras.script); barras.caso = string.(barras.caso); end
if !isempty(ramos);  ramos.script  = string.(ramos.script);  ramos.caso  = string.(ramos.caso); end
clusters.script = string.(clusters.script)
clusters.caso = string.(clusters.caso)

# Helpers
function status_abbrev(s::AbstractString)
    s == "LOCALLY_SOLVED"     && return "OK"
    s == "INFEASIBLE"         && return "INF"
    s == "LOCALLY_INFEASIBLE" && return "INF"
    s == "ITERATION_LIMIT"    && return "ITL"
    s == "TIME_LIMIT"         && return "TIM"
    s == "TIMEOUT_KILLED"     && return "KIL"
    s == "SUBPROCESS_CRASH"   && return "CRA"
    s == "OTHER_ERROR"        && return "ERR"
    s == "INVALID_MODEL"      && return "INV"
    return "ERR"
end

function get_status(caso::AbstractString, script::AbstractString)
    sel = (conv.caso .== caso) .& (conv.script .== script)
    any(sel) || return "ERR"
    return status_abbrev(first(conv[sel, :termination_status]))
end

function get_loss_pu(caso::AbstractString, script::AbstractString)
    sel = (conv.caso .== caso) .& (conv.script .== script)
    any(sel) || return NaN
    v = first(conv[sel, :p_loss_total_pu])
    return v isa Number ? v : NaN
end

function get_cluster_summary(caso::AbstractString)
    # Retorna agrupamento "{14,15}·{16}·{17,18,19}" mostrando quais
    # formulações são equivalentes entre si (mesmo cluster_id).
    rows = filter(r -> r.caso == caso, clusters)
    grouping = Dict{String, Vector{String}}()
    for r in eachrow(rows)
        cid = String(r.cluster_id)
        cid == "N/C" && continue
        if !haskey(grouping, cid); grouping[cid] = String[]; end
        push!(grouping[cid], String(r.script))
    end
    isempty(grouping) && return "—"
    # Ordena clusters por menor script ID neles
    sorted_cids = sort(collect(keys(grouping));
        by = k -> minimum(parse.(Int, grouping[k])))
    parts = String[]
    for cid in sorted_cids
        scripts = sort(grouping[cid]; by=x->parse(Int, x))
        push!(parts, "{" * join(scripts, ",") * "}")
    end
    return join(parts, "·")
end

function cluster_id_for(caso::AbstractString, script::AbstractString)
    sel = (clusters.caso .== caso) .& (clusters.script .== script)
    any(sel) || return "N/C"
    return String(first(clusters[sel, :cluster_id]))
end

function is_equivalent_to_pm(caso::AbstractString, script::AbstractString)
    cid = cluster_id_for(caso, script)
    cid == "N/C" && return false
    cid14 = cluster_id_for(caso, "14")
    cid15 = cluster_id_for(caso, "15")
    return cid == cid14 || cid == cid15
end

# Coletar casos em ordem
all_cases = sort(unique(conv.caso))
# SIN primeiro se existir
if SIN_CASE in all_cases
    all_cases = vcat([SIN_CASE], filter(!=(SIN_CASE), all_cases))
end

# === Seção 1: Tabela Resumo Global ===
function section1()
    io = IOBuffer()
    println(io, "## 1. Tabela Resumo Global de Convergência e Clusters")
    println(io)
    println(io, "Status abreviados: **OK**=LOCALLY_SOLVED · **INF**=INFEASIBLE/LOCALLY_INFEASIBLE · **ITL**=ITERATION_LIMIT · **TIM**=TIME_LIMIT · **KIL**=TIMEOUT_KILLED · **CRA**=SUBPROCESS_CRASH · **INV**=INVALID_MODEL · **ERR**=OTHER_ERROR")
    println(io)
    println(io, "**Grupos equivalentes**: formulações dentro do mesmo `{…}` produziram resultado numericamente idêntico (|Δ| ≤ 1e-4 em vm/va/pg/qg/pf/qf). Grupos separados por `·` indicam soluções distintas.")
    println(io)
    println(io, "| Caso | (14) | (15) | (16) | (17) | (18) | (19) | Grupos equivalentes | Observações |")
    println(io, "|---|---|---|---|---|---|---|---|---|")
    for caso in all_cases
        statuses = [get_status(caso, s) for s in SCRIPT_ORDER]
        cluster_summary = get_cluster_summary(caso)
        obs = ""
        n_failed = count(!=("OK"), statuses)
        if n_failed == 6; obs = "Nenhuma formulação convergiu"
        elseif n_failed > 0; obs = "$n_failed/6 não convergiram"
        elseif count("{", cluster_summary) == 1; obs = "Todas equivalentes"
        end
        println(io, "| `$caso` | $(statuses[1]) | $(statuses[2]) | $(statuses[3]) | $(statuses[4]) | $(statuses[5]) | $(statuses[6]) | $cluster_summary | $obs |")
    end
    return String(take!(io))
end

# === Seção 2: Análise Barra-a-Barra ===
# Para cada caso, listar barras onde (vm OU va) em (16)/(17)/(18)/(19) difere
# de AMBAS (14) E (15) por > BARRA_TOL.
function section2()
    io = IOBuffer()
    println(io, "## 2. Análise Barra-a-Barra")
    println(io)
    println(io, "Critério: para cada barra, listada apenas se vm ou va em (16)/(17)/(18)/(19) excede $BARRA_TOL em relação a AMBAS (14) E (15). Cada barra divergente é exibida com uma linha para (14) e (15) (quando convergiram) e uma linha para cada script (16)–(19) que divergiu, permitindo comparar os valores absolutos lado a lado. Scripts (16)–(19) numericamente equivalentes (mesmo cluster) a (14) ou (15) são omitidos do caso. As colunas `pg` e `qg` somam a geração ativa e reativa (em pu) de todas as máquinas conectadas à barra; quando a barra não tem gerador, exibe-se `—`.")
    println(io)

    if isempty(barras)
        println(io, "_Sem dados de barras (master barras.csv vazio)._")
        return String(take!(io))
    end

    for caso in all_cases
        b14 = filter(r -> r.caso == caso && r.script == "14", barras)
        b15 = filter(r -> r.caso == caso && r.script == "15", barras)
        if isempty(b14) && isempty(b15)
            println(io, "### Caso `$caso`")
            println(io)
            println(io, "_Nenhuma referência (14) ou (15) convergiu para este caso; análise pulada._")
            println(io)
            continue
        end
        b14_map = isempty(b14) ? Dict{Int, Any}() : Dict(r.bus_id => r for r in eachrow(b14))
        b15_map = isempty(b15) ? Dict{Int, Any}() : Dict(r.bus_id => r for r in eachrow(b15))

        # Para cada barra divergente, guarda os scripts (16-19) que efetivamente divergiram
        # e os valores (vm, va, pg, qg) desses scripts.
        divergent_buses = Dict{Int, Vector{String}}()
        script_values   = Dict{Tuple{Int,String}, NTuple{4,Float64}}()

        skipped_scripts = String[]
        for s in ["16", "17", "18", "19"]
            if is_equivalent_to_pm(caso, s)
                push!(skipped_scripts, s)
                continue
            end
            bs = filter(r -> r.caso == caso && r.script == s, barras)
            isempty(bs) && continue
            for r in eachrow(bs)
                bid = r.bus_id
                diff_14_vm = NaN; diff_14_va = NaN
                diff_15_vm = NaN; diff_15_va = NaN
                if haskey(b14_map, bid)
                    row14 = b14_map[bid]
                    diff_14_vm = abs(r.vm_pu - row14.vm_pu)
                    diff_14_va = abs(r.va_rad - row14.va_rad)
                end
                if haskey(b15_map, bid)
                    row15 = b15_map[bid]
                    diff_15_vm = abs(r.vm_pu - row15.vm_pu)
                    diff_15_va = abs(r.va_rad - row15.va_rad)
                end
                vm_div = (isnan(diff_14_vm) || diff_14_vm > BARRA_TOL) && (isnan(diff_15_vm) || diff_15_vm > BARRA_TOL)
                va_div = (isnan(diff_14_va) || diff_14_va > BARRA_TOL) && (isnan(diff_15_va) || diff_15_va > BARRA_TOL)
                ref_exists = haskey(b14_map, bid) || haskey(b15_map, bid)
                if ref_exists && (vm_div || va_div)
                    if !haskey(divergent_buses, bid); divergent_buses[bid] = String[]; end
                    push!(divergent_buses[bid], s)
                    script_values[(bid, s)] = (r.vm_pu, r.va_rad, r.pg_pu, r.qg_pu)
                end
            end
        end

        println(io, "### Caso `$caso`")
        println(io)
        if !isempty(skipped_scripts)
            println(io, "_Scripts equivalentes a (14)/(15) (mesmo cluster): $(join(["($s)" for s in skipped_scripts], ", "))._")
            println(io)
        end
        if isempty(divergent_buses)
            println(io, "_Nenhuma barra diverge das referências (14)/(15) acima da tolerância de $BARRA_TOL._")
            println(io)
        else
            println(io, "| Barra | Script | vm (pu) | va (rad) | pg (pu) | qg (pu) |")
            println(io, "|---|---|---|---|---|---|")
            fmt_pq(v) = (isnan(v) || v == 0.0) ? "—" : @sprintf("%.4f", v)
            sorted_bus_ids = sort(collect(keys(divergent_buses)))
            limit_buses = caso == SIN_CASE ? length(sorted_bus_ids) : min(20, length(sorted_bus_ids))
            for (i, bid) in enumerate(sorted_bus_ids)
                i > limit_buses && break
                if haskey(b14_map, bid)
                    row = b14_map[bid]
                    println(io, "| $bid | (14) | $(@sprintf("%.4f", row.vm_pu)) | $(@sprintf("%.4e", row.va_rad)) | $(fmt_pq(row.pg_pu)) | $(fmt_pq(row.qg_pu)) |")
                end
                if haskey(b15_map, bid)
                    row = b15_map[bid]
                    println(io, "| $bid | (15) | $(@sprintf("%.4f", row.vm_pu)) | $(@sprintf("%.4e", row.va_rad)) | $(fmt_pq(row.pg_pu)) | $(fmt_pq(row.qg_pu)) |")
                end
                for s in ["16", "17", "18", "19"]
                    if s in divergent_buses[bid]
                        (vm, va, pg, qg) = script_values[(bid, s)]
                        println(io, "| $bid | ($s) | $(@sprintf("%.4f", vm)) | $(@sprintf("%.4e", va)) | $(fmt_pq(pg)) | $(fmt_pq(qg)) |")
                    end
                end
            end
            if limit_buses < length(sorted_bus_ids)
                println(io, "_(mostrando $limit_buses de $(length(sorted_bus_ids)) barras divergentes; tabela truncada)_")
            end
            println(io)
        end
    end
    return String(take!(io))
end

# === Seção 3: Fluxos nos Ramos ===
function section3()
    io = IOBuffer()
    println(io, "## 3. Fluxos nos Ramos")
    println(io)
    println(io, "Mesmo critério da Seção 2 aplicado a `pf_pu`, `qf_pu`, `pt_pu`, `qt_pu` (excede $BARRA_TOL em AMBAS (14) E (15)). Cada ramo divergente é exibido com uma linha para (14) e (15) e uma para cada script (16)–(19) que divergiu. Scripts (16)–(19) numericamente equivalentes (mesmo cluster) a (14) ou (15) são omitidos do caso. A coluna `Ramo (f→t)` traz o `branch_id` seguido das barras de envio (`f_bus`) e recepção (`t_bus`); `pf`/`qf` são os fluxos no terminal `f` e `pt`/`qt` no terminal `t`.")
    println(io)

    if isempty(ramos)
        println(io, "_Sem dados de ramos (master ramos.csv vazio)._")
        return String(take!(io))
    end

    for caso in all_cases
        r14 = filter(r -> r.caso == caso && r.script == "14", ramos)
        r15 = filter(r -> r.caso == caso && r.script == "15", ramos)
        if isempty(r14) && isempty(r15)
            println(io, "### Caso `$caso`")
            println(io)
            println(io, "_Sem referência convergida; análise pulada._")
            println(io)
            continue
        end
        r14_map = isempty(r14) ? Dict{Int, Any}() : Dict(r.branch_id => r for r in eachrow(r14))
        r15_map = isempty(r15) ? Dict{Int, Any}() : Dict(r.branch_id => r for r in eachrow(r15))

        divergent_branches = Dict{Int, Vector{String}}()
        script_values      = Dict{Tuple{Int,String}, NTuple{4,Float64}}()
        # branch_id → (f_bus, t_bus), preenchido a partir de qualquer linha disponível
        branch_endpoints   = Dict{Int, Tuple{Int,Int}}()
        for r in eachrow(filter(r -> r.caso == caso, ramos))
            if !haskey(branch_endpoints, r.branch_id)
                branch_endpoints[r.branch_id] = (Int(r.f_bus), Int(r.t_bus))
            end
        end
        ramo_label(bid) = haskey(branch_endpoints, bid) ?
            (let (f,t)=branch_endpoints[bid]; "$bid ($f→$t)" end) :
            "$bid"

        skipped_scripts = String[]
        for s in ["16", "17", "18", "19"]
            if is_equivalent_to_pm(caso, s)
                push!(skipped_scripts, s)
                continue
            end
            rs = filter(r -> r.caso == caso && r.script == s, ramos)
            isempty(rs) && continue
            for r in eachrow(rs)
                bid = r.branch_id
                d14 = (NaN, NaN, NaN, NaN)
                d15 = (NaN, NaN, NaN, NaN)
                if haskey(r14_map, bid)
                    row14 = r14_map[bid]
                    d14 = (abs(r.pf_pu - row14.pf_pu), abs(r.qf_pu - row14.qf_pu),
                           abs(r.pt_pu - row14.pt_pu), abs(r.qt_pu - row14.qt_pu))
                end
                if haskey(r15_map, bid)
                    row15 = r15_map[bid]
                    d15 = (abs(r.pf_pu - row15.pf_pu), abs(r.qf_pu - row15.qf_pu),
                           abs(r.pt_pu - row15.pt_pu), abs(r.qt_pu - row15.qt_pu))
                end

                diverge = false
                for k in 1:4
                    a = isnan(d14[k]) ? Inf : d14[k]
                    b = isnan(d15[k]) ? Inf : d15[k]
                    if a > BARRA_TOL && b > BARRA_TOL
                        diverge = true
                        break
                    end
                end
                ref_exists = haskey(r14_map, bid) || haskey(r15_map, bid)
                if ref_exists && diverge
                    if !haskey(divergent_branches, bid); divergent_branches[bid] = String[]; end
                    push!(divergent_branches[bid], s)
                    script_values[(bid, s)] = (r.pf_pu, r.qf_pu, r.pt_pu, r.qt_pu)
                end
            end
        end

        println(io, "### Caso `$caso`")
        println(io)
        if !isempty(skipped_scripts)
            println(io, "_Scripts equivalentes a (14)/(15) (mesmo cluster): $(join(["($s)" for s in skipped_scripts], ", "))._")
            println(io)
        end
        if isempty(divergent_branches)
            println(io, "_Nenhum ramo diverge das referências (14)/(15) acima de $BARRA_TOL._")
            println(io)
        else
            println(io, "| Ramo (f→t) | Script | pf (pu) | qf (pu) | pt (pu) | qt (pu) |")
            println(io, "|---|---|---|---|---|---|")
            sorted_branch_ids = sort(collect(keys(divergent_branches)))
            limit_branches = caso == SIN_CASE ? length(sorted_branch_ids) : min(20, length(sorted_branch_ids))
            for (i, bid) in enumerate(sorted_branch_ids)
                i > limit_branches && break
                lbl = ramo_label(bid)
                if haskey(r14_map, bid)
                    row = r14_map[bid]
                    println(io, "| $lbl | (14) | $(@sprintf("%.4f", row.pf_pu)) | $(@sprintf("%.4f", row.qf_pu)) | $(@sprintf("%.4f", row.pt_pu)) | $(@sprintf("%.4f", row.qt_pu)) |")
                end
                if haskey(r15_map, bid)
                    row = r15_map[bid]
                    println(io, "| $lbl | (15) | $(@sprintf("%.4f", row.pf_pu)) | $(@sprintf("%.4f", row.qf_pu)) | $(@sprintf("%.4f", row.pt_pu)) | $(@sprintf("%.4f", row.qt_pu)) |")
                end
                for s in ["16", "17", "18", "19"]
                    if s in divergent_branches[bid]
                        (pf, qf, pt, qt) = script_values[(bid, s)]
                        println(io, "| $lbl | ($s) | $(@sprintf("%.4f", pf)) | $(@sprintf("%.4f", qf)) | $(@sprintf("%.4f", pt)) | $(@sprintf("%.4f", qt)) |")
                    end
                end
            end
            if limit_branches < length(sorted_branch_ids)
                println(io, "_(mostrando $limit_branches de $(length(sorted_branch_ids)) ramos divergentes; tabela truncada)_")
            end
            println(io)
        end
    end
    return String(take!(io))
end

# === Seção 4: Avaliação de Impacto Sistêmico ===
function section4()
    io = IOBuffer()
    println(io, "## 4. Avaliação de Impacto Sistêmico")
    println(io)
    println(io, "Tabela de perdas totais (em pu, na base do caso). ΔP_loss% calculado em relação a (14) e (15) quando ambas convergiram. Para converter para MW, multiplique pela baseMVA do caso (tipicamente 100 MVA).")
    println(io)

    println(io, "| Caso | (14) | (15) | (16) | (17) | (18) | (19) | Δ% vs(14): 17/18/19 | Δ% vs(15): 17/18/19 |")
    println(io, "|---|---|---|---|---|---|---|---|---|")
    for caso in all_cases
        losses = Dict(s => get_loss_pu(caso, s) for s in SCRIPT_ORDER)
        function fmt(v)
            isnan(v) ? "—" : @sprintf("%.5f", v)
        end
        function pct(num, den)
            (isnan(num) || isnan(den) || abs(den) < 1e-9) ? "—" : @sprintf("%+.2f%%", 100*(num-den)/den)
        end
        d14 = losses["14"]
        d15 = losses["15"]
        delta_vs14 = "$(pct(losses["17"], d14)) / $(pct(losses["18"], d14)) / $(pct(losses["19"], d14))"
        delta_vs15 = "$(pct(losses["17"], d15)) / $(pct(losses["18"], d15)) / $(pct(losses["19"], d15))"
        println(io, "| `$caso` | $(fmt(losses["14"])) | $(fmt(losses["15"])) | $(fmt(losses["16"])) | $(fmt(losses["17"])) | $(fmt(losses["18"])) | $(fmt(losses["19"])) | $delta_vs14 | $delta_vs15 |")
    end
    println(io)
    return String(take!(io))
end

# === Seção 5: Conclusão Técnica ===
function section5()
    io = IOBuffer()
    println(io, "## 5. Conclusão Técnica")
    println(io)
    # Conta convergências por formulação
    rate = Dict{String, Tuple{Int,Int}}()
    for s in SCRIPT_ORDER
        ok = sum(get_status(c, s) == "OK" for c in all_cases)
        rate[s] = (ok, length(all_cases))
    end

    println(io, "**Robustez de convergência (sobre $(length(all_cases)) casos):**")
    println(io)
    for s in SCRIPT_ORDER
        ok, tot = rate[s]
        @printf(io, "- (%s): %d/%d (%.1f%%)\n", s, ok, tot, 100*ok/tot)
    end
    println(io)

    println(io, """
**Interpretação física dos controles:**

- **QLIM** (limites de Q dos geradores; introduzido em (16)): impõe o setpoint de tensão das barras PV via slack quadrático `sl_v[i]`. Quando o reativo de máquina satura, a barra migra efetivamente para PQ — visualizável em casos onde `vm_pu` em (16)/(17)/(18) diverge do PF tradicional (15) porque a referência de tensão é abandonada pelo gerador saturado. Esperado: pequena perturbação no perfil de tensão em barras vizinhas a geradores com folga reduzida de Q.

- **CSCA** (controle de susceptância shunt; introduzido em (17)): libera `bs_var[i]` como variável de decisão dentro de `[bsmin, bsmax]` lido do bloco DOPC do PWF. Onde o ANAREDE permite chaveamento (banco capacitivo/reativo), o OPF pode redespachar reativo localmente — tende a aliviar tensão em barras de carga e reduzir geração reativa de máquinas, podendo diminuir perdas. Esperado: ΔP_loss negativo (perdas menores) em casos com shunts controláveis significativos.

- **CTAP** (controle de tap em transformadores; introduzido em (18)): libera `tm_var[l]` como contínuo em `[tapmin, tapmax]`. Modifica a relação de transformação para redistribuir fluxos e tensões secundárias. Diferente do CSCA (que adiciona Q local), o CTAP redistribui fluxo ao longo do ramo. Pode competir com o CSCA — ambos atuam sobre tensão, mas com mecanismos físicos distintos. Esperado: efeito de segunda ordem no perfil de tensão e nas perdas; impacto maior em redes com folga de tap.

- **DERA** (corte de carga preventivo; introduzido em (19)): adiciona `corte_p[l]` ∈ `[0, pd]` e `corte_q[l]` (vínculado por fator de potência da carga). Penalidade hierárquica por nível de tensão (`1e7` para <69 kV, `5e7` para 69–230 kV, `1e8` para >230 kV) faz com que o solver prefira cortar carga na distribuição antes de cortar em EAT. Esperado: corte zero quando a rede está OK; corte positivo apenas em casos onde os outros controles não bastam para satisfazer as restrições.

**Interações:**

- *CTAP × CSCA*: podem atuar sobre o mesmo objetivo de tensão, mas o solver tende a preferir a manobra de menor "custo" (PENALIDADE_MENOR = 1e4 para shunt, sem penalidade para tap) — ou seja, CTAP age primeiro quando disponível.
- *DERA × resto*: DERA tem peso ≥ 1e7 (>> PENALIDADE = 1e6 dos slacks). Logo, o solver só cortará carga quando o resto realmente não conseguir respeitar QLIM/VLIM dentro das margens disponíveis. Casos onde DERA mostra corte > 0 (visíveis pela diferença de carga entre (19) e (14)/(15) na tabela de perdas) indicam estresse efetivo da rede.

**Convergência:** quanto mais variáveis e slacks o modelo adiciona, mais sensível à inicialização e às tolerâncias o Ipopt fica. Casos pequenos (3bus/5bus) convergem facilmente em todas as formulações; redes maiores (300bus, 500bus, SIN) podem expor diferenças de robustez entre (14)/(15) (PowerModels) e as variantes JuMP (16)–(19). Iter count não foi capturado nesta bateria (Ipopt MOI não expôs `BarrierIterations` para os solves rodados); para análise futura, pode-se parsear o log do Ipopt onde aparece "Number of Iterations....:".
    """)
    return String(take!(io))
end

# === Montagem do relatório ===
hoje = Dates.today()
date_iso = string(Dates.now())
date_short = Dates.format(hoje, "dd-mm-yyyy")
md_path = joinpath(REPORTS_DIR, "short-report-pibic-opf-$date_short.md")
pdf_path = joinpath(REPORTS_DIR, "short-report-pibic-opf-$date_short.pdf")

mkpath(REPORTS_DIR)

open(md_path, "w") do io
    println(io, "# Bateria PF AC — Comparação (14)–(19)")
    println(io, "_Gerado em $(date_iso)_")
    println(io)
    print(io, section1())
    println(io)
    print(io, section2())
    println(io)
    print(io, section3())
    println(io)
    print(io, section4())
    println(io)
    print(io, section5())
end

println("Relatório markdown escrito em: $md_path")

# Converter para PDF via pandoc
cmd = `pandoc $md_path -o $pdf_path --pdf-engine=xelatex -V geometry:margin=2cm --highlight-style=tango`
println("Executando: $cmd")
try
    run(cmd)
    pdf_size = filesize(pdf_path)
    if pdf_size < 10_000
        @warn "PDF gerado com tamanho suspeito: $pdf_size bytes ($(pdf_path))"
    else
        println("PDF escrito em: $pdf_path ($(pdf_size) bytes)")
    end
catch e
    @error "Falha na geração do PDF" exception=(e, catch_backtrace())
    rethrow()
end
