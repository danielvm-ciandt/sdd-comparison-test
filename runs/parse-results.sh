#!/usr/bin/env bash
# parse-results.sh — Aggregate results.tsv and compute lean metrics.
#
# TSV columns (1-indexed):
#   1  run_number          2  methodology         3  task
#   4  start_time          5  end_time            6  cycle_time_sec
#   7  assertions_pass     8  assertions_fail     9  status
#   10 error_type          11 spec_quality        12 artifacts_produced
#   13 tokens_used         14 first_code_sec      15 spec_precedes_code
#   16 rework_count        17 files_touched       18 contradiction_found
#   19 notes

set -euo pipefail

RESULTS_FILE="${1:-$(dirname "$0")/results.tsv}"

if [ ! -f "$RESULTS_FILE" ]; then
  echo "ERROR: Results file not found: $RESULTS_FILE" >&2
  exit 1
fi

total_runs=$(awk 'NR>1 && NF>1' "$RESULTS_FILE" | wc -l | tr -d ' ')

if [ "$total_runs" -eq 0 ]; then
  echo "No data rows yet."
  exit 0
fi

# percentile <col> <filter_col> <filter_val> <pct>
percentile() {
  local col="$1" fcol="$2" fval="$3" pct="$4"
  awk -F'\t' -v c="$col" -v fc="$fcol" -v fv="$fval" \
    'NR>1 && $fc==fv { print $c+0 }' "$RESULTS_FILE" \
  | sort -n \
  | awk -v p="$pct" '
      { lines[NR]=$1 }
      END {
        if (NR==0) { print "—"; exit }
        idx=int(NR*p/100+0.5)
        if(idx<1) idx=1; if(idx>NR) idx=NR
        print lines[idx]
      }'
}

echo "============================================================"
echo " SABR Room 3 — Results & Lean Metrics"
echo "============================================================"
echo ""
echo "Total runs logged: $total_runs"
echo ""

# ── By Methodology ────────────────────────────────────────────────────────
echo "=== By Methodology ==="
printf "%-15s %5s %6s  %8s  %8s  %8s  %9s  %7s  %9s  %9s  %7s  %7s  %7s\n" \
  "Method" "Runs" "Pass%" \
  "AvgCycle" "P50Cycle" "P95Cycle" \
  "Thruput/h" "AvgTok" \
  "AvgSpec1stC" "SpecBefore%" "AvgRewrk" "AvgFiles" "Contra%"

for method in bigpowers superpowers bmad spec-kit acps gsd; do
  stats=$(awk -F'\t' -v m="$method" '
  NR==1 { next }
  $2==m {
    n++
    if ($9=="PASS") pass++
    sum_cycle  += $6+0
    sum_tok    += $13+0
    sum_fcs    += $14+0
    sum_sbc    += $15+0
    sum_rework += $16+0
    sum_files  += $17+0
    sum_contra += $18+0
  }
  END {
    if (n==0) exit
    printf "%d %.1f %.0f %.0f %.1f %.2f %.2f %.2f %.1f",
      n, pass*100/n, sum_cycle/n, sum_tok/n, sum_fcs/n,
      sum_sbc*100/n, sum_rework/n, sum_files/n, sum_contra*100/n
  }' "$RESULTS_FILE")
  [ -z "$stats" ] && continue

  read -r runs pass_pct avg_cycle avg_tok avg_fcs sbc_pct avg_rework avg_files contra_pct <<< "$stats"
  throughput=$(awk "BEGIN{printf \"%.1f\", ($avg_cycle>0)?3600/$avg_cycle:0}")
  p50=$(percentile 6 2 "$method" 50)
  p95=$(percentile 6 2 "$method" 95)

  printf "%-15s %5s %5s%%  %7ss  %7ss  %7ss  %8s/h  %7s  %10ss  %8s%%  %8s  %8s  %6s%%\n" \
    "$method" "$runs" "$pass_pct" \
    "$avg_cycle" "$p50" "$p95" \
    "$throughput" "$avg_tok" \
    "$avg_fcs" "$sbc_pct" "$avg_rework" "$avg_files" "$contra_pct"
done

echo ""

# ── By Task ───────────────────────────────────────────────────────────────
echo "=== By Task ==="
printf "%-6s %5s %6s  %8s  %8s  %6s  %8s  %9s  %7s\n" \
  "Task" "Runs" "Pass%" "AvgCycle" "P95Cycle" "AvgArt" "AvgTok" "AvgFCS" "Contra%"

for task in A B C D E F G H I J; do
  stats=$(awk -F'\t' -v t="$task" '
  NR==1 { next }
  $3==t {
    n++
    if ($9=="PASS") pass++
    sum_cycle  += $6+0
    sum_art    += $12+0
    sum_tok    += $13+0
    sum_fcs    += $14+0
    sum_contra += $18+0
  }
  END {
    if (n==0) exit
    printf "%d %.1f %.0f %.1f %.0f %.1f %.1f",
      n, pass*100/n, sum_cycle/n, sum_art/n, sum_tok/n, sum_fcs/n, sum_contra*100/n
  }' "$RESULTS_FILE")
  [ -z "$stats" ] && continue

  read -r runs pass_pct avg_cycle avg_art avg_tok avg_fcs contra_pct <<< "$stats"
  p95=$(percentile 6 3 "$task" 95)

  printf "%-6s %5s %5s%%  %7ss  %7ss  %6s  %8s  %8ss  %6s%%\n" \
    "$task" "$runs" "$pass_pct" "$avg_cycle" "$p95" "$avg_art" "$avg_tok" "$avg_fcs" "$contra_pct"
done

echo ""

# ── Spec Quality Distribution ─────────────────────────────────────────────
echo "=== Spec Quality Distribution ==="
for sq in 0 1 2; do
  label="none"; [ "$sq" -eq 1 ] && label="partial"; [ "$sq" -eq 2 ] && label="complete"
  count=$(awk -F'\t' -v s="$sq" 'NR>1 && $11==s {c++} END {print c+0}' "$RESULTS_FILE")
  printf "  spec_quality=%s (%s): %d runs\n" "$sq" "$label" "$count"
done

echo ""

# ── Observability Signal Summary ──────────────────────────────────────────
echo "=== Observability Signal Summary ==="
awk -F'\t' '
NR==1 { next }
NF>1 {
  n++
  sum_cycle  += $6+0
  sum_tok    += $13+0
  sum_fcs    += $14+0
  sum_sbc    += $15+0
  sum_rework += $16+0
  sum_files  += $17+0
  sum_contra += $18+0
  if ($9=="PASS") pass++
  if ($6+0 > max_cycle+0 || max_cycle=="") {
    max_cycle=$6; mc_run=$1; mc_method=$2; mc_task=$3
  }
  if (min_cycle=="" || $6+0 < min_cycle+0) {
    min_cycle=$6; mn_run=$1; mn_method=$2; mn_task=$3
  }
  if ($13+0 > max_tok+0 || max_tok=="") {
    max_tok=$13; mt_run=$1; mt_method=$2; mt_task=$3
  }
}
END {
  if (n==0) exit
  avg_c = sum_cycle/n
  printf "  Total runs:           %d\n", n
  printf "  Pass rate:            %.1f%%\n", pass*100/n
  printf "  Avg cycle:            %.0fs (%.1f min)\n", avg_c, avg_c/60
  printf "  Min cycle:            %ss  (Run %s | %s | Task %s)\n", min_cycle, mn_run, mn_method, mn_task
  printf "  Max cycle:            %ss  (Run %s | %s | Task %s)\n", max_cycle, mc_run, mc_method, mc_task
  printf "  Throughput:           %.1f runs/hour\n", (avg_c>0)?3600/avg_c:0
  printf "  Total tokens:         %.0f\n", sum_tok
  printf "  Avg tokens/run:       %.0f\n", sum_tok/n
  printf "  Max tokens/run:       %s  (Run %s | %s | Task %s)\n", max_tok, mt_run, mt_method, mt_task
  printf "  Avg first_code_sec:   %.0fs  (planning tax before first edit)\n", sum_fcs/n
  printf "  Spec-before-code %%:   %.1f%%  (method wrote spec before any code)\n", sum_sbc*100/n
  printf "  Avg rework_count:     %.2f  (edits to already-written files)\n", sum_rework/n
  printf "  Avg files_touched:    %.1f\n", sum_files/n
  printf "  Contradiction found%%: %.1f%%  (agent caught spec ambiguity before coding)\n", sum_contra*100/n
}
' "$RESULTS_FILE"

echo ""

# ── Error Types ───────────────────────────────────────────────────────────
echo "=== Error Types ==="
errors=$(awk -F'\t' 'NR>1 && $9=="ERROR" {e[$10]++} END {for(k in e) printf "  %-20s %d\n",k,e[k]}' "$RESULTS_FILE")
[ -n "$errors" ] && echo "$errors" || echo "  none"

echo ""
echo "=== Error Rows ==="
awk -F'\t' 'NR==1 || ($9=="ERROR" && NF>1) {print}' "$RESULTS_FILE" || true
