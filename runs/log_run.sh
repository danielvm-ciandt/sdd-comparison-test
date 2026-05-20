#!/usr/bin/env bash
# log_run.sh — Append one run to results.tsv with computed cycle_time_sec.
#
# Usage (v2 with RUN_ID):
#   bash log_run.sh <RUN> <METHOD> <TASK> <RUN_ID> <START_ISO> <END_ISO> \
#                   <PASS> <FAIL> <STATUS> [ERROR_TYPE] [SPEC_QUALITY] \
#                   [ARTIFACTS] [TOKENS] [FIRST_CODE_SEC] [SPEC_BEFORE_CODE] \
#                   [REWORK_COUNT] [FILES_TOUCHED] [CONTRADICTION_FOUND] [NOTES]
#
# Usage (backward compatible, without RUN_ID):
#   bash log_run.sh <RUN> <METHOD> <TASK> <START_ISO> <END_ISO> \
#                   <PASS> <FAIL> <STATUS> [ERROR_TYPE] [SPEC_QUALITY] ...
#
# Timestamps must be ISO-8601 with timezone offset, e.g.:
#   2026-05-24T14:30:00-03:00
#
# Observability columns:
#   FIRST_CODE_SEC      seconds from start until first file edit (planning tax)
#   SPEC_BEFORE_CODE    1 if any spec/plan doc was written before first code file, else 0
#   REWORK_COUNT        number of times the agent edited a file it had already written
#   FILES_TOUCHED       count of distinct files modified during the run
#   CONTRADICTION_FOUND 1 if agent explicitly identified a spec ambiguity/contradiction, else 0
#
# Example (v2):
#   bash log_run.sh 1 gsd E "20260519_gsd_1_E" \
#     "2026-05-24T14:30:00-03:00" "2026-05-24T14:31:45-03:00" \
#     5 0 PASS — 0 0 3200 \
#     12 0 1 2 0 \
#     "clean greenfield, direct impl"

set -euo pipefail

RESULTS_FILE="$(dirname "$0")/results.tsv"

RUN="${1:?missing RUN}"
METHOD="${2:?missing METHOD}"
TASK="${3:?missing TASK}"

# Support v2 (with RUN_ID) and backward compat (without)
# If arg 4 looks like ISO timestamp (contains 'T'), it's old format; else it's RUN_ID
if [[ "${4:-}" =~ T.*[+-][0-9]{2}:[0-9]{2}$ ]]; then
  # Old format: no RUN_ID
  RUN_ID="${TASK}_run${RUN}_$(date +%s)"  # generate pseudo-ID
  START_ISO="$4"
  END_ISO="${5:?missing END_ISO}"
  PASS="${6:?missing PASS}"
  FAIL="${7:?missing FAIL}"
  STATUS="${8:?missing STATUS (PASS|ERROR)}"
  ERROR_TYPE="${9:----}"
  SPEC_QUALITY="${10:-0}"
  ARTIFACTS="${11:-0}"
  TOKENS="${12:-0}"
  FIRST_CODE_SEC="${13:-0}"
  SPEC_BEFORE_CODE="${14:-0}"
  REWORK_COUNT="${15:-0}"
  FILES_TOUCHED="${16:-0}"
  CONTRADICTION_FOUND="${17:-0}"
  NOTES="${18:----}"
else
  # v2 format: with RUN_ID
  RUN_ID="${4:?missing RUN_ID}"
  START_ISO="${5:?missing START_ISO (e.g. 2026-05-24T14:30:00-03:00)}"
  END_ISO="${6:?missing END_ISO}"
  PASS="${7:?missing PASS}"
  FAIL="${8:?missing FAIL}"
  STATUS="${9:?missing STATUS (PASS|ERROR)}"
  ERROR_TYPE="${10:----}"
  SPEC_QUALITY="${11:-0}"
  ARTIFACTS="${12:-0}"
  TOKENS="${13:-0}"
  FIRST_CODE_SEC="${14:-0}"
  SPEC_BEFORE_CODE="${15:-0}"
  REWORK_COUNT="${16:-0}"
  FILES_TOUCHED="${17:-0}"
  CONTRADICTION_FOUND="${18:-0}"
  NOTES="${19:----}"
fi

iso_to_epoch() {
  local ts="$1"
  if date --version >/dev/null 2>&1; then
    date -d "$ts" +%s
  else
    local clean
    clean=$(echo "$ts" | sed 's/\([+-][0-9][0-9]\):\([0-9][0-9]\)$/\1\2/')
    date -j -f "%Y-%m-%dT%H:%M:%S%z" "$clean" +%s
  fi
}

START_EPOCH=$(iso_to_epoch "$START_ISO")
END_EPOCH=$(iso_to_epoch "$END_ISO")
CYCLE=$(( END_EPOCH - START_EPOCH ))

if [ "$CYCLE" -lt 0 ]; then
  echo "ERROR: end_time is before start_time" >&2
  exit 1
fi

printf '%s\t%s\t%s\t%s\t%s\t%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$RUN" "$METHOD" "$TASK" "$RUN_ID" \
  "$START_ISO" "$END_ISO" "$CYCLE" \
  "$PASS" "$FAIL" "$STATUS" "$ERROR_TYPE" \
  "$SPEC_QUALITY" "$ARTIFACTS" "$TOKENS" \
  "$FIRST_CODE_SEC" "$SPEC_BEFORE_CODE" "$REWORK_COUNT" "$FILES_TOUCHED" "$CONTRADICTION_FOUND" \
  "$NOTES" \
  >> "$RESULTS_FILE"

echo "Logged: RUN_ID=${RUN_ID} | cycle=${CYCLE}s | tokens=$TOKENS | first_code=${FIRST_CODE_SEC}s | spec_before=${SPEC_BEFORE_CODE} | $STATUS ($PASS pass, $FAIL fail)"
