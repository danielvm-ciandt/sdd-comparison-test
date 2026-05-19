#!/usr/bin/env bash
# run-worker.sh — Execute ONE trial in a fully isolated environment.
#
# Called by run-harness.sh. Never run directly in production.
#
# Args (positional):
#   $1  RUN_ORDER    — integer position in runs_matrix.csv
#   $2  RUN_ID       — unique id, e.g. "20260519_gsd_2_E"
#   $3  METHOD       — methodology name
#   $4  TASK         — task letter (A–J)
#   $5  RUN_NUM      — run repetition number within the cell
#   $6  WORKER_PORT  — base port assigned to this worker (e.g. 3100)
#
# Env vars consumed (set by harness before fork):
#   SCRIPT_ROOT, RUNS_DIR, RESULTS_FILE  (from config.sh)
#   WORKTREE_ROOT                        (default: /tmp/sabr_runs)
#
# Exit codes:
#   0  — trial completed and logged (PASS or FAIL are recorded, not thrown)
#   1  — infrastructure error (worktree creation, reset failed)

set -euo pipefail

RUN_ORDER="${1:?missing RUN_ORDER}"
RUN_ID="${2:?missing RUN_ID}"
METHOD="${3:?missing METHOD}"
TASK="${4:?missing TASK}"
RUN_NUM="${5:?missing RUN_NUM}"
WORKER_PORT="${6:?missing WORKER_PORT}"

SCRIPT_ROOT="${SCRIPT_ROOT:?SCRIPT_ROOT must be set by harness}"
RUNS_DIR="${SCRIPT_ROOT}/runs"

# ── Per-run environment namespace ───────────────────────────────────────────
# Every directory-based resource gets its own path under /tmp/sabr_runs/$RUN_ID
# so concurrent workers never collide on /tmp, npm cache, or ports.

export WORKTREE_ROOT="${WORKTREE_ROOT:-/tmp/sabr_runs}"
RUN_SCRATCH="${WORKTREE_ROOT}/${RUN_ID}"

export TMPDIR="${RUN_SCRATCH}/.tmp"
export NPM_CONFIG_CACHE="${RUN_SCRATCH}/.npm"
export PORT="${WORKER_PORT}"            # task servers bind to $PORT; test clients read it
export TEST_PORT="${WORKER_PORT}"       # alias used by some test files

mkdir -p "$TMPDIR" "$NPM_CONFIG_CACHE"

log() { echo "[worker ${RUN_ID}]" "$@" >&2; }
log "Starting: method=${METHOD} task=${TASK} run_num=${RUN_NUM} port=${WORKER_PORT}"

# ── Cleanup trap (always runs, even on error) ────────────────────────────────
WTREE=""
cleanup() {
  local exit_code=$?
  if [ -n "$WTREE" ] && [ -d "$WTREE" ]; then
    log "Cleaning up worktree: $WTREE"
    git -C "$SCRIPT_ROOT" worktree remove -f "$WTREE" 2>/dev/null || true
    rm -rf "$WTREE" 2>/dev/null || true
  fi
  rm -rf "$RUN_SCRATCH/.tmp" "$RUN_SCRATCH/.npm" 2>/dev/null || true
  log "Done (exit=$exit_code)"
}
trap cleanup EXIT

# ── Reset: create isolated worktree ─────────────────────────────────────────
# tail -1 strips any git "HEAD is now at …" informational lines that git writes
# to stdout before the path; the path is always the final line of output.
WTREE=$(bash "${SCRIPT_ROOT}/reset_lab_v2.sh" "$TASK" "$RUN_ID" "$METHOD" | tail -1)
log "Worktree: $WTREE"

TASK_DIR="${WTREE}/${TASK}"

# Inject port into the task directory so the agent's server and test use the same port.
# We write a .env file that test.js and server.js read via process.env.PORT.
echo "PORT=${WORKER_PORT}" > "${TASK_DIR}/.env"

# ── Record start time ────────────────────────────────────────────────────────
START_ISO=$(date +"%Y-%m-%dT%H:%M:%S%z" | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/')

# ── Agent execution placeholder ─────────────────────────────────────────────
# The harness calls this script synchronously; the agent runs inside TASK_DIR.
# When hermes-agent is integrated, it will:
#   1. Read the methodology prompt
#   2. Spawn a Claude Code session pointed at TASK_DIR
#   3. Wait for the session to finish
#
# For now, emit a marker so the harness can detect a bare (no-agent) run.
log "Agent slot: ${TASK_DIR} (PORT=${WORKER_PORT})"
log "  >> hermes-agent integration point <<"

# ── Run tests ────────────────────────────────────────────────────────────────
run_tests() {
  local task="$1" dir="$2" port="$3"
  local output exit_code pass fail status

  # Determine test command per task
  local test_cmd
  case "$task" in
    A|E|G)     test_cmd="node test.js" ;;
    B|D|F|H|I|J) test_cmd="NODE_PATH=${SCRIPT_ROOT}/shared_modules/node_modules node test.js" ;;
    C)         test_cmd="bash test.sh 2>&1 || true" ;;
    *)         log "Unknown task: $task"; return 1 ;;
  esac

  output=$(
    cd "$dir"
    PORT="$port" TEST_PORT="$port" \
    eval "$test_cmd" 2>&1
  ) && exit_code=0 || exit_code=$?

  # Parse pass/fail counts
  pass=$(echo "$output" | grep -oE '[0-9]+ passed' | tail -1 | grep -oE '^[0-9]+' || true)
  fail=$(echo "$output" | grep -oE '[0-9]+ failed' | tail -1 | grep -oE '^[0-9]+' || true)

  if [ -z "$pass" ] && [ -z "$fail" ]; then
    pass=$(printf '%s' "$output" | grep -c '✓' || true)
    fail=$(printf '%s' "$output" | grep -c '✗' || true)
  fi
  pass="${pass:-0}"
  fail="${fail:-0}"

  if [ "$exit_code" -eq 0 ] && [ "$fail" = "0" ]; then
    status="PASS"
  elif [ "$task" = "C" ] && [ "$fail" = "0" ] && [ "$pass" -gt 0 ]; then
    status="PASS"
  else
    status="FAIL"
  fi

  echo "${pass}|${fail}|${status}"
}

TEST_RESULT=$(run_tests "$TASK" "$TASK_DIR" "$WORKER_PORT")
PASS=$(echo "$TEST_RESULT" | cut -d'|' -f1)
FAIL=$(echo "$TEST_RESULT" | cut -d'|' -f2)
STATUS=$(echo "$TEST_RESULT" | cut -d'|' -f3)

log "Tests: $STATUS (pass=$PASS fail=$FAIL)"

# ── Record end time ──────────────────────────────────────────────────────────
END_ISO=$(date +"%Y-%m-%dT%H:%M:%S%z" | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/')

# ── Log the run ──────────────────────────────────────────────────────────────
bash "${RUNS_DIR}/log_run.sh" \
  "$RUN_NUM" "$METHOD" "$TASK" "$RUN_ID" \
  "$START_ISO" "$END_ISO" \
  "$PASS" "$FAIL" "$STATUS" \
  "—" "0" "0" "0" \
  "0" "0" "0" "0" "0" \
  "automated-parallel-worker"

log "Logged to results.tsv"
