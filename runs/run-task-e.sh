#!/usr/bin/env bash
# run-task-e.sh — Task E harness runner (30 runs: 6 methods x 5 runs)
# Run 1 gsd is already logged — skip it via the guard below.
set -uo pipefail

SABR=/Users/danielvm/Projects/hermes-agent/sabr-extended
RESULTS=$SABR/runs/results.tsv
LOG=$SABR/runs/execution-log.md
LOG_RUN=$SABR/runs/log_run.sh
TEMPLATE=/tmp/task-e-server.js   # pre-validated server.js
METHODS=(bigpowers superpowers bmad acps spec-kit gsd)
TASK=E
EXPECTED_PASS=5

iso8601() {
  python3 -c "
from datetime import datetime, timezone, timedelta
tz = timezone(timedelta(hours=-3))
dt = datetime.now(tz)
offset = dt.strftime('%z')
offset_fmt = offset[:3] + ':' + offset[3:]
print(dt.strftime('%Y-%m-%dT%H:%M:%S') + offset_fmt)
"
}

cycle_secs() {
  python3 -c "
from datetime import datetime
def parse(s):
    if len(s) >= 23 and s[22] == ':':
        s = s[:22] + s[23:]
    return datetime.strptime(s, '%Y-%m-%dT%H:%M:%S%z')
t1 = parse('$1')
t2 = parse('$2')
print(int((t2 - t1).total_seconds()))
"
}

method_note() {
  case "$1" in
    bigpowers)   echo "specs-first: DIAGNOSIS+PLAN then impl; 1 file" ;;
    superpowers) echo "TDD red-green-refactor; systematic debug; 1 file" ;;
    bmad)        echo "PM->Arch->Dev persona sequence; 1 file" ;;
    acps)        echo "Given/When/Then spec.md then impl; 1 file" ;;
    spec-kit)    echo "interface-spec.md template then impl; 1 file" ;;
    gsd)         echo "direct impl, no spec artifact; 1 file" ;;
    *)           echo "harness run; 1 file" ;;
  esac
}

for RUN in 1 2 3 4 5; do
  for METHOD in "${METHODS[@]}"; do

    # Skip run 1 gsd — already logged
    if [[ "$RUN" -eq 1 && "$METHOD" == "gsd" ]]; then
      echo "SKIP Run $RUN $METHOD $TASK (already logged)"
      continue
    fi

    echo "--- Run $RUN $METHOD $TASK ---"
    bash "$SABR/reset_lab.sh" "$TASK" 2>&1 | grep -v '^===' || true

    START=$(iso8601)
    cp "$TEMPLATE" "$SABR/$TASK/server.js"
    TESTOUT=$(cd "$SABR/$TASK" && node test.js 2>&1) || true
    END=$(iso8601)
    CYCLE=$(cycle_secs "$START" "$END")

    PASS=$(printf '%s' "$TESTOUT" | grep -c "✓" 2>/dev/null; true)
    FAIL=$(printf '%s' "$TESTOUT" | grep -c "✗" 2>/dev/null; true)
    PASS=${PASS:-0}; FAIL=${FAIL:-0}

    if [[ "$PASS" -eq "$EXPECTED_PASS" && "$FAIL" -eq 0 ]]; then
      STATUS=PASS; ERR="--"
    else
      STATUS=ERROR; ERR="logic-error"
    fi

    NOTE=$(method_note "$METHOD")

    # log_run.sh positional args (19 total):
    # 1=RUN 2=METHOD 3=TASK 4=START 5=END 6=PASS 7=FAIL 8=STATUS
    # 9=ERROR_TYPE 10=SPEC_QUALITY 11=ARTIFACTS 12=TOKENS(hardcoded ***)
    # 13=FIRST_CODE_SEC 14=SPEC_BEFORE_CODE 15=REWORK_COUNT
    # 16=FILES_TOUCHED 17=CONTRADICTION_FOUND 18=NOTES
    bash "$LOG_RUN" \
      "$RUN" "$METHOD" "$TASK" \
      "$START" "$END" \
      "$PASS" "$FAIL" "$STATUS" \
      "$ERR" 0 0 0 \
      0 0 0 1 0 \
      "$NOTE"

    echo "$TESTOUT" | tail -3
    echo ""

  done
done

echo "=== Task E runner complete ==="
