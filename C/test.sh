#!/usr/bin/env bash
# test.sh — SABR Task C: God-Script Refactoring Tests
#
# Checks that the refactored backup.sh meets the structural requirements.
# Does NOT actually run backups (no real DB/S3/Slack needed).
#
# Exit 0: all checks pass
# Exit 1: one or more checks fail

set -euo pipefail

SCRIPT="$(dirname "$0")/backup.sh"
PASS=0
FAIL=0

ok()   { echo "  ✓ $1"; ((PASS++)); }
fail() { echo "  ✗ $1"; ((FAIL++)); }

echo "SABR Task C — God-Script Refactoring Checks"
echo ""

# ── 1. Script must pass bash -n (syntax check) ───────────────────────────
echo "[ Syntax ]"
if bash -n "$SCRIPT" 2>/dev/null; then
  ok "bash -n passes (no syntax errors)"
else
  fail "bash -n failed — script has syntax errors"
fi

# ── 2. shellcheck (if available) ─────────────────────────────────────────
echo ""
echo "[ shellcheck ]"
if command -v shellcheck &>/dev/null; then
  if shellcheck "$SCRIPT" 2>/dev/null; then
    ok "shellcheck: no warnings"
  else
    WARNINGS=$(shellcheck "$SCRIPT" 2>&1 | wc -l)
    fail "shellcheck: $WARNINGS warning lines (must be 0)"
  fi
else
  echo "  - shellcheck not installed, skipping"
fi

# ── 3. Functions must exist (Stepdown Rule) ───────────────────────────────
echo ""
echo "[ Functions ]"
FUNC_COUNT=$(grep -c '^[a-zA-Z_][a-zA-Z0-9_]*\s*()' "$SCRIPT" || true)
if [ "$FUNC_COUNT" -ge 5 ]; then
  ok "at least 5 functions defined ($FUNC_COUNT found)"
else
  fail "less than 5 functions defined ($FUNC_COUNT found) — Stepdown Rule violated"
fi

# ── 4. No function longer than 20 lines ──────────────────────────────────
echo ""
echo "[ Function Length ]"
MAX_FUNC_LINES=0
CURRENT_FUNC=""
IN_FUNC=0
LINE_COUNT=0
LONG_FUNCS=()

while IFS= read -r line; do
  if [[ "$line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*\(\) ]] || [[ "$line" =~ ^function\ [a-zA-Z_] ]]; then
    IN_FUNC=1
    LINE_COUNT=0
    CURRENT_FUNC=$(echo "$line" | awk '{print $1}')
  fi
  if [ $IN_FUNC -eq 1 ]; then
    ((LINE_COUNT++))
    if [[ "$line" == "}" ]]; then
      if [ $LINE_COUNT -gt 20 ]; then
        LONG_FUNCS+=("$CURRENT_FUNC ($LINE_COUNT lines)")
      fi
      IN_FUNC=0
    fi
  fi
done < "$SCRIPT"

if [ ${#LONG_FUNCS[@]} -eq 0 ]; then
  ok "all functions are ≤ 20 lines"
else
  for f in "${LONG_FUNCS[@]}"; do
    fail "function too long: $f (must be ≤ 20 lines)"
  done
fi

# ── 5. Must have error handling (trap or set -e) ──────────────────────────
echo ""
echo "[ Error Handling ]"
if grep -qE '^(set -e|set -euo|trap )' "$SCRIPT"; then
  ok "error handling found (set -e or trap)"
else
  fail "no error handling — must use 'set -e' or 'trap'"
fi

# ── 6. No hardcoded credentials ───────────────────────────────────────────
echo ""
echo "[ Security ]"
if grep -qE 'AWS_ACCESS_KEY_ID="AKIA|PGPASSWORD="[a-z]+_secret' "$SCRIPT"; then
  fail "hardcoded credentials found — must use environment variables"
else
  ok "no hardcoded credentials"
fi

# ── 7. No duplicate curl patterns (code duplication check) ────────────────
echo ""
echo "[ Duplication ]"
SLACK_CALLS=$(grep -c 'hooks.slack.com' "$SCRIPT" || true)
if [ "$SLACK_CALLS" -le 3 ]; then
  ok "Slack calls not duplicated ($SLACK_CALLS occurrences — should be via a function)"
else
  fail "Slack curl is duplicated $SLACK_CALLS times — extract to a function"
fi

AWS_EXPORTS=$(grep -c 'AWS_ACCESS_KEY_ID=' "$SCRIPT" || true)
if [ "$AWS_EXPORTS" -le 2 ]; then
  ok "AWS credentials not duplicated ($AWS_EXPORTS occurrences)"
else
  fail "AWS_ACCESS_KEY_ID set $AWS_EXPORTS times — use a single export or .env"
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────"
echo "$PASS passed, $FAIL failed"

exit $FAIL
