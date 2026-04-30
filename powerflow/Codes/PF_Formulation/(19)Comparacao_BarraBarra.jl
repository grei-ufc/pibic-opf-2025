# =========================================================================
# COMPARAÇÃO BARRA A BARRA
# Compara o estado original do PWF (caso convergido no ANAREDE) com o
# resultado de uma das formulações otimizadas.
#
# COMO USAR:
#   1. Rode primeiro um dos códigos (9, 10, 12, 14, 16, 17 ou 15) para gerar
#      o CSV de resultados (ex.: "resultados_barras_SIN.csv").
#   2. Ajuste, na seção "EXECUÇÃO", o caminho do .PWF e do CSV.
#   3. Rode este script. Ele gera "comparacao_barras.csv" e imprime no
#      terminal um ranking das barras com maiores variações.
# =========================================================================

using PWF
using PowerModels
using CSV
using DataFrames
using Printf

print("\033c")

# Pasta dedicada aos CSVs (criada automaticamente se não existir)
PASTA_CSV = normpath(joinpath(@__DIR__, "resultados_csv"))
mkpath(PASTA_CSV)
println("PASTA_CSV = ", PASTA_CSV)

# =========================================================================
# 1. LEITURA DO ESTADO ORIGINAL (ANAREDE / .PWF)
# =========================================================================
"""
    ler_estado_original(caminho_pwf) -> DataFrame

Lê o arquivo .PWF e devolve um DataFrame com o estado convergido pelo
ANAREDE: tensão, ângulo, P/Q geradas e P/Q de carga por barra.
"""
function ler_estado_original(caminho_pwf::String)
    data = PWF.parse_file(caminho_pwf)
    PowerModels.select_largest_component!(data)

    df = DataFrame(
        ID_Barra        = Int[],
        Tipo_Barra      = Int[],
        Vm_Orig_pu      = Float64[],
        Va_Orig_graus   = Float64[],
        Pg_Orig_pu      = Float64[],
        Qg_Orig_pu      = Float64[],
        Pd_Orig_pu      = Float64[],
        Qd_Orig_pu      = Float64[],
    )

    for (i_str, bus) in data["bus"]
        i = parse(Int, i_str)

        pg_orig = sum(g["pg"] for (k, g) in data["gen"] if g["gen_bus"] == i; init = 0.0)
        qg_orig = sum(g["qg"] for (k, g) in data["gen"] if g["gen_bus"] == i; init = 0.0)
        pd_orig = sum(l["pd"] for (k, l) in data["load"] if l["load_bus"] == i; init = 0.0)
        qd_orig = sum(l["qd"] for (k, l) in data["load"] if l["load_bus"] == i; init = 0.0)

        push!(df, (
            i,
            bus["bus_type"],
            bus["vm"],
            bus["va"] * (180.0 / pi),
            pg_orig,
            qg_orig,
            pd_orig,
            qd_orig,
        ))
    end

    sort!(df, :ID_Barra)
    return df
end


# =========================================================================
# 2. LEITURA DO RESULTADO DA FORMULAÇÃO (CSV)
# =========================================================================
"""
    ler_resultado_csv(caminho_csv) -> DataFrame

Lê o CSV gerado pelas formulações (9, 10, 12, 14, 16, 17, 15…). Renomeia
colunas para o padrão usado na comparação. Tolerante a CSVs que não
tenham as colunas de slack QLIM/VLIM.
"""
function ler_resultado_csv(caminho_csv::String)
    caminho_csv = normpath(caminho_csv)
    if !isfile(caminho_csv)
        error("Arquivo CSV não encontrado: $caminho_csv\n" *
              "Rode primeiro uma das formulações (9/10/12/14/15/16/17) para gerar o CSV.")
    end
    df = CSV.read(caminho_csv, DataFrame)

    # Renomeação: aceita os dois layouts mais comuns na pasta
    rename_map = Dict(
        "ID_Barra"                  => "ID_Barra",
        "Tensao_Mag_pu"             => "Vm_Otim_pu",
        "Tensao_Ang_graus"          => "Va_Otim_graus",
        "P_Geracao_pu"              => "Pg_Otim_pu",
        "Q_Geracao_pu"              => "Qg_Otim_pu",
        "Desvio_Tensao_QLIM_pu"     => "Slack_QLIM_pu",
        "Corte_Reativo_VLIM_pu"     => "Slack_VLIM_pu",
        "Injecao_Reativa_VLIM_pu"   => "Slack_VLIM_pu",
    )

    for (de, para) in rename_map
        if (de in names(df)) && (de != para)
            rename!(df, de => para)
        end
    end

    # Garante que as colunas de slack existem (caso o CSV venha do (15) ou similar)
    if !("Slack_QLIM_pu" in names(df))
        df.Slack_QLIM_pu = zeros(Float64, nrow(df))
    end
    if !("Slack_VLIM_pu" in names(df))
        df.Slack_VLIM_pu = zeros(Float64, nrow(df))
    end

    sort!(df, :ID_Barra)
    return df
end


# =========================================================================
# 3. COMPARAÇÃO E CÁLCULO DE DELTAS
# =========================================================================
"""
    comparar(df_orig, df_otim) -> DataFrame

Faz o join por ID_Barra e calcula Δ absolutos e relativos para Vm, Va,
Pg, Qg. Inclui também o módulo total `Delta_Vm_abs` para servir de chave
de ordenação no ranking.
"""
function comparar(df_orig::DataFrame, df_otim::DataFrame)
    # Remove colunas duplicadas no df_otim (mantém só ID_Barra para o join e
    # as colunas que não existem em df_orig)
    cols_otim = [c for c in names(df_otim) if c == "ID_Barra" || !(c in names(df_orig))]
    df = innerjoin(df_orig, df_otim[:, cols_otim], on = :ID_Barra)

    df.Delta_Vm_pu      = df.Vm_Otim_pu      .- df.Vm_Orig_pu
    df.Delta_Va_graus   = df.Va_Otim_graus   .- df.Va_Orig_graus
    df.Delta_Pg_pu      = df.Pg_Otim_pu      .- df.Pg_Orig_pu
    df.Delta_Qg_pu      = df.Qg_Otim_pu      .- df.Qg_Orig_pu

    # Variação relativa (%) com proteção para divisão por zero
    df.Delta_Vm_pct = [v != 0 ? 100 * d / abs(v) : 0.0
                       for (d, v) in zip(df.Delta_Vm_pu, df.Vm_Orig_pu)]
    df.Delta_Pg_pct = [v != 0 ? 100 * d / abs(v) : 0.0
                       for (d, v) in zip(df.Delta_Pg_pu, df.Pg_Orig_pu)]
    df.Delta_Qg_pct = [v != 0 ? 100 * d / abs(v) : 0.0
                       for (d, v) in zip(df.Delta_Qg_pu, df.Qg_Orig_pu)]

    df.Delta_Vm_abs = abs.(df.Delta_Vm_pu)
    df.Delta_Va_abs = abs.(df.Delta_Va_graus)
    df.Delta_Pg_abs = abs.(df.Delta_Pg_pu)
    df.Delta_Qg_abs = abs.(df.Delta_Qg_pu)

    return df
end


# =========================================================================
# 4. RELATÓRIO NO TERMINAL
# =========================================================================
function imprimir_top(df::DataFrame, coluna::Symbol, titulo::String; n::Int = 10)
    println("\n--- TOP $n BARRAS COM MAIOR ", titulo, " ---")
    df_sorted = sort(df, coluna, rev = true)
    n_real = min(n, nrow(df_sorted))

    @printf("%-8s %-6s %-14s %-14s %-14s\n",
            "Barra", "Tipo", "Original", "Otimizado", "Δ (abs)")
    println(repeat("-", 60))

    # Mapa da coluna de Δ absoluto -> par (orig, otim) para imprimir
    pares = Dict(
        :Delta_Vm_abs => (:Vm_Orig_pu,    :Vm_Otim_pu),
        :Delta_Va_abs => (:Va_Orig_graus, :Va_Otim_graus),
        :Delta_Pg_abs => (:Pg_Orig_pu,    :Pg_Otim_pu),
        :Delta_Qg_abs => (:Qg_Orig_pu,    :Qg_Otim_pu),
    )
    col_orig, col_otim = pares[coluna]

    for i in 1:n_real
        row = df_sorted[i, :]
        @printf("%-8d %-6d %-14.4f %-14.4f %-14.4f\n",
                row.ID_Barra, row.Tipo_Barra,
                row[col_orig], row[col_otim], row[coluna])
    end
end


function imprimir_resumo(df::DataFrame)
    println("\n========================================================")
    println("            RESUMO DA COMPARAÇÃO BARRA A BARRA")
    println("========================================================")
    @printf("Barras comparadas:                    %d\n", nrow(df))

    println("\n--- ESTATÍSTICAS GLOBAIS DE VARIAÇÃO ---")
    @printf("Δ Vm  máx (abs):   %.4f pu     |   média: %.4f pu\n",
            maximum(df.Delta_Vm_abs), sum(df.Delta_Vm_abs) / nrow(df))
    @printf("Δ Va  máx (abs):   %.4f graus  |   média: %.4f graus\n",
            maximum(df.Delta_Va_abs), sum(df.Delta_Va_abs) / nrow(df))
    @printf("Δ Pg  máx (abs):   %.4f pu     |   média: %.4f pu\n",
            maximum(df.Delta_Pg_abs), sum(df.Delta_Pg_abs) / nrow(df))
    @printf("Δ Qg  máx (abs):   %.4f pu     |   média: %.4f pu\n",
            maximum(df.Delta_Qg_abs), sum(df.Delta_Qg_abs) / nrow(df))

    n_qlim = count(x -> abs(x) > 1e-3, df.Slack_QLIM_pu)
    n_vlim = count(x -> abs(x) > 1e-3, df.Slack_VLIM_pu)
    println("\n--- ATUAÇÃO DE CONTROLES (slacks > 1e-3 pu) ---")
    @printf("Barras com QLIM ativo:  %d\n", n_qlim)
    @printf("Barras com VLIM ativo:  %d\n", n_vlim)

    imprimir_top(df, :Delta_Vm_abs, "VARIAÇÃO DE TENSÃO (|ΔVm|)")
    imprimir_top(df, :Delta_Va_abs, "VARIAÇÃO DE ÂNGULO (|ΔVa|)")
    imprimir_top(df, :Delta_Pg_abs, "VARIAÇÃO DE Pg (|ΔPg|)")
    imprimir_top(df, :Delta_Qg_abs, "VARIAÇÃO DE Qg (|ΔQg|)")
end


# =========================================================================
# 5. EXECUÇÃO
# =========================================================================

# Caminho do .PWF original (estado convergido pelo ANAREDE)
# Descomente o caso que corresponde à formulação que você acabou de rodar:
caminho_pwf = joinpath(@__DIR__, "..", "data_CPF", "anarede", "5busfrank_csca.pwf")  # caso (9), (16), (17)
#caminho_pwf = joinpath(@__DIR__, "01 MAXIMA NOTURNA_DEZ25.PWF")                      # caso (10), (12), (14)

# Caminho do CSV gerado por uma das suas formulações
# Ex.: "resultados_barras_SIN.csv"  (gerado pelas formulações 9/10/12/14/16/17)
#      "resultados_barras_PM.csv"   (gerado pela formulação 15)
caminho_csv = normpath(joinpath(PASTA_CSV, "resultados_barras_SIN.csv"))

# Arquivo de saída
arquivo_saida = normpath(joinpath(PASTA_CSV, "comparacao_barras.csv"))

println("caminho_csv = ", caminho_csv)
println("1. Lendo estado original do PWF ...")
df_orig = ler_estado_original(caminho_pwf)
println("   -> $(nrow(df_orig)) barras lidas.")

println("2. Lendo resultados otimizados do CSV ...")
df_otim = ler_resultado_csv(caminho_csv)
println("   -> $(nrow(df_otim)) barras lidas.")

println("3. Calculando comparação barra a barra ...")
df_cmp = comparar(df_orig, df_otim)

# Reordena colunas para uma leitura mais natural no CSV final
colunas_saida = [
    :ID_Barra, :Tipo_Barra,
    :Vm_Orig_pu,    :Vm_Otim_pu,    :Delta_Vm_pu,    :Delta_Vm_pct,
    :Va_Orig_graus, :Va_Otim_graus, :Delta_Va_graus,
    :Pg_Orig_pu,    :Pg_Otim_pu,    :Delta_Pg_pu,    :Delta_Pg_pct,
    :Qg_Orig_pu,    :Qg_Otim_pu,    :Delta_Qg_pu,    :Delta_Qg_pct,
    :Pd_Orig_pu,    :Qd_Orig_pu,
    :Slack_QLIM_pu, :Slack_VLIM_pu,
]
colunas_saida = filter(c -> string(c) in names(df_cmp), colunas_saida)

CSV.write(arquivo_saida, df_cmp[:, colunas_saida])
println("   -> Arquivo gerado: $arquivo_saida")

imprimir_resumo(df_cmp)

println("\n>> Comparação concluída com sucesso.")
