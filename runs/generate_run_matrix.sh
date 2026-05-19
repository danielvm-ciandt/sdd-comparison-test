#!/usr/bin/env bash
# generate_run_matrix.sh — Generate randomized run matrix for SABR Room 3 v2.
#
# This script:
#  1. Reads config.sh for experiment parameters
#  2. Generates a list of all (method, task, run_num) tuples
#  3. Randomizes the execution order
#  4. Outputs runs_matrix.csv with columns: run_order, run_id, method, task, run_num, seed
#  5. Stores the random seed for reproducibility
#
# Usage:
#   bash runs/generate_run_matrix.sh [--seed <SEED>]
#
# Output:
#   runs/runs_matrix.csv         (randomized execution plan)
#   runs/runs_matrix_seed.txt    (random seed for reproducibility)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source config
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/runs/config.sh"

log() {
  echo "[generate_run_matrix]" "$@" >&2
}

# ──────────────────────────────────────────────────────────────────────────────
# Parse arguments
# ──────────────────────────────────────────────────────────────────────────────

CUSTOM_SEED=""
if [ "$#" -ge 2 ] && [ "$1" = "--seed" ]; then
  CUSTOM_SEED="$2"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Validate config
# ──────────────────────────────────────────────────────────────────────────────

if ! validate_config; then
  exit 1
fi

log "Generating run matrix..."
log "  Methods: $METHODOLOGIES"
log "  Tasks: A B C D E F G H I J"
log "  Runs per cell: $N_RUNS_PER_CELL"
log "  Total budget: $BUDGET_TOTAL"

# ──────────────────────────────────────────────────────────────────────────────
# Generate random seed
# ──────────────────────────────────────────────────────────────────────────────

if [ -n "$CUSTOM_SEED" ]; then
  SEED="$CUSTOM_SEED"
else
  # Generate a random seed from current time + entropy
  SEED=$(date +%s%N | sha256sum | cut -c1-16)
fi

log "Random seed: $SEED"
echo "$SEED" > "$MATRIX_SEED_FILE"

# ──────────────────────────────────────────────────────────────────────────────
# Generate tuples and randomize
# ──────────────────────────────────────────────────────────────────────────────

# Temporary file for unsorted tuples
temp_tuples=$(mktemp)
trap "rm -f $temp_tuples" EXIT

# Build the Cartesian product: method × task × run_number
read -ra methods_array <<< "$METHODOLOGIES"
tasks_array=(A B C D E F G H I J)

run_order=1
for method in "${methods_array[@]}"; do
  for task in "${tasks_array[@]}"; do
    for run_num in $(seq 1 "$N_RUNS_PER_CELL"); do
      # Generate a unique run_id: TIMESTAMP_METHOD_RUN_TASK
      run_id="$(date +%Y%m%d)_${method}_${run_num}_${task}"
      echo "$run_order:$run_id:$method:$task:$run_num" >> "$temp_tuples"
      run_order=$((run_order + 1))
    done
  done
done

# Randomize using awk + sort with the seeded hash
# We'll use a simple approach: sort by a hash of (seed + line) to pseudorandomize
# This is reproducible given the same seed
{
  cat "$temp_tuples" | awk -v seed="$SEED" '
    BEGIN {
      # Simple seeded pseudorandom: hash = (seed * 1103515245 + 12345) mod 2^31
      # We iterate this hash for each line
      state = seed % 2147483647
    }
    {
      # LCG: state = (state * 1103515245 + 12345) % 2147483647
      state = (state * 1103515245 + 12345) % 2147483647
      hash = state % 1000000
      print hash "\t" $0
    }
  ' | sort -n -k1 | cut -f2-
} > "$temp_tuples.sorted"

# ──────────────────────────────────────────────────────────────────────────────
# Write CSV header and randomized rows
# ──────────────────────────────────────────────────────────────────────────────

{
  echo "run_order,run_id,method,task,run_num,seed"
  new_order=1
  while IFS=: read -r old_order run_id method task run_num; do
    echo "$new_order,$run_id,$method,$task,$run_num,$SEED"
    new_order=$((new_order + 1))
  done < "$temp_tuples.sorted"
} > "$RUNS_MATRIX_FILE"

log "Run matrix written: $RUNS_MATRIX_FILE"
log "Total rows: $(( $(wc -l < "$RUNS_MATRIX_FILE") - 1 )) runs"

# ──────────────────────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────────────────────

log "Seed stored: $MATRIX_SEED_FILE"
log ""
log "To reproduce this matrix: bash runs/generate_run_matrix.sh --seed $SEED"
log ""
log "First 5 runs in execution order:"
head -6 "$RUNS_MATRIX_FILE" | tail -5 | sed 's/^/  /'
