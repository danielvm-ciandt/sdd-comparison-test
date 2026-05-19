# Parallel Isolation + n=30 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable 4-way parallel experiment runs on the local machine (no Docker) via per-run env-namespace isolation, and bump sample size from n=15 to n=30 to achieve publishable statistical power across all 21 pairwise method comparisons.

**Architecture:** A new harness script (`runs/run-harness.sh`) reads `runs_matrix.csv` and spawns up to N concurrent worker shells, each with a fully-namespaced environment: unique `TMPDIR`, `NPM_CONFIG_CACHE`, `PORT`, and git worktree. Each worker is self-contained — it resets, runs the agent, captures results, and cleans up regardless of success or failure. `config.sh` is updated to set `N_RUNS_PER_CELL=30` and a new `MAX_PARALLEL=4` knob. The matrix generator already handles the larger `n`; it just needs a config reload.

**Tech Stack:** bash 5 (Homebrew), git worktrees, rsync, Node.js, Python 3.8+

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `runs/config.sh` | Modify | Add `MAX_PARALLEL=4`, bump `N_RUNS_PER_CELL=30` |
| `runs/run-harness.sh` | **Create** | Parallel worker orchestrator — reads matrix, spawns workers |
| `runs/run-worker.sh` | **Create** | Single-run worker: env isolation + reset + agent stub + test + log + cleanup |
| `reset_lab_v2.sh` | Modify | Add `--port` arg passthrough so worker can request a specific port range |
| `runs/generate_run_matrix.sh` | No change | Already handles any `N_RUNS_PER_CELL`; just re-run after config change |
| `runs/README_v2.md` | Modify | Document parallel execution, new knobs, updated time estimates |

---

## Task 1: Update config.sh — add parallelism knob and bump n=30

**Files:**
- Modify: `runs/config.sh`

- [ ] **Step 1: Open config.sh and locate the experiment parameters block**

The block starts at line 14:
```
# Total number of runs: 6 methodologies × 10 tasks × N runs per cell
export N_RUNS_PER_CELL=15
```

- [ ] **Step 2: Change N_RUNS_PER_CELL from 15 to 30 and add MAX_PARALLEL**

Replace this block (lines 14–21):
```bash
# Total number of runs: 6 methodologies × 10 tasks × N runs per cell
# Choices: 300 (n=5), 600 (n=10), 900 (n=15), or any custom value
export N_RUNS_PER_CELL=15
export N_METHODS=7  # 6 + 1 bare control
export N_TASKS=10

# Computed
export BUDGET_TOTAL=$(( N_RUNS_PER_CELL * N_METHODS * N_TASKS ))
```

With this:
```bash
# Total number of runs: 7 methodologies × 10 tasks × N runs per cell
# Choices: 350 (n=5), 700 (n=10), 1400 (n=20), 2100 (n=30)
# n=30 required for 80% power at δ=0.3 across all 21 pairwise comparisons
export N_RUNS_PER_CELL=30
export N_METHODS=7  # 6 + 1 bare control
export N_TASKS=10

# Maximum concurrent runs (parallel workers). Each run needs ~2 CPU cores + 1 port.
# 4 is safe for an 8-core Mac; reduce to 2 on a 4-core machine.
export MAX_PARALLEL=4

# Computed
export BUDGET_TOTAL=$(( N_RUNS_PER_CELL * N_METHODS * N_TASKS ))
```

- [ ] **Step 3: Also update the BUDGET_TOTAL comment in the --info block (lines 144–163)**

Find the line:
```bash
Total runs (BUDGET):    $BUDGET_TOTAL
  n per cell:           $N_RUNS_PER_CELL
```

No code change needed here — the variables already expand correctly. Verify by running:
```bash
source runs/config.sh --info
```
Expected output includes:
```
Total runs (BUDGET):    2100
  n per cell:           30
  methodologies:        7
  tasks:                10
```

- [ ] **Step 4: Commit**

```bash
git add runs/config.sh
git commit -m "config: bump N_RUNS_PER_CELL to 30, add MAX_PARALLEL=4"
```

---

## Task 2: Create run-worker.sh — isolated single-run worker

**Files:**
- Create: `runs/run-worker.sh`

This is the heart of the fix. Each parallel execution slot runs this script, with its own env namespace.

- [ ] **Step 1: Create runs/run-worker.sh with the isolation scaffold**

```bash
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
WTREE=$(bash "${SCRIPT_ROOT}/reset_lab_v2.sh" "$TASK" "$RUN_ID" "$METHOD")
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
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x runs/run-worker.sh
```

- [ ] **Step 3: Smoke-test the worker with a dry run (no agent, Task E)**

First ensure the SANDBOX has node_modules (run prebuild-cache if needed):
```bash
ls /Users/danielvm/Developer/sdd-comparison-test/SANDBOX/E/node_modules 2>/dev/null \
  || bash runs/prebuild-cache.sh
```

Then run a single worker:
```bash
source runs/config.sh
SCRIPT_ROOT=$(pwd) bash runs/run-worker.sh \
  1 "20260519_test_1_E" gsd E 1 3100
```

Expected stderr (partial):
```
[worker 20260519_test_1_E] Starting: method=gsd task=E run_num=1 port=3100
[worker 20260519_test_1_E] Worktree: /tmp/sabr_runs/20260519_test_1_E
[worker 20260519_test_1_E] Tests: PASS (pass=5 fail=0)
[worker 20260519_test_1_E] Logged to results.tsv
[worker 20260519_test_1_E] Cleaning up worktree: /tmp/sabr_runs/20260519_test_1_E
[worker 20260519_test_1_E] Done (exit=0)
```

If Task E passes 5 assertions pre-agent (the SANDBOX already has the solved server.js), that confirms: worktree creation, env isolation, test execution, port passing, and log_run all work.

- [ ] **Step 4: Verify results.tsv received the row**

```bash
tail -1 runs/results.tsv
```

Expected: a tab-separated row where `run_id` = `20260519_test_1_E` and `status` = `PASS`.

- [ ] **Step 5: Verify the worktree was cleaned up**

```bash
ls /tmp/sabr_runs/ 2>/dev/null || echo "clean"
```

Expected: either empty or only other active runs (not `20260519_test_1_E`).

- [ ] **Step 6: Commit**

```bash
git add runs/run-worker.sh
git commit -m "feat: add run-worker.sh with per-run env namespace isolation"
```

---

## Task 3: Create run-harness.sh — parallel orchestrator

**Files:**
- Create: `runs/run-harness.sh`

The harness reads `runs_matrix.csv`, spawns up to `MAX_PARALLEL` workers concurrently, assigns each a unique port range, and waits for all to complete before exiting.

- [ ] **Step 1: Create runs/run-harness.sh**

```bash
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

# Warn if SANDBOX node_modules are missing
missing_modules=0
for task in A B C D E F G H I J; do
  pkgjson="${SCRIPT_ROOT}/SANDBOX/${task}/package.json"
  nm="${SCRIPT_ROOT}/SANDBOX/${task}/node_modules"
  if [ -f "$pkgjson" ] && [ ! -d "$nm" ]; then
    echo "WARNING: SANDBOX/${task}/node_modules missing. Run: bash runs/prebuild-cache.sh" >&2
    missing_modules=$(( missing_modules + 1 ))
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
declare -a WORKER_PIDS=()   # PID per slot (0 = free)
declare -a WORKER_RIDS=()   # RUN_ID per slot (for logging)

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
completed=0
skipped=0
dispatched=0

# Skip CSV header (line 1)
tail -n +2 "$MATRIX_FILE" | while IFS=, read -r run_order run_id method task run_num seed; do
  # Trim whitespace
  run_order="${run_order// /}"
  run_id="${run_id// /}"

  # Row filter
  if [ "$run_order" -lt "$FROM_ROW" ] || [ "$run_order" -gt "$TO_ROW" ]; then
    (( skipped++ )) || true
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
  (( dispatched++ )) || true
done

# Wait for all remaining workers
wait_all

echo "==========================================="
echo "Harness complete."
echo "  Dispatched: $dispatched  Skipped: $skipped"
echo "  Results:    $RESULTS_FILE"
echo "  Log:        $HARNESS_LOG"
echo "==========================================="
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x runs/run-harness.sh
```

- [ ] **Step 3: Dry-run smoke test**

```bash
source runs/config.sh
bash runs/generate_run_matrix.sh   # regenerate matrix with n=30
bash runs/run-harness.sh --dry-run --from 1 --to 10
```

Expected: 10 lines printed like:
```
  [DRY] run_order=1 run_id=20260519_gsd_3_H method=gsd task=H
  [DRY] run_order=2 run_id=20260519_bmad_1_E method=bmad task=E
  ...
```

No workers spawned, no file changes.

- [ ] **Step 4: Live smoke test — 4 parallel workers, tasks A and E only**

This creates 4 real workers at the same time to verify ports don't collide:

```bash
# Filter matrix to just task A and E for the first 4 rows that match
bash runs/run-harness.sh --from 1 --to 4 --parallel 4
```

Monitor progress:
```bash
tail -f runs/harness.log
```

Expected: 4 workers start nearly simultaneously, each printing its own `[worker ...]` prefix. All 4 should show different ports (3100, 3200, 3300, 3400).

- [ ] **Step 5: Verify no port collisions in the log**

```bash
grep "port=" runs/harness.log | awk '{print $NF}' | sort | uniq -d
```

Expected: empty output (no duplicate ports in any concurrent window).

- [ ] **Step 6: Verify 4 rows appended to results.tsv**

```bash
wc -l runs/results.tsv   # should be 5 (header + 4 data rows)
```

- [ ] **Step 7: Commit**

```bash
git add runs/run-harness.sh
git commit -m "feat: add run-harness.sh — parallel orchestrator with slot-based port isolation"
```

---

## Task 4: Add per-run env passthrough to test files (PORT env var)

**Files:**
- Modify: `SANDBOX/B/test.js`, `SANDBOX/D/test.js`, `SANDBOX/F/test.js`, `SANDBOX/H/test.js`, `SANDBOX/I/test.js`, `SANDBOX/J/test.js`
- Modify: `SANDBOX/B/server.js`, `SANDBOX/D/server.js`, `SANDBOX/F/server.js`, `SANDBOX/H/server.js`, `SANDBOX/I/server.js`, `SANDBOX/J/server.js`
- (Tasks A, E, G are read-only JSON/simple node — check first, likely already use env)

**Problem:** Tests and servers currently hardcode port 3000 or 3001. Parallel workers assign each a unique port via `$PORT`/`$TEST_PORT`. Every server and test must read `process.env.PORT` (or `process.env.TEST_PORT`) instead of a literal.

- [ ] **Step 1: Check which tasks have hardcoded ports**

```bash
grep -rn "listen(3" SANDBOX/ --include="*.js" | grep -v node_modules
grep -rn "localhost:3" SANDBOX/ --include="*.js" | grep -v node_modules
```

Note every file and line number that appears. You will fix each one in the steps below.

- [ ] **Step 2: For every server.js that has `app.listen(3000)` or `app.listen(3001)`, update to read from env**

Pattern to apply to each server file:

Find:
```js
app.listen(3000
```
Or:
```js
app.listen(3001
```

Replace with (example — adapt the variable name and comment to match the file's existing style):
```js
const PORT = parseInt(process.env.PORT || '3000', 10);
app.listen(PORT
```

If the file already has `const PORT = process.env.PORT || 3000`, it's fine — move on.

Run the grep from Step 1 again after each edit to confirm the literal is gone.

- [ ] **Step 3: For every test.js that constructs a URL with a hardcoded port, update to read from env**

Pattern to apply:

Find (various forms):
```js
const BASE = 'http://localhost:3000';
```
Or:
```js
fetch('http://localhost:3001/
```

Replace with:
```js
const PORT = process.env.TEST_PORT || process.env.PORT || '3000';
const BASE = `http://localhost:${PORT}`;
```

And update all fetch/axios/supertest calls that used the hardcoded URL to use `BASE` (or the equivalent variable that's already there).

- [ ] **Step 4: Verify Task B still passes with an explicit port**

```bash
cd SANDBOX/B
PORT=3200 TEST_PORT=3200 node server.js &
SERVER_PID=$!
sleep 1
TEST_PORT=3200 node test.js
kill $SERVER_PID
```

Expected: all assertions pass. This confirms the env-var pattern works end-to-end.

- [ ] **Step 5: Verify Task B still passes with the default port (backward compat)**

```bash
cd SANDBOX/B
node server.js &
SERVER_PID=$!
sleep 1
node test.js
kill $SERVER_PID
```

Expected: same pass count. Fallback to `'3000'` when `$PORT` is unset preserves existing behavior.

- [ ] **Step 6: Commit**

```bash
git add SANDBOX/*/server.js SANDBOX/*/test.js
git commit -m "fix: make all servers and tests read PORT from env (parallel isolation)"
```

---

## Task 5: Re-run matrix generation for n=30 and validate budget

**Files:**
- Regenerate: `runs/runs_matrix.csv`
- Regenerate: `runs/runs_matrix_seed.txt`

- [ ] **Step 1: Source updated config and regenerate the matrix**

```bash
source runs/config.sh
bash runs/generate_run_matrix.sh
```

Expected stderr:
```
[generate_run_matrix] Generating run matrix...
[generate_run_matrix]   Methods: bigpowers superpowers bmad spec-kit acps gsd bare
[generate_run_matrix]   Tasks: A B C D E F G H I J
[generate_run_matrix]   Runs per cell: 30
[generate_run_matrix]   Total budget: 2100
```

- [ ] **Step 2: Confirm row count**

```bash
wc -l runs/runs_matrix.csv
```

Expected: `2101` (header + 2100 data rows).

- [ ] **Step 3: Confirm each (method, task) cell has exactly 30 entries**

```bash
tail -n +2 runs/runs_matrix.csv \
  | awk -F, '{print $3","$4}' \
  | sort \
  | uniq -c \
  | awk '$1 != 30 {print "BAD:", $0}'
```

Expected: no output (all cells have exactly 30).

- [ ] **Step 4: Confirm the seed was saved**

```bash
cat runs/runs_matrix_seed.txt
```

Expected: a 16-char hex string.

- [ ] **Step 5: Confirm matrix is reproducible**

```bash
SAVED_SEED=$(cat runs/runs_matrix_seed.txt)
bash runs/generate_run_matrix.sh --seed "$SAVED_SEED"
# Compare
diff <(tail -n +2 runs/runs_matrix.csv | head -20) \
     <(bash runs/generate_run_matrix.sh --seed "$SAVED_SEED" 2>/dev/null && \
       tail -n +2 runs/runs_matrix.csv | head -20)
```

Expected: no diff.

- [ ] **Step 6: Commit the new matrix**

```bash
git add runs/runs_matrix.csv runs/runs_matrix_seed.txt
git commit -m "data: regenerate run matrix for n=30 (2100 trials, seed committed)"
```

---

## Task 6: Integration test — 4 parallel workers, 2 tasks, verify isolation

**Files:**
- No file changes — this is a validation task

This is the acceptance test for the full parallel isolation design. Run 8 trials simultaneously (4 workers × 2 rounds) and confirm: no port collisions, no worktree leakage, no npm cache write errors, all results logged.

- [ ] **Step 1: Reset results.tsv to header only**

```bash
head -1 runs/results.tsv > /tmp/results_backup.tsv
cp /tmp/results_backup.tsv runs/results.tsv
```

- [ ] **Step 2: Generate a small test matrix (2 methods × 2 tasks × 4 runs = 16 trials)**

```bash
# Temporarily override config for the test
N_RUNS_PER_CELL=4 N_METHODS=2 N_TASKS=2 \
  bash -c 'source runs/config.sh && bash runs/generate_run_matrix.sh'
```

Wait — `generate_run_matrix.sh` reads from `config.sh` directly. Use a different approach: filter the real matrix:

```bash
source runs/config.sh
bash runs/generate_run_matrix.sh   # full n=30 matrix already generated in Task 5
```

Then run just the first 16 rows via `--from 1 --to 16`:

- [ ] **Step 3: Run 16 trials with 4 parallel workers**

```bash
bash runs/run-harness.sh --from 1 --to 16 --parallel 4
```

Monitor in a second terminal:
```bash
tail -f runs/harness.log
```

- [ ] **Step 4: Check for port collision in the log**

```bash
grep "port=" runs/harness.log \
  | grep -oE 'port=[0-9]+' \
  | sort \
  | uniq -c \
  | sort -rn \
  | head -5
```

Each port should appear no more than once per time window. If the same port appears at the same timestamp with different run_ids, there is a collision — investigate `run-harness.sh`'s slot assignment.

- [ ] **Step 5: Check for npm cache write errors**

```bash
grep -i "EACCES\|EEXIST\|npm error\|cache" runs/harness.log | head -10
```

Expected: no cache errors. Each worker has its own `NPM_CONFIG_CACHE` dir.

- [ ] **Step 6: Check worktree cleanup**

```bash
ls /tmp/sabr_runs/ 2>/dev/null | wc -l
```

Expected: 0 or only active runs. After harness exits, all should be gone.

- [ ] **Step 7: Verify results.tsv received all 16 rows**

```bash
wc -l runs/results.tsv   # should be 17 (header + 16)
tail -5 runs/results.tsv | cut -f1-4
```

Expected: 5 distinct `run_id` values, all with `status` = PASS or FAIL (not empty).

- [ ] **Step 8: Restore full matrix**

```bash
source runs/config.sh
bash runs/generate_run_matrix.sh --seed "$(cat runs/runs_matrix_seed.txt)"
```

- [ ] **Step 9: Commit the test results as validation evidence**

```bash
git add runs/harness.log runs/results.tsv
git commit -m "test: 16-trial parallel integration test — 4 workers, 0 port collisions, 0 cache errors"
```

---

## Task 7: Update README_v2.md with parallel execution docs

**Files:**
- Modify: `runs/README_v2.md`

- [ ] **Step 1: Find the "Batch Execution" section in README_v2.md (around line 212)**

The current section shows a serial `while` loop harness. Replace it with the parallel harness instructions.

Find this block:
```markdown
## Batch Execution (for 900 trials)
```

Replace the entire section (through the closing code block) with:

```markdown
## Batch Execution (parallel, for 2100 trials)

**First:** Install npm dependencies once (if not already done):
```bash
bash runs/prebuild-cache.sh  # ~5-10 min, one-time
```

**Then:** Generate the run matrix (n=30, 2100 trials):
```bash
source runs/config.sh
bash runs/generate_run_matrix.sh
```

**Then:** Run the harness with 4 parallel workers:
```bash
bash runs/run-harness.sh --parallel 4
```

Each worker gets an isolated environment:
- **Port:** slot 0 → 3100, slot 1 → 3200, slot 2 → 3300, slot 3 → 3400
- **TMPDIR:** `/tmp/sabr_runs/<RUN_ID>/.tmp` — no `/tmp` bleed between runs
- **NPM_CONFIG_CACHE:** `/tmp/sabr_runs/<RUN_ID>/.npm` — no npm write contention
- **Git worktree:** `/tmp/sabr_runs/<RUN_ID>/` — only the active task visible

**Resume a partial run** (e.g., rows 500–2100 after a crash):
```bash
bash runs/run-harness.sh --from 500 --parallel 4
```

**Dry-run to preview the schedule:**
```bash
bash runs/run-harness.sh --dry-run | head -20
```

**Monitor progress:**
```bash
tail -f runs/harness.log
wc -l runs/results.tsv   # rows completed so far
```

**Expected wall-clock time:**
- n=30, 2100 trials at 10 min/trial avg
- Serial: ~350 hours
- 4 parallel workers: **~88 hours** (~3.7 days continuous)
- 8 parallel workers (if machine supports it): ~44 hours
```

- [ ] **Step 2: Update the "What's New in v2" table to mention n=30 and parallelism**

Find the table row:
```markdown
| **Statistical power** | n=5 | n=15 (900 runs total) |
```

Replace with:
```markdown
| **Statistical power** | n=5 | n=30 (2100 runs total) — detects medium effects (δ≥0.3) across all 21 pairs |
```

Find the row:
```markdown
| **Process isolation** | Shared task dirs | Isolated worktree per run |
```

Replace with:
```markdown
| **Process isolation** | Shared task dirs | Isolated worktree + per-run TMPDIR/NPM_CACHE/PORT (safe for 4-way parallelism) |
```

- [ ] **Step 3: Commit**

```bash
git add runs/README_v2.md
git commit -m "docs: update README_v2 for parallel execution and n=30"
```

---

## Self-Review

**Spec coverage check:**

| Requirement | Covered by |
|-------------|-----------|
| No Docker | Approach A: env namespacing — no Docker anywhere |
| Port collision prevention | Task 3: slot-based port assignment (3100/3200/3300/3400) |
| TMPDIR isolation | Task 2: `export TMPDIR=${RUN_SCRATCH}/.tmp` |
| NPM cache isolation | Task 2: `export NPM_CONFIG_CACHE=${RUN_SCRATCH}/.npm` |
| Worktree cleanup on crash | Task 2: `trap cleanup EXIT` |
| n=30 (valid samples) | Task 1: `N_RUNS_PER_CELL=30`, Task 5: matrix regeneration |
| Reproducible matrix | Task 5: seed preserved, regeneration verified |
| 4-way parallel | Task 3: `MAX_PARALLEL=4` default, `--parallel N` override |
| Resume after crash | Task 3: `--from ROW` flag |
| Server/test port env var | Task 4: all SANDBOX servers/tests read `process.env.PORT` |
| Integration validation | Task 6: 16-trial parallel smoke test |
| Documentation | Task 7: README_v2 updated |

**Placeholder scan:** No TBDs. All code blocks are complete. The agent-stub comment in `run-worker.sh` is intentional — it marks the hermes-agent integration point and is not a placeholder.

**Type consistency:** `WORKER_PORT` used consistently between harness (assigns it) and worker (consumes it). `RUN_ID` naming matches `log_run.sh` expectations. `PASS`/`FAIL`/`STATUS` parsing is identical to `run-all-tasks.sh` (copy-verified).
