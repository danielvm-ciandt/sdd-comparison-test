#!/usr/bin/env bash
# config.sh — Configuration for SABR Room 3 v2 experiment.
#
# Source this file before running generate_run_matrix.sh, log_run.sh, or stats-analysis.py
#
# Example:
#   source runs/config.sh
#   bash runs/generate_run_matrix.sh

# ──────────────────────────────────────────────────────────────────────────────
# Experiment Parameters
# ──────────────────────────────────────────────────────────────────────────────

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

# Methodologies (in execution order after randomization)
export METHODOLOGIES="bigpowers superpowers bmad spec-kit acps gsd bare"

# Include bare (no-prompt) control arm
export INCLUDE_BARE=true

# ──────────────────────────────────────────────────────────────────────────────
# Paths
# ──────────────────────────────────────────────────────────────────────────────

export SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export RUNS_DIR="${SCRIPT_ROOT}/runs"
export RESULTS_FILE="${RUNS_DIR}/results.tsv"
export RUNS_MATRIX_FILE="${RUNS_DIR}/runs_matrix.csv"
export MATRIX_SEED_FILE="${RUNS_DIR}/runs_matrix_seed.txt"
export STATS_REPORT="${RUNS_DIR}/stats-report.md"
export BLINDED_SPECS_DIR="${RUNS_DIR}/blinded-specs"
export BLINDED_KEY_FILE="${RUNS_DIR}/blinded-key.json"

# Worktree root for isolated runs
export WORKTREE_ROOT="${WORKTREE_ROOT:-/tmp/sabr_runs}"

# ──────────────────────────────────────────────────────────────────────────────
# Timing & Thresholds
# ──────────────────────────────────────────────────────────────────────────────

# Timeout per run (in seconds). Adjust based on your task complexity.
# This is the max time allowed from start_time to end_time (includes npm install, agent, tests, scoring).
export RUN_TIMEOUT_SEC=900  # 15 minutes

# Target time for npm install (cached). If exceeded, it's logged as a covariate.
export NPM_TARGET_SEC=10

# ──────────────────────────────────────────────────────────────────────────────
# Spec Quality Scoring
# ──────────────────────────────────────────────────────────────────────────────

# Set to true if you have two independent raters for spec_quality.
# If true, runs will wait for RATER1_NAME and RATER2_NAME scores, and Cohen's κ is computed.
export ENABLE_DUAL_RATERS=true
export RATER1_NAME="rater_1"
export RATER2_NAME="rater_2"

# Spec quality levels
# 0 = no spec or plan document written
# 1 = bullet notes or rough plan
# 2 = structured document resolving all ambiguities/contradictions
export SPEC_QUALITY_LEVELS="0:none 1:partial 2:complete"

# ──────────────────────────────────────────────────────────────────────────────
# Statistical Analysis
# ──────────────────────────────────────────────────────────────────────────────

# Significance level for hypothesis tests
export ALPHA=0.05

# Bootstrap resamples for confidence intervals
export BOOTSTRAP_RESAMPLES=10000

# Which effect size threshold to highlight in the report
export EFFECT_SIZE_THRESHOLD=0.330  # small effect (Cliff's δ)

# Token pricing for cost calculations (USD per 1M tokens)
# Claude 3.5 Sonnet: $3 / 1M input, $15 / 1M output (rough average ~$0.003/token)
export TOKEN_PRICE_PER_1M=3000  # in cents, or use --token-price in stats-analysis.py

# ──────────────────────────────────────────────────────────────────────────────
# Reproducibility
# ──────────────────────────────────────────────────────────────────────────────

# Random seed for run matrix generation (set by generate_run_matrix.sh).
# If unset, a new seed is generated and stored in MATRIX_SEED_FILE.
export MATRIX_SEED=""

# Python version check (stats-analysis.py requires Python 3.8+)
export PYTHON_MIN_VERSION="3.8"

# ──────────────────────────────────────────────────────────────────────────────
# Validation
# ──────────────────────────────────────────────────────────────────────────────

log_info() {
  echo "[config.sh]" "$@" >&2
}

validate_config() {
  local errors=0

  if [ ! -d "$SCRIPT_ROOT" ]; then
    log_info "ERROR: SCRIPT_ROOT not found: $SCRIPT_ROOT"
    errors=$((errors + 1))
  fi

  if [ ! -d "${SCRIPT_ROOT}/SANDBOX" ]; then
    log_info "ERROR: SANDBOX directory not found: ${SCRIPT_ROOT}/SANDBOX"
    errors=$((errors + 1))
  fi

  if [ ! -f "$RESULTS_FILE" ] && [ ! -w "$(dirname "$RESULTS_FILE")" ]; then
    log_info "ERROR: Cannot write to RESULTS_FILE directory: $(dirname "$RESULTS_FILE")"
    errors=$((errors + 1))
  fi

  if [ "$BUDGET_TOTAL" -eq 0 ]; then
    log_info "ERROR: BUDGET_TOTAL is 0 (check N_RUNS_PER_CELL, N_METHODS, N_TASKS)"
    errors=$((errors + 1))
  fi

  if [ "$errors" -gt 0 ]; then
    log_info "Config validation failed with $errors error(s)"
    return 1
  fi

  return 0
}

# ──────────────────────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────────────────────

if [ "${1:---}" = "--info" ]; then
  cat >&2 <<EOF
=== SABR Room 3 v2 Configuration ===
Total runs (BUDGET):    $BUDGET_TOTAL
  n per cell:           $N_RUNS_PER_CELL
  methodologies:        $N_METHODS
  tasks:                $N_TASKS

Methodologies:          $METHODOLOGIES
Include bare control:   $INCLUDE_BARE

Results file:           $RESULTS_FILE
Run matrix:             $RUNS_MATRIX_FILE
Worktree root:          $WORKTREE_ROOT

Spec quality raters:    $([ "$ENABLE_DUAL_RATERS" = "true" ] && echo "2 (dual) with Cohen's κ" || echo "1 (single)")
Statistical alpha:      $ALPHA
Bootstrap resamples:    $BOOTSTRAP_RESAMPLES
Token price (/1M):      \$$((TOKEN_PRICE_PER_1M / 100))

EOF
fi
