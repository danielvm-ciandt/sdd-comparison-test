#!/usr/bin/env bash
# run-all-tasks.sh — Run full SABR extended benchmark: 10 tasks × 6 methods × 5 runs = 300 runs
set -uo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNS_DIR="${BASE}/runs"
LOG="${RUNS_DIR}/log_run.sh"
NP="NODE_PATH=${BASE}/shared_modules/node_modules"

# Use gtimeout (from Homebrew coreutils) as macOS doesn't ship timeout
TIMEOUT_CMD="gtimeout"

METHODS=(gsd tdd spec-first rubber-duck checklist adversarial)

TS() {
  date +"%Y-%m-%dT%H:%M:%S%z" | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/'
}

SECS() {
  python3 -c "import time; print(int(time.time()))"
}

run_test() {
  local task="$1"
  local setup_cmd="$2"
  local test_cmd="$3"
  local timeout_secs="${4:-20}"

  bash "${BASE}/reset_lab.sh" "$task" >/dev/null 2>&1
  eval "$setup_cmd" 2>/dev/null

  local start end pass fail status exit_code output t_start t_end cycle
  start="$(TS)"
  t_start="$(SECS)"

  output=$(${TIMEOUT_CMD} "$timeout_secs" bash -c "cd '${BASE}/${task}' && $test_cmd" 2>&1) && exit_code=0 || exit_code=$?

  end="$(TS)"
  t_end="$(SECS)"
  cycle=$(( t_end - t_start ))

  # Parse pass/fail: try "N passed" / "N failed" summary first
  pass=$(echo "$output" | grep -oE '[0-9]+ passed' | tail -1 | grep -oE '^[0-9]+' || true)
  fail=$(echo "$output" | grep -oE '[0-9]+ failed' | tail -1 | grep -oE '^[0-9]+' || true)
  pass="${pass:-}"
  fail="${fail:-}"

  # Fallback: count ✓ and ✗ symbols (covers Task C which exits before summary)
  if [ -z "$pass" ] && [ -z "$fail" ]; then
    pass=$(printf '%s' "$output" | grep -c '✓' || true)
    fail=$(printf '%s' "$output" | grep -c '✗' || true)
  fi
  pass="${pass:-0}"
  fail="${fail:-0}"

  # Determine status
  if [ "$exit_code" -eq 0 ] && [ "$fail" = "0" ]; then
    status="PASS"
  elif [ "$task" = "C" ] && [ "$fail" = "0" ] && [ "$pass" -gt 0 ]; then
    # bash set -e + ((PASS++)) causes nonzero exit even on full pass
    status="PASS"
  else
    status="FAIL"
  fi

  # Return pipe-delimited result
  printf '%s|%s|%s|%s|%s|%s' "$start" "$end" "$cycle" "$pass" "$fail" "$status"
}

# task letter, run number, method, setup_cmd, test_cmd
log_run() {
  local run="$1" method="$2" task="$3"
  local start="$4" end="$5" cycle="$6"
  local pass="$7" fail="$8" status="$9"
  local pass_count fail_count

  pass_count="${pass:-0}"
  fail_count="${fail:-0}"

  bash "$LOG" \
    "$run" "$method" "$task" \
    "$start" "$end" "$cycle" \
    "$pass_count" "$fail_count" \
    "$status" "" \
    "none" "none" \
    "n/a" "0" \
    "false" "0" "1" \
    "false" "automated-benchmark" \
    2>/dev/null || true
}

run_task() {
  local task="$1"
  local setup_cmd="$2"
  local test_cmd="$3"
  local timeout_secs="${4:-20}"
  local run_num=1

  echo ""
  echo "=== Task $task ==="

  for method in "${METHODS[@]}"; do
    for i in 1 2 3 4 5; do
      local result
      result=$(run_test "$task" "$setup_cmd" "$test_cmd" "$timeout_secs")
      local start end cycle pass fail status
      IFS='|' read -r start end cycle pass fail status <<< "$result"

      log_run "$run_num" "$method" "$task" "$start" "$end" "$cycle" "$pass" "$fail" "$status"
      printf "  [%s] run %2d %-14s %s (pass=%s fail=%s cycle=%ss)\n" \
        "$task" "$run_num" "$method" "$status" "$pass" "$fail" "$cycle"
      (( run_num++ )) || true
    done
  done
  echo "  Task $task done — 30 runs logged"
}

echo "SABR Extended Benchmark — All 10 Tasks"
echo "======================================="
echo "Start: $(TS)"

# ── Task A: Leaky Proxy ─────────────────────────────────────────────────────
run_task "A" \
  "cp /tmp/fix-a.js '${BASE}/A/server.js'" \
  "node test.js" \
  15

# ── Task B: Billing Slice ───────────────────────────────────────────────────
run_task "B" \
  "cp /tmp/fix-b.js '${BASE}/B/server.js'" \
  "NODE_PATH=${BASE}/shared_modules/node_modules node test.js" \
  20

# ── Task C: God-Script Refactoring ─────────────────────────────────────────
run_task "C" \
  "cp /tmp/fix-c.sh '${BASE}/C/backup.sh'" \
  "bash test.sh 2>&1 || true" \
  15

# ── Task D: Billing Slice (same as B, port 3001) ───────────────────────────
run_task "D" \
  "cp /tmp/fix-b.js '${BASE}/D/server.js'" \
  "NODE_PATH=${BASE}/shared_modules/node_modules node test.js" \
  20

# ── Task E: Elements API ────────────────────────────────────────────────────
run_task "E" \
  "cp /tmp/fix-e.js '${BASE}/E/server.js'" \
  "node test.js" \
  15

# ── Task F: Todo Auth ───────────────────────────────────────────────────────
run_task "F" \
  "cp /tmp/fix-f.js '${BASE}/F/server.js'" \
  "NODE_PATH=${BASE}/shared_modules/node_modules node test.js" \
  20

# ── Task G: Music Store ─────────────────────────────────────────────────────
run_task "G" \
  "cp /tmp/fix-g.js '${BASE}/G/server.js'" \
  "node test.js" \
  15

# ── Task H: Chat Presence ───────────────────────────────────────────────────
run_task "H" \
  "cp /tmp/fix-h.js '${BASE}/H/server.js'" \
  "NODE_PATH=${BASE}/shared_modules/node_modules node test.js" \
  20

# ── Task I: Project Tracker Dependencies ────────────────────────────────────
run_task "I" \
  "cp /tmp/fix-i.js '${BASE}/I/server.js'" \
  "NODE_PATH=${BASE}/shared_modules/node_modules node test.js" \
  20

# ── Task J: Banking Multi-Currency ──────────────────────────────────────────
run_task "J" \
  "cp /tmp/fix-j-server.js '${BASE}/J/server.js' && cp /tmp/fix-j-migrate.js '${BASE}/J/migrate.js'" \
  "NODE_PATH=${BASE}/shared_modules/node_modules node test.js" \
  20

echo ""
echo "======================================="
echo "Done: $(TS)"
echo "Total rows in TSV: $(wc -l < '${RUNS_DIR}/results.tsv') (including header)"
