#!/usr/bin/env bash
# Runner para o batch de validação dos casos da Isabela (caso_red, caso_red2)
# nas formulações (14)-(19). Patcha um tmp de cada script para apontar para o
# .pwf alvo, roda em Julia, e move CSVs para resultados_csv/<n>/<caso>/.

set -u

REPO="/Users/gabrielrufinomontenegro/pibic-opf-2025"
PF="$REPO/powerflow/Codes/PF_Formulation"
LOGS="$REPO/_batch_isabela_logs"
RES="$PF/resultados_csv"

mkdir -p "$LOGS"

# (n) -> nome do script
get_script() {
  case "$1" in
    14) echo "(14)OPF_PM.jl" ;;
    15) echo "(15)PF_PM.jl.jl" ;;
    16) echo "(16)QLIM+VLIM.jl" ;;
    17) echo "(17)QLIM+VLIM+CSCA.jl" ;;
    18) echo "(18)QLIM+VLIM+CSCA+CTAP.jl" ;;
    19) echo "(19)+DERA.jl" ;;
  esac
}

# (n) -> nome do CSV de barras gerado (caminho relativo a $PF)
get_barras_csv() {
  case "$1" in
    14|15) echo "resultados_barras_PM.csv" ;;
    17|18|19) echo "resultados_csv/resultados_barras_SIN.csv" ;;
    16) echo "" ;;
  esac
}

# (n) -> nome do CSV de fluxos
get_linhas_csv() {
  case "$1" in
    14|15) echo "resultados_fluxos_linhas_PM.csv" ;;
    17|18|19) echo "resultados_csv/resultados_fluxos_linhas_SIN.csv" ;;
    16) echo "" ;;
  esac
}

CASES=("caso_red.pwf" "caso_red2.pwf")
FORMS=(14 15 16 17 18 19)
TIMEOUT_SEC=1500   # 25 min por rodada

START_TS=$(date +%s)
echo "BATCH START $(date)" > "$LOGS/_overview.log"

cd "$PF"

for case_pwf in "${CASES[@]}"; do
  case_tag="${case_pwf%.pwf}"
  case_tag="${case_tag%.PWF}"

  for n in "${FORMS[@]}"; do
    script=$(get_script "$n")
    barras_src=$(get_barras_csv "$n")
    linhas_src=$(get_linhas_csv "$n")

    tmpscript="$LOGS/_${n}_${case_tag}.jl"
    logfile="$LOGS/${n}_${case_tag}.log"
    outdir="$RES/${n}/${case_tag}"
    mkdir -p "$outdir"

    echo "=== n=$n  caso=$case_pwf  start=$(date '+%H:%M:%S') ===" | tee -a "$LOGS/_overview.log"

    # Patch input: troca o joinpath(..., "data", "<qualquer>.pwf") por caminho ABSOLUTO.
    # (caminho absoluto porque @__DIR__ no tmpscript aponta para LOGS, não para PF.)
    abs_pwf="$REPO/powerflow/Codes/data/${case_pwf}"
    abs_pasta="$PF/resultados_csv"
    sed -E \
      -e "s|joinpath\(@__DIR__,[[:space:]]*\"\.\.\",[[:space:]]*\"data\",[[:space:]]*\"[^\"]+\"\)|\"${abs_pwf}\"|" \
      -e "s|joinpath\(@__DIR__,[[:space:]]*\"resultados_csv\"\)|\"${abs_pasta}\"|" \
      "$PF/$script" > "$tmpscript"

    # Roda
    {
      echo "--- patched script (head) ---"
      grep -nE "^(arquivo|caminho_arquivo)[[:space:]]*=" "$tmpscript" || true
      echo "--- begin julia output ---"
    } > "$logfile"

    t0=$(date +%s)
    /usr/bin/env julia --project="$REPO" "$tmpscript" >> "$logfile" 2>&1
    rc=$?
    t1=$(date +%s)
    dur=$((t1 - t0))

    {
      echo "--- end julia output ---"
      echo "EXIT_CODE=$rc"
      echo "WALL_SECONDS=$dur"
    } >> "$logfile"

    # Move CSVs
    if [ -n "$barras_src" ] && [ -f "$PF/$barras_src" ]; then
      mv "$PF/$barras_src" "$outdir/$(basename "$barras_src")"
    fi
    if [ -n "$linhas_src" ] && [ -f "$PF/$linhas_src" ]; then
      mv "$PF/$linhas_src" "$outdir/$(basename "$linhas_src")"
    fi
    cp "$logfile" "$outdir/run.log"

    echo "    -> rc=$rc dur=${dur}s outdir=$outdir" | tee -a "$LOGS/_overview.log"
    rm -f "$tmpscript"
  done
done

END_TS=$(date +%s)
TOTAL=$((END_TS - START_TS))
echo "BATCH END $(date)  total=${TOTAL}s" | tee -a "$LOGS/_overview.log"
