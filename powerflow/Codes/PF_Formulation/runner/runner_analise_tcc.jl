# runner_analise_tcc.jl — Orquestrador para 6 variantes × N casos .pwf.
#
# Invocação:
#   julia --project=. powerflow/Codes/PF_Formulation/runner/runner_analise_tcc.jl
#
# Comportamento:
#   - Descobre todos os .pwf em powerflow/Codes/data/
#   - Lança 6×N subprocessos com ENV (PIBIC_PWF, PIBIC_CSV_DIR, PIBIC_CASE_ID)
#   - Pool de 4 workers (asyncmap)
#   - Timeout: 1800s para "01 MAXIMA NOTURNA_DEZ25.PWF", 600s para os demais
#   - Statuses que o runner injeta quando o subprocesso não escreve convergencia.csv:
#       TIMEOUT_KILLED, SUBPROCESS_CRASH, OTHER_ERROR
#   - Saída: resultados_csv/<script>/<caso_sanitizado>/{barras,ramos,convergencia}.csv
#           + master files concatenados em resultados_csv/{barras,ramos,convergencia}.csv

using CSV
using DataFrames
using Dates

const REPO_ROOT     = abspath(joinpath(@__DIR__, "..", "..", "..", ".."))
const PF_FORM_DIR   = abspath(joinpath(@__DIR__, ".."))
const DATA_DIR      = abspath(joinpath(@__DIR__, "..", "..", "data"))
const RUNNER_DIR    = @__DIR__
const OUT_ROOT      = abspath(joinpath(PF_FORM_DIR, "resultados_csv"))
const LOGS_DIR      = joinpath(OUT_ROOT, "logs")

const SCRIPTS = [
    ("14", joinpath(RUNNER_DIR, "variant_14_OPF_PM.jl")),
    ("15", joinpath(RUNNER_DIR, "variant_15_PF_PM.jl")),
    ("16", joinpath(RUNNER_DIR, "variant_16_QLIM_VLIM.jl")),
    ("17", joinpath(RUNNER_DIR, "variant_17_CSCA.jl")),
    ("18", joinpath(RUNNER_DIR, "variant_18_CTAP.jl")),
    ("19", joinpath(RUNNER_DIR, "variant_19_DERA.jl")),
]

const SIN_CASE = "01 MAXIMA NOTURNA_DEZ25.PWF"
const TIMEOUT_DEFAULT_S = 600
const TIMEOUT_SIN_S     = 1800
const NUM_WORKERS       = 4

# ----- Setup -----
println("=" ^ 70)
println("runner_analise_tcc.jl  —  $(Dates.now())")
println("=" ^ 70)
println("REPO_ROOT  = $REPO_ROOT")
println("DATA_DIR   = $DATA_DIR")
println("OUT_ROOT   = $OUT_ROOT")

# Limpa resultados_csv/ inteiro
if isdir(OUT_ROOT)
    println("Limpando $OUT_ROOT ...")
    for entry in readdir(OUT_ROOT; join=true)
        rm(entry; recursive=true, force=true)
    end
end
mkpath(OUT_ROOT)
mkpath(LOGS_DIR)

# Descobre casos
function find_pwf_files(dir)
    out = String[]
    for (root, _, files) in walkdir(dir)
        # Ignora data_CPF/ se existir
        occursin("/data_CPF", root) && continue
        for f in files
            if endswith(lowercase(f), ".pwf")
                push!(out, joinpath(root, f))
            end
        end
    end
    sort!(out; by=basename)
    return out
end

pwf_files = find_pwf_files(DATA_DIR)
println("Encontrados $(length(pwf_files)) arquivos .pwf:")
for p in pwf_files; println("  $(basename(p))"); end

# Sanitiza nome de caso para diretório
function sanitize(name::String)
    s = replace(name, " " => "_")
    s = replace(s, ".pwf" => "")
    s = replace(s, ".PWF" => "")
    return s
end

# Monta lista de jobs (par script×caso)
struct Job
    script_id::String
    script_path::String
    case_path::String
    case_id::String
    case_dir::String   # sanitized
    out_dir::String
    log_path::String
    timeout_s::Int
end

jobs = Job[]
for (sid, spath) in SCRIPTS
    for cpath in pwf_files
        cid = basename(cpath)
        cdir = sanitize(cid)
        out = joinpath(OUT_ROOT, sid, cdir)
        log = joinpath(LOGS_DIR, "$(sid)__$(cdir).log")
        tout = (cid == SIN_CASE) ? TIMEOUT_SIN_S : TIMEOUT_DEFAULT_S
        push!(jobs, Job(sid, spath, cpath, cid, cdir, out, log, tout))
    end
end
println("Total de jobs: $(length(jobs))  ($(length(SCRIPTS)) scripts × $(length(pwf_files)) casos)")

# ----- Execução de um job (subprocesso isolado) -----
function run_job(j::Job)
    mkpath(j.out_dir)
    mkpath(dirname(j.log_path))

    env = copy(ENV)
    env["PIBIC_PWF"]      = j.case_path
    env["PIBIC_CSV_DIR"]  = j.out_dir
    env["PIBIC_CASE_ID"]  = j.case_id
    env["PIBIC_SCRIPT"]   = j.script_id
    env["JULIA_NUM_THREADS"] = "1"

    cmd = Cmd(`julia --project=$REPO_ROOT --color=no $(j.script_path)`; env=env)

    t0 = time()
    proc_status = "UNKNOWN"
    log_io = open(j.log_path, "w")
    try
        proc = run(pipeline(cmd; stdout=log_io, stderr=log_io); wait=false)

        # Timeout watchdog
        deadline = t0 + j.timeout_s
        killed = false
        while process_running(proc)
            if time() > deadline
                kill(proc)
                killed = true
                # Dar uns segundos para morrer
                kill_t0 = time()
                while process_running(proc) && time() - kill_t0 < 5
                    sleep(0.2)
                end
                process_running(proc) && kill(proc, Base.SIGKILL)
                break
            end
            sleep(0.5)
        end
        wait(proc)
        ec = proc.exitcode
        if killed
            proc_status = "TIMEOUT_KILLED"
        elseif ec != 0
            proc_status = "SUBPROCESS_CRASH"
        else
            proc_status = "OK_EXIT"
        end
    catch e
        proc_status = "RUNNER_ERROR"
        @warn "Falha lançando subprocesso para $(j.script_id)__$(j.case_id)" exception=(e, catch_backtrace())
    finally
        close(log_io)
    end
    elapsed = time() - t0

    # Verifica se convergencia.csv foi escrito
    conv_path = joinpath(j.out_dir, "convergencia.csv")
    if !isfile(conv_path)
        # Subprocesso não conseguiu escrever — injeta linha conforme proc_status
        injected_status = if proc_status == "TIMEOUT_KILLED"
            "TIMEOUT_KILLED"
        elseif proc_status == "SUBPROCESS_CRASH"
            "SUBPROCESS_CRASH"
        else
            "OTHER_ERROR"
        end
        # Escreve diretamente (não usa helper para evitar dependência cíclica)
        df = DataFrame(
            caso = [j.case_id], script = [j.script_id],
            termination_status = [injected_status],
            solve_time_s = [NaN], objective = [NaN],
            iteracoes = [NaN], p_loss_total_pu = [NaN],
        )
        CSV.write(conv_path, df)
    end

    # Lê status final
    try
        df = CSV.read(conv_path, DataFrame)
        final_status = String(first(df.termination_status))
        println("[$(lpad(j.script_id, 2))] $(rpad(j.case_id, 38)) → $(rpad(final_status, 18)) ($(round(elapsed, digits=1))s)")
        return final_status, elapsed
    catch e
        @warn "Não consegui ler convergencia.csv após job $(j.script_id)/$(j.case_dir)" exception=e
        return "READ_FAILED", elapsed
    end
end

# ----- Execução paralela com pool de 4 workers -----
println("\nLançando $(length(jobs)) jobs em pool de $NUM_WORKERS workers...")
t_start = time()
results = asyncmap(run_job, jobs; ntasks=NUM_WORKERS)
t_total = time() - t_start
println("\nBatch finalizado em $(round(t_total, digits=1))s ($(round(t_total/60, digits=1)) min)")

# ----- Consolidação: concatena CSVs por job em masters -----
println("\nConsolidando CSVs master...")

function read_optional(path)
    isfile(path) ? CSV.read(path, DataFrame) : nothing
end

master_conv = DataFrame()
master_barras = DataFrame()
master_ramos = DataFrame()

for j in jobs
    cv = read_optional(joinpath(j.out_dir, "convergencia.csv"))
    if cv !== nothing
        master_conv = isempty(master_conv) ? cv : vcat(master_conv, cv; cols=:union)
    end
    br = read_optional(joinpath(j.out_dir, "barras.csv"))
    if br !== nothing
        master_barras = isempty(master_barras) ? br : vcat(master_barras, br; cols=:union)
    end
    rm = read_optional(joinpath(j.out_dir, "ramos.csv"))
    if rm !== nothing
        master_ramos = isempty(master_ramos) ? rm : vcat(master_ramos, rm; cols=:union)
    end
end

CSV.write(joinpath(OUT_ROOT, "convergencia.csv"), master_conv)
CSV.write(joinpath(OUT_ROOT, "barras.csv"),       master_barras)
CSV.write(joinpath(OUT_ROOT, "ramos.csv"),        master_ramos)

println("Masters escritos:")
println("  convergencia.csv  ($(nrow(master_conv)) linhas)")
println("  barras.csv        ($(nrow(master_barras)) linhas)")
println("  ramos.csv         ($(nrow(master_ramos)) linhas)")

# ----- Sumário por script -----
println("\n=== Taxa de convergência por script ===")
if nrow(master_conv) > 0
    grp = combine(groupby(master_conv, :script),
                  :termination_status => (s -> sum(s .== "LOCALLY_SOLVED")) => :ok,
                  :termination_status => length => :total)
    for r in eachrow(grp)
        pct = round(100 * r.ok / r.total, digits=1)
        println("  ($(r.script)): $(r.ok)/$(r.total)  ($pct%)")
    end
end

println("\nDone.")
