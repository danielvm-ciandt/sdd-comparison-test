#!/usr/bin/env bash
# prebuild-cache.sh — Install npm dependencies in SANDBOX dirs (one-time setup).
#
# This script runs npm install for each task's SANDBOX and KEEPS node_modules
# in place. Since reset_lab.sh uses rsync --delete to copy SANDBOX → working dir,
# node_modules will be preserved across resets, eliminating npm install per run.
#
# Usage:
#   bash runs/prebuild-cache.sh
#
# Output:
#   SANDBOX/<TASK>/node_modules/ (kept in place)
#   SANDBOX/<TASK>/package-lock.json (kept in place)
#
# Time: ~5–10 min (first-time npm installs)
# Benefit: Each run saves 10–60s of npm install time (npm cache is warm)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX_DIR="${SCRIPT_DIR}/SANDBOX"
ALL_TASKS=(A B C D E F G H I J)

log() {
  echo "[prebuild-cache]" "$@" >&2
}

log "Installing npm dependencies in SANDBOX dirs..."
log "Sandbox: $SANDBOX_DIR"
echo ""

for task in "${ALL_TASKS[@]}"; do
  task_dir="${SANDBOX_DIR}/${task}"

  if [ ! -d "$task_dir" ]; then
    log "Task ${task}: not found, skipping"
    continue
  fi

  # Skip if no package.json
  if [ ! -f "${task_dir}/package.json" ]; then
    log "Task ${task}: no package.json, skipping"
    continue
  fi

  log "Task ${task}: running npm install in SANDBOX..."
  (
    cd "$task_dir"
    npm install --silent --legacy-peer-deps 2>&1 | grep -E "(added|up to date|warn)" || true
  )

  # Verify install succeeded
  if [ ! -d "${task_dir}/node_modules" ]; then
    log "Task ${task}: npm install failed, skipping"
    continue
  fi

  log "Task ${task}: ✓ node_modules installed (will persist across resets via rsync)"
  echo ""
done

log "Prebuild complete."
log "Node modules installed: $(find "$SANDBOX_DIR" -maxdepth 2 -name node_modules -type d | wc -l) tasks"
log ""
log "Important: Do NOT delete SANDBOX/*/node_modules or package-lock.json"
log "They will be preserved by reset_lab.sh --delete and speed up every run."
