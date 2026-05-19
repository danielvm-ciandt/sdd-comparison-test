#!/usr/bin/env bash
# run-harness.sh — Parallel experiment harness.
#
# Reads runs/runs_matrix.csv and executes each trial via run-worker.sh.
# Up to MAX_PARALLEL workers run concurrently; each gets an isolated env.
#
# Usage:
#   bash runs/run-harness.sh [--dry-run] [--from ROW] [--to ROW] [--parallel N]
#
# Options:
#   --dry-run       Print what would run but don't execute workers
#   --from ROW      Start at this run_order (1-based, inclusive)
#   --to ROW        Stop at this run_order (inclusive)
#   --parallel N    Override MAX_PARALLEL from config.sh
#
# Requirements:
#   - runs/config.sh sourced (auto-sourced here)
#   - runs/runs_matrix.csv exists (run generate_run_matrix.sh first)
#   - runs/prebuild-cache.sh has been run at least once
#
# Output:
#   - runs/results.tsv  (appended per trial via log_run.sh)
#   - runs/harness.log  (per-worker stderr captured here)

set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNS_DIR="${SCRIPT_ROOT}/runs"
export SCRIPT_ROOT

# Source config
# shellcheck source=/dev/null
source "${RUNS_DIR}/config.sh"

# ── Argument parsing ─────────────────────────────────────────────────────────
DRY_RUN=false
FROM_ROW=1
TO_ROW=999999
PARALLEL_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=true; shift ;;
    --from)       FROM_ROW="$2"; shift 2 ;;
    --to)         TO_ROW="$2"; shift 2 ;;
    --parallel)   PARALLEL_OVERRIDE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

MAX_WORKERS="${PARALLEL_OVERRIDE:-${MAX_PARALLEL:-4}}"
MATRIX_FILE="${RUNS_MATRIX_FILE}"
HARNESS_LOG="${RUNS_DIR}/harness.log"

# ── Preflight checks ─────────────────────────────────────────────────────────
if [ ! -f "$MATRIX_FILE" ]; then
  echo "ERROR: runs_matrix.csv not found. Run: bash runs/generate_run_matrix.sh" >&2
  exit 1
fi

if [ ! -f "${RUNS_DIR}/results.tsv" ]; then
  echo "ERROR: results.tsv not found. Expected a header-only file." >&2
  exit 1
fi

# Warn if SANDBOX node_modules are missing (only for tasks with actual dependencies)
missing_modules=0
for task in A B C D E F G H I J; do
  pkgjson="${SCRIPT_ROOT}/SANDBOX/${task}/package.json"
  nm="${SCRIPT_ROOT}/SANDBOX/${task}/node_modules"
  if [ -f "$pkgjson" ] && [ ! -d "$nm" ]; then
    # Check if there are actual dependencies; skip tasks with empty deps
    has_deps=$(python3 -c "
import json, sys
try:
  pkg=json.load(open('$pkgjson'))
  deps={**pkg.get('dependencies',{}),**pkg.get('devDependencies',{})}
  print('yes' if deps else 'no')
except: print('no')
" 2>/dev/null || echo "no")
    if [ "$has_deps" = "yes" ]; then
      echo "WARNING: SANDBOX/${task}/node_modules missing. Run: bash runs/prebuild-cache.sh" >&2
      missing_modules=$(( missing_modules + 1 ))
    fi
  fi
done
if [ "$missing_modules" -gt 0 ]; then
  echo "ERROR: $missing_modules task(s) missing node_modules. Run prebuild-cache.sh first." >&2
  exit 1
fi

echo "==========================================="
echo "SABR Parallel Harness"
echo "  Matrix:     $MATRIX_FILE"
echo "  Workers:    $MAX_WORKERS concurrent"
echo "  Row range:  $FROM_ROW – $TO_ROW"
echo "  Dry run:    $DRY_RUN"
echo "  Log:        $HARNESS_LOG"
echo "==========================================="

# ── Port assignment ──────────────────────────────────────────────────────────
# Worker slot 0 → port 3100, slot 1 → port 3200, ..., slot N-1 → port 3100+(N*100)
# Each slot is reserved for its worker; no two concurrent workers share a port range.
# Tasks that don't start servers ignore $PORT, so the reservation is safe.
get_port() {
  local slot="$1"
  echo $(( 3100 + slot * 100 ))
}

# ── Worker slot tracking ─────────────────────────────────────────────────────
declare -a WORKER_PIDS
declare -a WORKER_RIDS

for (( s=0; s<MAX_WORKERS; s++ )); do
  WORKER_PIDS[$s]=0
  WORKER_RIDS[$s]=""
done

wait_for_free_slot() {
  while true; do
    for (( s=0; s<MAX_WORKERS; s++ )); do
      local pid="${WORKER_PIDS[$s]}"
      if [ "$pid" -eq 0 ]; then
        echo "$s"; return
      fi
      if ! kill -0 "$pid" 2>/dev/null; then
        wait "$pid" 2>/dev/null || true
        WORKER_PIDS[$s]=0
        WORKER_RIDS[$s]=""
        echo "$s"; return
      fi
    done
    sleep 1
  done
}

wait_all() {
  for (( s=0; s<MAX_WORKERS; s++ )); do
    local pid="${WORKER_PIDS[$s]}"
    if [ "$pid" -ne 0 ]; then
      wait "$pid" 2>/dev/null || true
      WORKER_PIDS[$s]=0
    fi
  done
}

# ── Main dispatch loop ───────────────────────────────────────────────────────
dispatched=0

# Skip CSV header (line 1)
while IFS=, read -r run_order run_id method task run_num seed; do
  # Trim whitespace
  run_order="${run_order// /}"
  run_id="${run_id// /}"

  # Row filter
  if [ "$run_order" -lt "$FROM_ROW" ] || [ "$run_order" -gt "$TO_ROW" ]; then
    continue
  fi

  if [ "$DRY_RUN" = "true" ]; then
    echo "  [DRY] run_order=$run_order run_id=$run_id method=$method task=$task"
    continue
  fi

  # Acquire a free worker slot
  slot=$(wait_for_free_slot)
  port=$(get_port "$slot")

  echo "--> Dispatching run_order=$run_order | $method/$task | slot=$slot port=$port | run_id=$run_id"

  # Spawn worker in background; capture its stderr to harness.log
  bash "${RUNS_DIR}/run-worker.sh" \
    "$run_order" "$run_id" "$method" "$task" "$run_num" "$port" \
    >> "$HARNESS_LOG" 2>&1 &

  WORKER_PIDS[$slot]=$!
  WORKER_RIDS[$slot]="$run_id"
  dispatched=$(( dispatched + 1 ))
done < <(tail -n +2 "$MATRIX_FILE")

# Wait for all remaining workers
wait_all

echo "==========================================="
echo "Harness complete."
echo "  Dispatched: $dispatched"
echo "  Results:    $RESULTS_FILE"
echo "  Log:        $HARNESS_LOG"
echo "==========================================="
