#!/usr/bin/env bash
# blind-specs.sh — Anonymize spec artifacts before human scoring.
#
# This script:
#  1. Finds all spec files (.md not in baseline) in a task directory
#  2. Renames them to anonymized IDs (UUIDs)
#  3. Creates a blind key JSON mapping: { anon_id → { run_id, method, task } }
#  4. Stores anonymized files in BLINDED_SPECS_DIR for independent scoring
#
# Usage:
#   bash runs/blind-specs.sh <TASK_DIR> <RUN_ID> <METHOD> <TASK>
#
# Args:
#   TASK_DIR   Path to the completed task directory (e.g., /tmp/sabr_runs/xyz/E)
#   RUN_ID     Unique run identifier (e.g., "20260519_gsd_1_E")
#   METHOD     Methodology name (e.g., "gsd")
#   TASK       Task letter (e.g., "E")
#
# Output:
#   Anonymized spec files → BLINDED_SPECS_DIR/
#   Blind key entry appended → BLINDED_KEY_FILE

set -euo pipefail

# Source config for paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/runs/config.sh"

log() {
  echo "[blind-specs]" "$@" >&2
}

# ──────────────────────────────────────────────────────────────────────────────
# Parse arguments
# ──────────────────────────────────────────────────────────────────────────────

if [ "$#" -lt 4 ]; then
  cat >&2 <<EOF
Usage: bash blind-specs.sh <TASK_DIR> <RUN_ID> <METHOD> <TASK>

Example:
  bash runs/blind-specs.sh /tmp/sabr_runs/20260519_gsd_1_E/E \\
    "20260519_gsd_1_E" "gsd" "E"
EOF
  exit 1
fi

TASK_DIR="$1"
RUN_ID="$2"
METHOD="$3"
TASK="$4"

# ──────────────────────────────────────────────────────────────────────────────
# Validate
# ──────────────────────────────────────────────────────────────────────────────

if [ ! -d "$TASK_DIR" ]; then
  log "ERROR: Task directory not found: $TASK_DIR"
  exit 1
fi

if [ ! -d "${SCRIPT_ROOT}/SANDBOX/${TASK}" ]; then
  log "ERROR: Baseline task dir not found: ${SCRIPT_ROOT}/SANDBOX/${TASK}"
  exit 1
fi

# Ensure blinded specs directory exists
mkdir -p "$BLINDED_SPECS_DIR"

# Ensure blinded key file exists with valid JSON
if [ ! -f "$BLINDED_KEY_FILE" ]; then
  echo "{}" > "$BLINDED_KEY_FILE"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Find new spec files (not in baseline)
# ──────────────────────────────────────────────────────────────────────────────

log "Blinding specs for Run ${RUN_ID} | Method ${METHOD} | Task ${TASK}"

# Get list of baseline spec files
baseline_specs=$(find "${SCRIPT_ROOT}/SANDBOX/${TASK}" -name "*.md" 2>/dev/null | xargs basename -a 2>/dev/null | sort || true)

# Find all .md files in the task dir that aren't in baseline
new_specs=$(
  find "$TASK_DIR" -maxdepth 1 -name "*.md" 2>/dev/null | while read -r f; do
    fname=$(basename "$f")
    if ! echo "$baseline_specs" | grep -q "^${fname}$"; then
      echo "$f"
    fi
  done
)

if [ -z "$new_specs" ]; then
  log "  No new spec files found (spec_quality will be 0)"
  exit 0
fi

# ──────────────────────────────────────────────────────────────────────────────
# Anonymize and update blind key
# ──────────────────────────────────────────────────────────────────────────────

# Use jq if available, else fall back to manual JSON editing
have_jq=false
command -v jq &>/dev/null && have_jq=true

while IFS= read -r spec_file; do
  if [ -z "$spec_file" ]; then
    continue
  fi

  # Generate anonymized filename (UUID-like, but simpler: hash of file content)
  anon_id=$(sha256sum "$spec_file" | cut -c1-12)
  anon_filename="${BLINDED_SPECS_DIR}/anon_${anon_id}.md"

  # Copy to blinded directory
  cp "$spec_file" "$anon_filename"
  log "  Anonymized: $(basename "$spec_file") → anon_${anon_id}.md"

  # Update blind key with jq if available
  if [ "$have_jq" = "true" ]; then
    jq --arg key "anon_${anon_id}" \
       --arg run_id "$RUN_ID" \
       --arg method "$METHOD" \
       --arg task "$TASK" \
       '.[$key] = {run_id: $run_id, method: $method, task: $task}' \
       "$BLINDED_KEY_FILE" > "$BLINDED_KEY_FILE.tmp" && \
      mv "$BLINDED_KEY_FILE.tmp" "$BLINDED_KEY_FILE"
  else
    # Fallback: manual JSON append (simple, but less robust for complex JSON)
    # For now, just log it; production should use jq
    log "  (jq not found; manually update $BLINDED_KEY_FILE if needed)"
  fi

done <<< "$new_specs"

log "  done. Key file: $BLINDED_KEY_FILE"
log ""
log "Next step: Have independent raters score the anonymized files in:"
log "  $BLINDED_SPECS_DIR"
log "Then: bash runs/unblind-specs.sh <RATER_1_CSV> <RATER_2_CSV>"
