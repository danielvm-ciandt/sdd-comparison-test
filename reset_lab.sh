#!/usr/bin/env bash
# reset_lab.sh — Reset one or all task sandboxes (A–J) to their immutable baselines.
#
# Usage:
#   bash reset_lab.sh          # reset all tasks A–J
#   bash reset_lab.sh E        # reset only Task E
#   bash reset_lab.sh A B C    # reset specific tasks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX_DIR="${SCRIPT_DIR}/SANDBOX"

reset_task() {
  local letter
  letter=$(echo "$1" | tr '[:lower:]' '[:upper:]')
  local dest="${SCRIPT_DIR}/${letter}"
  local src="${SANDBOX_DIR}/${letter}"

  if [ ! -d "$src" ]; then
    echo "ERROR: No baseline found for Task ${letter} at ${src}" >&2
    exit 1
  fi

  echo "  Task ${letter}..."
  # rsync --delete will preserve node_modules since they exist in SANDBOX
  rsync -a --delete "${src}/" "${dest}/"

  # Remove agent-produced spec artifacts but keep immutable spec files
  if [ -d "${dest}/specs" ]; then
    find "${dest}/specs" -type f \
      ! -name "FEATURE_REQUEST.md" ! -name "MIGRATION_REQUEST.md" \
      -delete 2>/dev/null || true
  fi

  # DO NOT delete node_modules or package-lock.json
  # They are installed in SANDBOX and preserved by rsync --delete
  # This saves 10-60s per run on npm install
  echo "    done"
}

ALL_TASKS=(A B C D E F G H I J)

if [ "$#" -eq 0 ]; then
  echo "=== Resetting all tasks (A–J) to baseline ==="
  for t in "${ALL_TASKS[@]}"; do
    reset_task "$t"
  done
else
  echo "=== Resetting task(s): $* ==="
  for t in "$@"; do
    reset_task "$t"
  done
fi

echo "=== Reset complete ==="
