# rerun_sin.jl — Re-roda APENAS o caso "01 MAXIMA NOTURNA_DEZ25.PWF" para os 6 variantes
# SEM wall-clock timeout. Respeita apenas o max_iter=3000 do Ipopt já configurado
# nas variantes. Sobrescreve as saídas anteriores em resultados_csv/<script>/01_MAXIMA_NOTURNA_DEZ25/.
#
# Pool de 4 workers paralelos.

using CSV
using DataFrames
using Dates

const REPO_ROOT   = abspath(joinpath(@__DIR__, "..", "..", "..", ".."))
const RUNNER_DIR  = @__DIR__
const PF_FORM_DIR = abspath(joinpath(@__DIR__, ".."))
const DATA_DIR    = abspath(joinpath(@__DIR__, "..", "..", "data"))
const OUT_ROOT    = abspath(joinpath(PF_FORM_DIR, "resultados_csv"))
const LOGS_DIR    = joinpath(OUT_ROOT, "logs")

const SIN_PATH    = joinpath(DATA_DIR, "01 MAXIMA NOTURNA_DEZ25.PWF")
const SIN_CASE_ID = "01 MAXIMA NOTURNA_DEZ25.PWF"
const SIN_DIRNAME = "01_MAXIMA_NOTURNA_DEZ25"

const VARIANTS = [
    ("14", joinpath(RUNNER_DIR, "variant_14_OPF_PM.jl")),
    ("15", joinpath(RUNNER_DIR, "variant_15_PF_PM.jl")),
    ("16", joinpath(RUNNER_DIR, "variant_16_QLIM_VLIM.jl")),
    ("17", joinpath(RUNNER_DIR, "variant_17_CSCA.jl")),
    ("18", joinpath(RUNNER_DIR, "variant_18_CTAP.jl")),
    ("19", joinpath(RUNNER_DIR, "variant_19_DERA.jl")),
]

const NUM_WORKERS = 4

println("=" ^ 70)
println("rerun_sin.jl  —  $(Dates.now())")
println("=" ^ 70)
println("SIN_PATH = $SIN_PATH")
println("OUT_ROOT = $OUT_ROOT")
println("Workers paralelos: $NUM_WORKERS  /  SEM wall-clock timeout (Ipopt max_iter=3000)")

mkpath(LOGS_DIR)

function run_sin(spec)
    sid, spath = spec
    out_dir = joinpath(OUT_ROOT, sid, SIN_DIRNAME)
    # Limpa rodada anterior do SIN para esta variante
    if isdir(out_dir); rm(out_dir; recursive=true, force=true); end
    mkpath(out_dir)
    log_path = joinpath(LOGS_DIR, "rerun_SIN__$(sid).log")

    env = copy(ENV)
    env["PIBIC_PWF"]      = SIN_PATH
    env["PIBIC_CSV_DIR"]  = out_dir
    env["PIBIC_CASE_ID"]  = SIN_CASE_ID
    env["PIBIC_SCRIPT"]   = sid
    env["JULIA_NUM_THREADS"] = "1"

    cmd = Cmd(`julia --project=$REPO_ROOT --color=no $spath`; env=env)

    t0 = time()
    proc_status = "UNKNOWN"
    log_io = open(log_path, "w")
    try
        run(pipeline(cmd; stdout=log_io, stderr=log_io))
        proc_status = "OK_EXIT"
    catch e
        proc_status = "SUBPROCESS_FAIL"
        @warn "($sid) subprocess failed" exception=e
    finally
        close(log_io)
    end
    elapsed = time() - t0

    conv_path = joinpath(out_dir, "convergencia.csv")
    if !isfile(conv_path)
        injected = proc_status == "SUBPROCESS_FAIL" ? "SUBPROCESS_CRASH" : "OTHER_ERROR"
        df = DataFrame(
            caso = [SIN_CASE_ID], script = [sid],
            termination_status = [injected],
            solve_time_s = [NaN], objective = [NaN],
            iteracoes = [NaN], p_loss_total_pu = [NaN],
        )
        CSV.write(conv_path, df)
    end

    df = CSV.read(conv_path, DataFrame)
    final_status = String(first(df.termination_status))
    println("[$sid] SIN → $final_status  ($(round(elapsed/60, digits=1)) min)")
    return (sid, final_status, elapsed)
end

println("\nLançando 6 jobs em pool de $NUM_WORKERS workers...")
t_start = time()
results = asyncmap(run_sin, VARIANTS; ntasks=NUM_WORKERS)
t_total = time() - t_start
println("\nrerun_sin terminou em $(round(t_total/60, digits=1)) min")

println("\n=== Resumo final ===")
for (sid, status, elapsed) in results
    println("  ($sid): $status  ($(round(elapsed/60, digits=1)) min)")
end
