# SABR Room 3 v2 — Quick-Start Guide

This guide walks through the new v2 experimental design: **process isolation** via git worktrees, **randomized execution**, **statistical rigor**, and **blinded scoring**.

## What's New in v2

| Aspect | Room 2 | Room 3 v2 |
|--------|--------|----------|
| **Process isolation** | Shared task dirs | Isolated worktree + per-run TMPDIR/NPM_CACHE/PORT (safe for 4-way parallelism) |
| **npm variance** | Network on timer | Pre-warmed cache |
| **Run order** | Fixed (method → task) | Randomized |
| **Statistical power** | n=5 | n=30 (2100 runs total) — detects medium effects (δ≥0.3) across all 21 pairs |
| **Spec scoring** | Unblinded | Blinded + dual raters |
| **Analysis** | Mean/percentile | Bootstrap CIs + Wilcoxon tests + Holm-Bonferroni |
| **Control baseline** | None | Bare methodology |

## Quick Start (5-Minute Setup)

### 1. Configure the experiment

Edit `runs/config.sh`:
```bash
export N_RUNS_PER_CELL=15      # or 5/10 if constrained
export BUDGET_TOTAL=$(( 15 * 7 * 10 ))  # auto-computed: n × methods × tasks = 1050
export METHODOLOGIES="bigpowers superpowers bmad spec-kit acps gsd bare"
export INCLUDE_BARE=true
```

### 2. Install npm dependencies in SANDBOX (one-time, ~5–10 min)

```bash
bash runs/prebuild-cache.sh
```

This runs `npm install` for each task **and keeps node_modules in SANDBOX**. Since `reset_lab.sh` uses `rsync --delete` to copy SANDBOX → working directory, `node_modules` persist across resets. This saves **10–60 seconds per run** on npm install, eliminating network variance from the timer.

### 3. Generate the run matrix

```bash
source runs/config.sh
bash runs/generate_run_matrix.sh
```

Outputs:
- `runs/runs_matrix.csv` — randomized schedule of all trials
- `runs/runs_matrix_seed.txt` — seed for reproducibility

Example first 5 rows of `runs_matrix.csv`:
```
run_order,run_id,method,task,run_num,seed
1,20260519_gsd_2_E,gsd,E,2,abc123def456
2,20260519_bmad_1_A,bmad,A,1,abc123def456
3,20260519_spec-kit_3_C,spec-kit,C,3,abc123def456
...
```

### 4. Run the pilot (optional but recommended, ~1–2 hours)

Before committing to 900 trials, test the infrastructure on 20 runs:

```bash
# Edit runs/config.sh:
# export N_RUNS_PER_CELL=5 (temporarily)
# export METHODOLOGIES="gsd bmad"

source runs/config.sh
bash runs/generate_run_matrix.sh  # regenerate for just 2 methods × 2 tasks × 5 runs

# Now run 20 trials manually (see "Per-Run Workflow" below)
```

Monitor:
- Worktrees are isolated; no cross-task visibility
- `npm install` takes <10s (confirms caching)
- Spec artifacts are anonymized correctly
- `stats-analysis.py` runs without errors

## Per-Run Workflow

For each row in `runs_matrix.csv`:

### Step 1: Reset task to isolated worktree

```bash
WTREE=$(bash reset_lab_v2.sh E "20260519_gsd_2_E" gsd)
cd "$WTREE/E"

# Agent now only sees this task; cannot peek at A/B/C...
ls /  # No other tasks visible (isolated worktree)

# node_modules already present (copied from SANDBOX)
ls node_modules | head -5  # ✓ Should see modules, no npm install needed
```

`reset_lab_v2.sh` returns the path to the isolated worktree and preserves `node_modules` from SANDBOX. Copy/paste the path into subsequent steps.

### Step 2: Record start time

```bash
START=$(date +"%Y-%m-%dT%H:%M:%S%z" | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/')
echo "START: $START"
```

### Step 3: Send task prompt to agent

Use the isolated `$WTREE/E` path as the workspace.

Methodology prompt (from STARTUP-PROMPT.md) + task prompt.

Example: Task E (Element Filter API)
```
Complete this task in the sandbox at: /tmp/sabr_runs/20260519_gsd_2_E/E

[Task prompt for E...]
```

### Step 4: Agent solves the task

(30 min to 2 hours depending on task and methodology)

### Step 5: Record end time

```bash
END=$(date +"%Y-%m-%dT%H:%M:%S%z" | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/')
echo "END: $END"
```

### Step 6: Run tests and record results

```bash
cd "$WTREE/E"

# Task E:
node test.js

# Capture: PASS/FAIL count, STATUS (PASS|ERROR)
```

### Step 7: Blind and score specs (if written)

```bash
bash runs/blind-specs.sh "$WTREE/E" "20260519_gsd_2_E" "gsd" "E"
```

Outputs anonymized spec files to `runs/blinded-specs/`.

**Hand to rater(s):** Score each `anon_*.md` file as 0/1/2 without seeing the run ID.

Rater 1 output: `runs/rater1_scores.csv`
```
anon_a7f3d1e,2
anon_b9e2f4c,1
```

Rater 2 output: `runs/rater2_scores.csv` (same format)

### Step 8: Unblind and reconcile scores

```bash
bash runs/unblind-specs.sh runs/rater1_scores.csv runs/rater2_scores.csv
```

Outputs:
- `runs/spec-scores.tsv` — canonical scores per run_id (with Cohen's κ)
- Reports any disagreements between raters

### Step 9: Log the run

```bash
spec_quality=$(grep "^20260519_gsd_2_E" runs/spec-scores.tsv | cut -f2)

bash runs/log_run.sh \
  2 gsd E "20260519_gsd_2_E" \
  "$START" "$END" \
  5 0 PASS \
  — "$spec_quality" 0 3200 \
  12 1 1 2 0 \
  "clean greenfield, spec resolved all ambiguities"
```

Fields (in order):
1. RUN — cycle number (1–5 in v2 with n=5; or 1–15 with n=15)
2. METHOD — methodology name (gsd, bmad, etc.)
3. TASK — task letter (A–J)
4. RUN_ID — unique identifier (e.g., "20260519_gsd_2_E")
5. START_ISO — start time (ISO-8601)
6. END_ISO — end time
7. PASS — assertion pass count
8. FAIL — assertion fail count
9. STATUS — PASS or ERROR
10. ERROR_TYPE — (— if PASS)
11. SPEC_QUALITY — 0/1/2
12. ARTIFACTS — count of new .md files (optional)
13. TOKENS — tokens consumed by model
14. FIRST_CODE_SEC — seconds to first code edit
15. SPEC_BEFORE_CODE — 1 if spec written before code
16. REWORK_COUNT — edits to already-written files
17. FILES_TOUCHED — distinct files modified
18. CONTRADICTION_FOUND — 1 if agent caught ambiguity
19. NOTES — qualitative observations

### Step 10: Cleanup worktree

```bash
bash reset_lab_v2.sh --cleanup "$WTREE"
```

Or: automatically cleaned by trap handler if you wrap the run in a bash script.

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

## Analyzing Results

After all trials complete:

### 1. Generate statistical report

```bash
python3 runs/stats-analysis.py runs/results.tsv --alpha 0.05 --bootstraps 10000
```

Outputs:
- `runs/stats-report.md` — markdown report with tables, CIs, Wilcoxon tests, effect sizes

### 2. Read the report

Open `runs/stats-report.md`:
- **Summary Statistics**: Pass rate ± 95% CI per method
- **Pairwise Comparisons**: Wilcoxon signed-rank p-values (Holm-Bonferroni corrected)
- **Effect Sizes**: Cliff's δ with interpretation
- **Observability**: Avg first_code_sec, spec_before_code%, rework_count, etc.
- **Ranking**: Methods ranked by pass rate with overlapping CIs

### 3. Parse for publication

```bash
bash runs/parse-results.sh runs/results.tsv | tee runs/lean-summary.txt
```

(Backward-compatible lean summary for quick reading)

## Troubleshooting

### Worktree creation fails

Error: `git worktree add --detach ... failed`

**Solution:**
```bash
git worktree prune  # clean stale entries
rm -rf /tmp/sabr_runs/*  # reset worktree root
bash reset_lab_v2.sh E "20260519_test_E" gsd
```

### npm install timeout

If `npm install` in the isolated worktree exceeds `NPM_TARGET_SEC`, it won't invalidate the run, but will be logged as a covariate. Check:
```bash
cd "$WTREE/E"
npm install --verbose  # debug
```

### Spec blinding fails (no jq)

If `jq` is not installed:
```bash
brew install jq  # macOS
apt-get install jq  # Linux
```

Without `jq`, blinding still runs, but the blind key won't be automatically updated. Manually add entries to `runs/blinded-key.json`:
```json
{
  "anon_a7f3d1e": {"run_id": "20260519_gsd_1_E", "method": "gsd", "task": "E"},
  ...
}
```

### Python stats analysis fails

Requires Python 3.8+ with numpy/scipy optional:
```bash
pip install numpy scipy  # for full stats (recommended)
# or: python3 runs/stats-analysis.py ... (will use pure-Python fallbacks, slower)
```

## Advanced: Custom Configuration

Edit `runs/config.sh`:

```bash
# Experiment scale
export N_RUNS_PER_CELL=10  # fewer trials if constrained
export BUDGET_TOTAL=600

# Methodologies (reorder or subset)
export METHODOLOGIES="gsd bmad spec-kit acps"
export INCLUDE_BARE=false  # skip control arm

# Timing thresholds
export RUN_TIMEOUT_SEC=1200  # max 20 min per run
export NPM_TARGET_SEC=15

# Dual-rater spec scoring
export ENABLE_DUAL_RATERS=true
export RATER1_NAME="Alice"
export RATER2_NAME="Bob"

# Statistical parameters
export ALPHA=0.10  # less stringent
export BOOTSTRAP_RESAMPLES=5000  # faster, less precise

# Token pricing
export TOKEN_PRICE_PER_1M=4000  # $40 per 1M (e.g., Claude Opus)
```

Then regenerate:
```bash
source runs/config.sh
bash runs/generate_run_matrix.sh
```

## Files & Outputs

```
runs/
├── config.sh                 # Configuration (source this first)
├── prebuild-cache.sh         # One-time npm warming
├── generate_run_matrix.sh    # Randomized execution schedule
├── log_run.sh                # Record one trial result
├── blind-specs.sh            # Anonymize spec artifacts
├── unblind-specs.sh          # Reveal & reconcile scores
├── stats-analysis.py         # Statistical pipeline
├── parse-results.sh          # Lean tabular summary (backward-compat)
├── README_v2.md              # This file
│
├── results.tsv               # Canonical trial log (appended per run)
├── runs_matrix.csv           # Randomized schedule (regenerated per config)
├── runs_matrix_seed.txt      # Seed for reproducibility
├── spec-scores.tsv           # Canonical spec quality scores
├── blinded-key.json          # Mapping: anon_id → run_id
├── blinded-specs/            # Anonymized spec files for raters
├── stats-report.md           # Final statistical report
└── execution-log.md          # Qualitative notes per run
```

## Reproducibility Checklist

- [ ] `runs/config.sh` committed (fixes BUDGET, N_RUNS, METHODOLOGIES)
- [ ] `runs/runs_matrix_seed.txt` committed (enables replay with same seed)
- [ ] All trial `.run_id` values unique and recorded in results.tsv
- [ ] `bash runs/generate_run_matrix.sh --seed $(cat runs/runs_matrix_seed.txt)` produces identical `runs_matrix.csv`
- [ ] Python version recorded: `python3 --version`
- [ ] numpy/scipy versions: `pip freeze | grep -E "numpy|scipy"`
- [ ] Cohen's κ ≥ 0.6 for dual-rater spec scoring (or disagreements documented)
- [ ] At least one pairwise comparison significant after Holm-Bonferroni correction (or power re-evaluated)

## Questions?

- **Replicating a specific run:** Look up the run_id in results.tsv, extract the run_order, and resync the run matrix with the seed.
- **Adjusting for new tasks:** Increase N_TASKS in config.sh, regenerate, and only run the new (method, new_task, run) combos.
- **Combining with Room 2 data:** Keep separate results.tsv files; do not mix n=5 and n=15 in the same analysis.
