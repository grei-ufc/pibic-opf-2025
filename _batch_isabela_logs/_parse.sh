#!/usr/bin/env bash
# Parser robusto: extrai (status, t_solver, t_wall, objective, Vmin, Vmax, Pg, Qg, Perdas, base, rc)
# de cada log e gera TSV consolidado.

LOGS="/Users/gabrielrufinomontenegro/pibic-opf-2025/_batch_isabela_logs"
OUT="$LOGS/_summary.tsv"

printf "n\tcaso\tstatus\tt_solver_s\tt_wall_s\tobjective\tVmin_pu\tVmax_pu\tPg_pu\tQg_pu\tPerdas_pu\trc\n" > "$OUT"

for case in caso_red caso_red2; do
  for n in 14 15 16 17 18 19; do
    f="$LOGS/${n}_${case}.log"
    [ ! -f "$f" ] && continue

    status=$(grep "Status da Convergência:" "$f" | head -1 | sed -E 's/.*Status da Convergência:[ \t]*//')
    [ -z "$status" ] && status="NO_RESULT"

    ts=$(grep "Tempo interno do Solver" "$f" | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    obj=$(grep "Erro de Controle" "$f" | head -1 | awk -F': ' '{print $2}')
    vmin=$(grep "Tensão Mínima (pu):" "$f" | head -1 | awk '{print $NF}')
    vmax=$(grep "Tensão Máxima (pu):" "$f" | head -1 | awk '{print $NF}')
    pg=$(grep "Geração Ativa Total (pu):" "$f" | head -1 | awk '{print $NF}')
    qg=$(grep "Geração Reativa Total (pu):" "$f" | head -1 | awk '{print $NF}')
    pe=$(grep "Perdas Ativas (Total pu):" "$f" | head -1 | awk '{print $NF}')
    rc=$(grep '^EXIT_CODE=' "$f" | head -1 | sed 's/^EXIT_CODE=//')
    # wall: overview log — bloco entre "=== n=N caso=C.pwf" e a próxima linha "-> rc=...".
    wall=$(grep -A1 -E "^=== n=${n}[[:space:]]+caso=${case}\\.pwf" "$LOGS/_overview.log" \
      | grep -oE 'dur=[0-9]+s' | head -1 | sed -E 's/dur=([0-9]+)s/\1/')

    for v in status ts obj vmin vmax pg qg pe rc wall; do
      eval "[ -z \"\${$v}\" ] && $v='-'"
    done

    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
      "$n" "$case" "$status" "$ts" "$wall" "$obj" "$vmin" "$vmax" "$pg" "$qg" "$pe" "$rc" >> "$OUT"
  done
done

echo "=== summary.tsv ==="
column -t -s $'\t' "$OUT"
