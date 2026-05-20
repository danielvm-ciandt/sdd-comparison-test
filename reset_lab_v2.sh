#!/usr/bin/env bash
# reset_lab_v2.sh — Create isolated git worktree per run for process isolation.
#
# Usage:
#   bash reset_lab_v2.sh <TASK> <RUN_ID> [METHOD]
#
# Args:
#   TASK       Task letter (A–J)
#   RUN_ID     Unique run identifier (e.g., "20260519_gsd_1_A")
#   METHOD     (Optional) Methodology name, for logging
#
# Returns:
#   Prints the path to the isolated worktree on stdout.
#   All other info goes to stderr.
#
# Behavior:
#   1. Creates a fresh git worktree at WORKTREE_ROOT/<RUN_ID>
#   2. Copies SANDBOX/<TASK> into the worktree
#   3. Untars npm cache if .npm-cache.tar.gz exists
#   4. Cleans up on EXIT signal (if trap is set by caller) or manually via cleanup_worktree()
#
# Example:
#   WTREE=$(bash reset_lab_v2.sh E "20260519_gsd_1_E" gsd)
#   cd "$WTREE/E"
#   # ... agent runs in this isolated dir ...
#   # cleanup happens automatically or via: bash reset_lab_v2.sh --cleanup "$WTREE"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX_DIR="${SCRIPT_DIR}/SANDBOX"
WORKTREE_ROOT="${WORKTREE_ROOT:-/tmp/sabr_runs}"

# Ensure WORKTREE_ROOT exists
mkdir -p "$WORKTREE_ROOT"

# ──────────────────────────────────────────────────────────────────────────────
# Functions
# ──────────────────────────────────────────────────────────────────────────────

log_err() {
  echo "[reset_lab_v2]" "$@" >&2
}

cleanup_worktree() {
  local wtree="$1"
  if [ -d "$wtree" ]; then
    log_err "Cleaning up worktree: $wtree"
    git -C "$SCRIPT_DIR" worktree remove -f "$wtree" 2>/dev/null || true
    rm -rf "$wtree" 2>/dev/null || true
  fi
}

create_worktree() {
  local task="$1"
  local run_id="$2"
  local method="${3:---}"

  # Normalize task to uppercase
  task=$(echo "$task" | tr '[:lower:]' '[:upper:]')

  # Validate task
  local sandbox_task="${SANDBOX_DIR}/${task}"
  if [ ! -d "$sandbox_task" ]; then
    log_err "ERROR: No baseline found for Task ${task} at ${sandbox_task}"
    exit 1
  fi

  # Create worktree
  local wtree_path="${WORKTREE_ROOT}/${run_id}"

  # Clean up any stale worktree
  if [ -d "$wtree_path" ]; then
    cleanup_worktree "$wtree_path"
  fi

  log_err "Creating worktree for Task ${task} | RUN: ${run_id} | METHOD: ${method}"

  # Create a fresh worktree from the repo root (detached HEAD is fine for our purposes)
  git -C "$SCRIPT_DIR" worktree add --detach "$wtree_path" HEAD 2>/dev/null || {
    log_err "Failed to create worktree. Cleaning stale entries and retrying..."
    git -C "$SCRIPT_DIR" worktree prune
    git -C "$SCRIPT_DIR" worktree add --detach "$wtree_path" HEAD 2>/dev/null
  }

  # Clear the worktree of all content except .git
  log_err "  Clearing worktree..."
  find "$wtree_path" -maxdepth 1 ! -name ".git" -type f -delete
  find "$wtree_path" -maxdepth 1 ! -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

  # Copy the task sandbox into the worktree
  # rsync --delete preserves node_modules since they exist in SANDBOX
  log_err "  Copying SANDBOX/${task} → worktree (preserving node_modules)..."
  mkdir -p "$wtree_path/${task}"
  rsync -a --delete "${sandbox_task}/" "${wtree_path}/${task}/"

  # Verify node_modules copied successfully
  if [ ! -d "${wtree_path}/${task}/node_modules" ] && [ -f "${sandbox_task}/package.json" ]; then
    log_err "  Warning: node_modules not found; npm install will run during trial"
  else
    log_err "  ✓ node_modules preserved (npm install not needed)"
  fi

  # Clean up spec artifacts (keep only baseline specs)
  if [ -d "${wtree_path}/${task}/specs" ]; then
    log_err "  Cleaning spec artifacts..."
    find "${wtree_path}/${task}/specs" -type f \
      ! -name "FEATURE_REQUEST.md" ! -name "MIGRATION_REQUEST.md" \
      -delete 2>/dev/null || true
  fi

  log_err "  done. Worktree: $wtree_path"

  # Print the worktree path to stdout (this is the return value)
  echo "$wtree_path"
}

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

if [ "$#" -eq 0 ]; then
  cat >&2 <<EOF
Usage:
  bash reset_lab_v2.sh <TASK> <RUN_ID> [METHOD]
  bash reset_lab_v2.sh --cleanup <WTREE_PATH>

Args:
  TASK        Task letter (A–J)
  RUN_ID      Unique identifier (e.g., "20260519_gsd_1_E")
  METHOD      Optional methodology name for logging
  WTREE_PATH  Path to worktree to clean up (for --cleanup mode)
EOF
  exit 1
fi

if [ "$1" = "--cleanup" ] && [ "$#" -ge 2 ]; then
  cleanup_worktree "$2"
else
  create_worktree "$1" "$2" "${3:----}"
fi
