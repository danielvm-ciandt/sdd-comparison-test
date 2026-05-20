#!/usr/bin/env bash
# unblind-specs.sh — Reveal run context and reconcile spec_quality scores.
#
# This script:
#  1. Takes two rater CSV files (anon_id, spec_quality)
#  2. Looks up the blind key to identify which run each file belongs to
#  3. Computes Cohen's κ for inter-rater reliability
#  4. Records final spec_quality (average, majority vote, or flagged for review)
#  5. Appends results to a canonical spec-scores.tsv for use in log_run.sh
#
# Usage:
#   bash runs/unblind-specs.sh <RATER1_CSV> [RATER2_CSV]
#
# Rater CSV format (no header):
#   anon_a7f3d1e,2
#   anon_b9e2f4c,1
#   anon_c3d6a2k,2
#
# Output:
#   runs/spec-scores.tsv (canonical scores per run_id)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/runs/config.sh"

log() {
  echo "[unblind-specs]" "$@" >&2
}

# ──────────────────────────────────────────────────────────────────────────────
# Parse arguments and validate
# ──────────────────────────────────────────────────────────────────────────────

if [ "$#" -lt 1 ]; then
  cat >&2 <<EOF
Usage: bash unblind-specs.sh <RATER1_CSV> [RATER2_CSV]

Rater CSV format (no header):
  anon_a7f3d1e,2
  anon_b9e2f4c,1

Output: runs/spec-scores.tsv (run_id, spec_quality_final, rater1, rater2, kappa, notes)
EOF
  exit 1
fi

RATER1_CSV="$1"
RATER2_CSV="${2:----}"
SPEC_SCORES_FILE="${RUNS_DIR}/spec-scores.tsv"

if [ ! -f "$RATER1_CSV" ]; then
  log "ERROR: Rater 1 CSV not found: $RATER1_CSV"
  exit 1
fi

if [ "$RATER2_CSV" != "---" ] && [ ! -f "$RATER2_CSV" ]; then
  log "ERROR: Rater 2 CSV not found: $RATER2_CSV"
  exit 1
fi

if [ ! -f "$BLINDED_KEY_FILE" ]; then
  log "ERROR: Blind key not found: $BLINDED_KEY_FILE"
  exit 1
fi

log "Unblinding spec scores..."
log "  Rater 1: $RATER1_CSV"
[ "$RATER2_CSV" != "---" ] && log "  Rater 2: $RATER2_CSV"
log "  Blind key: $BLINDED_KEY_FILE"

# ──────────────────────────────────────────────────────────────────────────────
# Initialization
# ──────────────────────────────────────────────────────────────────────────────

# Write header if not exists
if [ ! -f "$SPEC_SCORES_FILE" ]; then
  echo "run_id	spec_quality_final	rater1_score	rater2_score	cohens_kappa	disagreement_flag	notes" > "$SPEC_SCORES_FILE"
fi

temp_unblind=$(mktemp)
trap "rm -f $temp_unblind" EXIT

# ──────────────────────────────────────────────────────────────────────────────
# Load rater scores
# ──────────────────────────────────────────────────────────────────────────────

# Rater 1 scores: anon_id → score
declare -A rater1_scores
while IFS=, read -r anon_id score; do
  anon_id=$(echo "$anon_id" | tr -d ' ')
  score=$(echo "$score" | tr -d ' ')
  rater1_scores["$anon_id"]="$score"
done < "$RATER1_CSV"

log "Loaded Rater 1: ${#rater1_scores[@]} scores"

# Rater 2 scores (if provided)
declare -A rater2_scores
if [ "$RATER2_CSV" != "---" ]; then
  while IFS=, read -r anon_id score; do
    anon_id=$(echo "$anon_id" | tr -d ' ')
    score=$(echo "$score" | tr -d ' ')
    rater2_scores["$anon_id"]="$score"
  done < "$RATER2_CSV"
  log "Loaded Rater 2: ${#rater2_scores[@]} scores"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Unblind and reconcile
# ──────────────────────────────────────────────────────────────────────────────

# Use jq to iterate over blind key
have_jq=false
command -v jq &>/dev/null && have_jq=true

if [ "$have_jq" = "true" ]; then
  jq -r 'to_entries[] | "\(.key)\t\(.value.run_id)\t\(.value.method)\t\(.value.task)"' \
    "$BLINDED_KEY_FILE" | while IFS=$'\t' read -r anon_id run_id method task; do

    r1_score="${rater1_scores[$anon_id]:-—}"
    r2_score="${rater2_scores[$anon_id]:-—}"

    # Reconcile: if both raters present, take average; else single score
    if [ "$r1_score" != "—" ] && [ "$r2_score" != "—" ]; then
      final_score=$(( (r1_score + r2_score) / 2 ))
      disagreement=$([ "$r1_score" != "$r2_score" ] && echo "1" || echo "0")
      notes="avg(r1=$r1_score,r2=$r2_score)"
    elif [ "$r1_score" != "—" ]; then
      final_score="$r1_score"
      disagreement="0"
      notes="rater1_only"
    else
      final_score="0"  # Default if neither rater scored
      disagreement="0"
      notes="not_scored"
    fi

    # Append to results (kappa computed below)
    printf '%s\t%s\t%s\t%s\t—\t%s\t%s\n' \
      "$run_id" "$final_score" "$r1_score" "$r2_score" "$disagreement" "$notes" \
      >> "$temp_unblind"
  done
else
  log "WARNING: jq not found; manual unblinding (limited functionality)"
  # Fallback: manual grep on blind key (works for simple JSON)
  grep -oP '"anon_[^"]+": \{[^}]+\}' "$BLINDED_KEY_FILE" | while read -r entry; do
    anon_id=$(echo "$entry" | cut -d'"' -f2)
    # ... manual parsing would go here, but it's fragile
    log "  (Skipping: jq required for robust unblinding)"
  done
fi

# ──────────────────────────────────────────────────────────────────────────────
# Compute Cohen's κ (if dual raters)
# ──────────────────────────────────────────────────────────────────────────────

if [ "$RATER2_CSV" != "---" ] && [ -f "$temp_unblind" ]; then
  log "Computing Cohen's κ for inter-rater reliability..."

  # Simple κ: (P_o - P_e) / (1 - P_e)
  # where P_o = agreement rate, P_e = expected agreement by chance
  # For 0/1/2 scores on n pairs:

  kappa=$(awk '
    NR==1 { next }  # skip header
    {
      r1=$3; r2=$4
      if (r1==r2) agree++
      n++
    }
    END {
      if (n>0) {
        p_o = agree / n
        # Rough P_e: uniform distribution (0,1,2 equally likely)
        p_e = 1/3 * 1/3 * 3  # = 1/3 for 0/1/2
        kappa = (p_o - p_e) / (1 - p_e)
        printf "%.3f", kappa
      } else {
        print "—"
      }
    }
  ' "$temp_unblind")

  log "  Cohen's κ: $kappa"

  # Insert kappa into each row of temp_unblind
  awk -v kappa="$kappa" '{
    $5 = kappa
    print
  }' "$temp_unblind" > "$temp_unblind.kappa"
  mv "$temp_unblind.kappa" "$temp_unblind"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Append to canonical spec-scores.tsv
# ──────────────────────────────────────────────────────────────────────────────

if [ -f "$temp_unblind" ]; then
  tail -n +2 "$SPEC_SCORES_FILE" > "$SPEC_SCORES_FILE.tmp"
  {
    head -1 "$SPEC_SCORES_FILE"
    sort -u -k1,1 "$temp_unblind" "$SPEC_SCORES_FILE.tmp" | sort -k1,1
  } > "$SPEC_SCORES_FILE.new"
  mv "$SPEC_SCORES_FILE.new" "$SPEC_SCORES_FILE"
  rm -f "$SPEC_SCORES_FILE.tmp"
fi

log "Spec scores written: $SPEC_SCORES_FILE"
log ""
log "Disagreements (rater1 ≠ rater2):"
awk '$6=="1"' "$SPEC_SCORES_FILE" | wc -l | sed 's/^/  /'
log ""
log "Next: Use spec_quality values from $SPEC_SCORES_FILE in your log_run.sh calls."
