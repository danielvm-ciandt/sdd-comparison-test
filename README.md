# SABR Extended: Methodology Comparison Experiment v2

[![Experiment Status](https://img.shields.io/badge/status-ready%20for%20pilot-blue)](#quick-start)
[![License](https://img.shields.io/badge/license-MIT-green)]()
[![Python](https://img.shields.io/badge/python-3.8+-blue)](#requirements)

## Motivation

How much do different prompting methodologies actually improve AI-assisted software engineering? Most evaluations measure raw capability (pass rate on a fixed benchmark), but don't isolate or quantify the effectiveness of **methodology itself**. This experiment answers: *given identical tasks and a fixed model, which methodologies produce the best results, and by how much?*

We compare 7 methodologies (including a control arm) across 10 diverse tasks with rigorous statistical design:
- **Process isolation** via git worktrees (no cross-contamination)
- **Randomized execution** (eliminates order effects, model drift)
- **Blinded dual-rater scoring** (removes evaluator bias)
- **Statistical rigor** (bootstrap CIs, Wilcoxon tests, Holm-Bonferroni correction)
- **Reproducible by design** (seeded randomization, full audit trail)

## What's New in v2

| Aspect | Room 2 | Room 3 v2 |
|--------|--------|----------|
| **Process isolation** | Shared task dirs | Isolated git worktree per run |
| **npm variance** | 10–60s network noise per run | Pre-warmed cache, eliminates noise |
| **Execution order** | Fixed (method 1..7, task A..J) | Randomized → removes model/evaluator drift |
| **Statistical power** | n=5, no significance testing | n=15 with bootstrap CIs, Wilcoxon tests |
| **Multiple comparisons** | None | Holm-Bonferroni (15 pairwise) |
| **Effect sizes** | None | Cliff's δ with interpretation |
| **Spec scoring** | Unblinded, 1 rater | Blinded, 2 raters, Cohen's κ |
| **Control baseline** | None | Bare model (zero-shot) |
| **Analysis** | Tables/percentiles | Publication-ready markdown report |

## Quick Start

### 1. Clone & Configure (5 minutes)

```bash
git clone https://github.com/[your-org]/sdd-comparison-test.git
cd sdd-comparison-test

# Edit runs/config.sh to choose experiment scale:
# - PILOT: N_RUNS_PER_CELL=5 (20 trials total, ~1–2 hours)
# - FULL: N_RUNS_PER_CELL=15 (900 trials, ~150 hours wall-clock)
nano runs/config.sh
```

### 2. Pre-warm npm Cache (One-time, ~5–10 min)

```bash
bash runs/prebuild-cache.sh
# Installs node_modules in SANDBOX; preserved across all runs
```

### 3. Generate Run Matrix

```bash
source runs/config.sh
bash runs/generate_run_matrix.sh
# Outputs: runs/runs_matrix.csv (randomized schedule)
#          runs/runs_matrix_seed.txt (for reproducibility)
```

### 4. Run Pilot (20 trials, 2 methods × 2 tasks × 5 runs)

```bash
# Edit config.sh:
export N_RUNS_PER_CELL=5
export METHODOLOGIES="gsd bmad"

source runs/config.sh
bash runs/generate_run_matrix.sh  # regenerate for pilot

# Manual or batch: see runs/README_v2.md for per-run workflow
```

### 5. Analyze Results

```bash
python3 runs/stats-analysis.py runs/results.tsv --alpha 0.05 --bootstraps 10000
# Outputs: runs/stats-report.md (publication-ready tables & figures)
```

## Architecture & Design

### Experimental Matrix

```
Methodologies (7):  bigpowers, superpowers, bmad, spec-kit, acps, gsd, bare
Tasks (10):         A–J (diverse SWE scenarios)
Replicates (n):     15 per cell (900 total trials)
```

### Process Isolation

Each trial runs in a **fresh git worktree** at `/tmp/sabr_runs/<RUN_ID>`:
```
/tmp/sabr_runs/20260519_gsd_1_E/
├── .git/           (detached HEAD)
└── E/              (only Task E visible; A–J hidden)
    ├── src/
    ├── test.js
    └── node_modules/  (pre-installed, no npm install needed)
```

Guarantees: The agent cannot see or interfere with other tasks.

### npm Optimization

**Problem:** Traditional per-run `npm install` adds 10–60s of network variance.

**Solution:** Install once in SANDBOX (via `prebuild-cache.sh`), then preserve via `rsync --delete`:
```bash
# One-time (Phase 2):
bash runs/prebuild-cache.sh
# → SANDBOX/A/node_modules/ ... SANDBOX/J/node_modules/

# Per-run (Phase 1):
bash reset_lab_v2.sh E "20260519_gsd_1_E" gsd
# → /tmp/sabr_runs/20260519_gsd_1_E/E/node_modules/ (copied, not reinstalled)
# Saves 10–60s per trial
```

### Randomized Execution

All (method, task, run_num) tuples are randomly permuted with a seeded LCG:
```
Original (confounded): method-1 task-A run-1, method-1 task-A run-2, ...
Randomized:            method-6 task-E run-3, method-2 task-C run-1, method-1 task-J run-2, ...
```

Eliminates: model drift (later runs benefit from earlier task knowledge), evaluator fatigue (later scores drift).

**Reproducible:** `bash generate_run_matrix.sh --seed $(cat runs_matrix_seed.txt)` regenerates identical matrix.

### Blinded Spec Quality Scoring

1. After agent finishes, run `bash runs/blind-specs.sh`
   - Spec artifacts anonymized: `spec_20260519_gsd_1_E.md` → `anon_a7f3d1e.md`
   - Blind key stored: `{ "anon_a7f3d1e": { run_id, method, task } }`

2. Two independent raters score each anonymized spec (0/1/2) without seeing run context

3. Run `bash runs/unblind-specs.sh rater1.csv rater2.csv`
   - Computes Cohen's κ (inter-rater reliability)
   - Flags disagreements (κ < 0.6 requires review)
   - Outputs: `runs/spec-scores.tsv` with final scores

### Statistical Analysis

**Input:** `runs/results.tsv` (one row per trial, ~30 columns)

**Output:** `runs/stats-report.md` with:

- **Summary statistics** per method: pass rate, cycle time, token cost (all with 95% bootstrap CI)
- **Pairwise comparisons:** Wilcoxon signed-rank test (paired, nonparametric) with Holm-Bonferroni correction (α=0.05)
- **Effect sizes:** Cliff's δ (negligible < 0.147 | small | medium | large)
- **Observability:** Method effects on first_code_sec, spec_before_code, contradiction_found, rework_count
- **Ranking table:** Methods ordered by pass rate CI lower bound

**Features:**
- Bootstrap CI: 10k resamples, percentile method (no normality assumption)
- Multiple-comparison correction: Holm-Bonferroni (controls family-wise error rate)
- Graceful fallback: Pure-Python fallbacks if numpy/scipy unavailable

## 7 Methodologies

| Name | Description | Expected |
|------|-------------|----------|
| **gsd** | GSD methodology (structured, spec-first) | High spec quality, lower rework |
| **bmad** | BMAD methodology (model-assisted design) | Balanced code/spec iteration |
| **spec-kit** | Spec-Kit (spec-heavy) | Higher artifact count |
| **acps** | ACPS (adaptive cycle planning) | Adaptive iteration strategy |
| **superpowers** | Superpowers (extended capabilities) | Fast code generation |
| **bigpowers** | BigPowers (aggressive approach) | Maximum throughput |
| **bare** | Bare model (control, zero-shot) | Minimal methodology overhead; baseline |

## 10 Tasks (A–J)

Each task is a sandbox with:
- `FEATURE_REQUEST.md` or `MIGRATION_REQUEST.md` (immutable spec)
- `src/` directory (code to implement or modify)
- `test.js` (success criteria)
- `specs/` (for agent-written artifacts)

**Tasks:**
- **A–E:** Simple, deterministic (Leaky Proxy, Element Filter, Bounded Backoff, etc.)
- **F–J:** Complex, ambiguous (Banking Migration, Chat Presence, Music Store, Project Tracker, etc.)

See `SANDBOX/[A-J]/` for full details.

## Files & Workflows

```
sdd-comparison-test/
├── README.md                       # This file
├── IMPLEMENTATION_SUMMARY_V2.md   # Technical architecture v2
├── reset_lab.sh                    # Original reset (preserves node_modules)
├── reset_lab_v2.sh                 # New: git worktree isolation per run
├── SANDBOX/                        # Immutable task baselines
│   ├── A/ ... J/
│   └── [A-J]/node_modules/         # Pre-installed (one-time via prebuild-cache.sh)
├── runs/
│   ├── config.sh                   # Edit once: BUDGET, N_RUNS, METHODOLOGIES
│   ├── README_v2.md                # Complete per-run workflow guide
│   ├── prebuild-cache.sh           # One-time npm warmup
│   ├── generate_run_matrix.sh      # Randomized execution schedule
│   ├── log_run.sh                  # Record one trial
│   ├── blind-specs.sh              # Anonymize for scoring
│   ├── unblind-specs.sh            # Reconcile dual-rater scores
│   ├── stats-analysis.py           # Bootstrap CI, Wilcoxon, Holm-Bonferroni
│   │
│   ├── results.tsv                 # Canonical trial log (appended per run)
│   ├── runs_matrix.csv             # Randomized schedule
│   ├── runs_matrix_seed.txt        # Seed for reproducibility
│   ├── spec-scores.tsv             # Final spec quality scores
│   ├── blinded-key.json            # anon_id → run_id mapping
│   ├── blinded-specs/              # Anonymized spec files for raters
│   └── stats-report.md             # Final report (generated post-analysis)
└── STARTUP-PROMPT.md               # Methodology prompts + task context
```

## Observability Metrics

Every trial records:

| Metric | Meaning |
|--------|---------|
| `pass` / `fail` | Test assertions passed/failed |
| `cycle_time_sec` | Wall-clock duration start → end |
| `status` | PASS, ERROR, TIMEOUT |
| `spec_quality` | 0=none, 1=partial, 2=complete (dual-rater consensus) |
| `tokens_used` | LLM tokens consumed |
| `first_code_sec` | Seconds to first code edit |
| `spec_precedes_code` | 1 if spec written before code |
| `rework_count` | Number of re-edits to existing files |
| `files_touched` | Distinct files modified |
| `contradiction_found` | 1 if agent caught spec ambiguity |

These enable rich observability: Which methodologies write specs first? Which minimize rework? Which find contradictions?

## Running the Full Experiment

### Pilot (20 trials, ~1–2 hours)

```bash
# 1. Edit config.sh:
N_RUNS_PER_CELL=5
METHODOLOGIES="gsd bmad"

# 2. Regenerate matrix:
source runs/config.sh
bash runs/generate_run_matrix.sh

# 3. Run 20 trials (see runs/README_v2.md for per-run workflow)
# Manual or batch harness (template in README_v2.md)

# 4. Validate:
# ✓ All 20 worktrees created and cleaned up
# ✓ npm install <10s per trial
# ✓ Tests recorded correctly
# ✓ Specs anonymized and scored
# ✓ stats-analysis.py runs successfully
```

### Full Run (900 trials, ~150 hours)

```bash
# 1. Reset config to full:
N_RUNS_PER_CELL=15
METHODOLOGIES="bigpowers superpowers bmad spec-kit acps gsd bare"
BUDGET_TOTAL=1050

# 2. Regenerate:
source runs/config.sh
bash runs/generate_run_matrix.sh

# 3. Run batch harness (template in runs/README_v2.md)
# Can be parallelized, distributed, or run serially

# 4. Generate report:
python3 runs/stats-analysis.py runs/results.tsv --alpha 0.05 --bootstraps 10000
# → runs/stats-report.md
```

## Understanding the Output

After full run, read `runs/stats-report.md`:

```markdown
# SABR Extended v2 Statistical Report

## Summary Statistics

| Methodology | Pass Rate | 95% CI | Cycle Time (sec) | Tokens |
|-------------|-----------|--------|------------------|--------|
| **gsd**     | 72% | [68%, 76%] | 487 ± 45 | 8,200 ± 1,100 |
| **bmad**    | 68% | [64%, 72%] | 501 ± 52 | 8,900 ± 1,300 |
| **bare**    | 31% | [27%, 35%] | 312 ± 28 | 4,100 ± 600 |

## Pairwise Comparisons (Holm-Bonferroni corrected, α=0.05)

| Method 1 | Method 2 | U | p-value | Cliff's δ | Sig? |
|----------|----------|---|---------|-----------|------|
| **gsd**  | **bmad** | 152 | 0.087 | 0.18 | No (small effect) |
| **gsd**  | **bare** | 89  | <0.001 | 0.64 | Yes (large effect) |
...

## Ranking (by Pass Rate CI Lower Bound)

1. gsd [68%, 76%]
2. bmad [64%, 72%]
3. acps [62%, 70%]
```

## Reproducibility Checklist

- [ ] `runs/config.sh` committed (fixes BUDGET, N_RUNS, METHODOLOGIES)
- [ ] `runs/runs_matrix_seed.txt` committed (enables full replay)
- [ ] All trial `run_id` values unique
- [ ] `bash runs/generate_run_matrix.sh --seed $(cat runs/runs_matrix_seed.txt)` reproduces identical matrix
- [ ] Python/numpy/scipy versions recorded (`pip freeze`)
- [ ] Cohen's κ ≥ 0.6 for dual-rater spec scoring (or disagreements documented)
- [ ] At least one pairwise comparison significant (or power re-evaluated)

## Requirements

### System
- **macOS/Linux** (git, bash 4.0+, rsync)
- **Python 3.8+** (for stats analysis; optional numpy/scipy for full features)
- **Node.js 16+** (for task test suites)

### Optional Dependencies
```bash
# For full statistical analysis (recommended):
pip install numpy scipy

# For spec blinding (recommended):
brew install jq  # macOS
apt-get install jq  # Linux
```

## Troubleshooting

### Worktree creation fails
```bash
git worktree prune
rm -rf /tmp/sabr_runs/*
bash reset_lab_v2.sh E "20260519_test_E" gsd
```

### npm install timeout
Pre-warmed cache should take <10s. If slower:
```bash
cd /tmp/sabr_runs/[RUN_ID]/[TASK]
npm install --verbose
```

### Spec blinding fails (no jq)
Install jq or manually edit `runs/blinded-key.json`:
```json
{
  "anon_a7f3d1e": {"run_id": "20260519_gsd_1_E", "method": "gsd", "task": "E"}
}
```

### Python stats fails
Requires 3.8+. Install optional dependencies:
```bash
pip install numpy scipy
# or: python3 runs/stats-analysis.py ... (pure-Python fallback, slower)
```

## Known Limitations & Contingencies

1. **If n=900 is too expensive:** Cap BUDGET_TOTAL in config.sh to 300 and randomly sample the matrix. Statistical power will be lower but design remains sound.

2. **If dual-rater scoring is impractical:** Use single rater but note potential bias in limitations section.

3. **If worktrees cause issues:** Fall back to temp directories + rsync. Trade-off: slightly more state bleeding, simpler debugging.

4. **If Python unavailable:** Rewrite stats-analysis.py in bash with `awk`/`bc`. Slower but feasible.

## Roadmap

- [ ] **Pilot (2–3 hours):** Validate infrastructure on 20 trials
- [ ] **Full Run (5–7 days continuous):** Execute 900 trials with full statistical rigor
- [ ] **Analysis (1–2 hours):** Generate stats-report.md with publication-ready tables
- [ ] **External Validation (5–10 days):** Cross-walk top 3 methods on SWE-bench Verified for credibility
- [ ] **Publication:** Write paper with methodology comparison, effect sizes, limitations

## Contributing

To extend this experiment:

1. **New task:** Add to SANDBOX/K/, run `bash runs/prebuild-cache.sh` for that task only, regenerate matrix
2. **New methodology:** Add to METHODOLOGIES in config.sh, regenerate matrix
3. **Custom scoring:** Modify rater CSVs before unblinding
4. **Analysis modifications:** Edit runs/stats-analysis.py (e.g., different significance level, effect size threshold)

## FAQ

**Q: Can I mix Room 2 (n=5) and Room 3 v2 (n=15) results?**
A: No. Keep separate results.tsv files. Statistical power differs; mixing confounds analysis.

**Q: How reproducible is this?**
A: Fully reproducible. Commit config.sh and runs_matrix_seed.txt; all downstream analyses deterministic.

**Q: Can I parallelize the 900 trials?**
A: Yes. Each trial is independent; use the batch harness template to distribute across machines or processes.

**Q: What if a trial times out?**
A: Recorded as `status=ERROR`, `error_type=TIMEOUT`. Partial data (if any) still logged; run marked failed.

**Q: How do I interpret Cohen's κ < 0.6?**
A: Dual-rater disagreement flags potential scoring ambiguity. Review disagreed specs and revise scoring criteria.

## License

MIT. See LICENSE file.

## Contact

For questions or to join the experiment, contact: danielvm@ciandt.com

---

**Ready to benchmark your methodology? Run `bash runs/prebuild-cache.sh` → `bash runs/generate_run_matrix.sh` → start the pilot!**
