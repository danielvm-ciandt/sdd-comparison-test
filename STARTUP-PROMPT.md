# SABR Room 3 — Startup Prompt

## What Changed from Room 2

- All 10 tasks (A–J) are now in scope. Tasks A–D are in `SANDBOX/A`–`SANDBOX/D`.
- `wall_time_sec` is gone. Record `start_time` and `end_time` in ISO-8601 with
  timezone offset. `cycle_time_sec` is computed automatically — never enter it manually.
- `runs/log_run.sh` handles the append + computation.
- `runs/parse-results.sh` reports lean metrics (avg cycle, P50/P95, throughput).

---

## Pre-Flight Checklist

```bash
# Verify all 10 task sandboxes exist
ls /Users/danielvm/Projects/hermes-agent/sabr-extended/SANDBOX/
# Expected: A B C D E F G H I J

# Verify all 10 live task dirs exist
ls /Users/danielvm/Projects/hermes-agent/sabr-extended/
# Expected: A B C D E F G H I J README.md reset_lab.sh runs SANDBOX STARTUP-PROMPT.md

# Make scripts executable
chmod +x /Users/danielvm/Projects/hermes-agent/sabr-extended/reset_lab.sh
chmod +x /Users/danielvm/Projects/hermes-agent/sabr-extended/runs/log_run.sh
chmod +x /Users/danielvm/Projects/hermes-agent/sabr-extended/runs/parse-results.sh

# Verify results file has header only (0 data rows)
wc -l /Users/danielvm/Projects/hermes-agent/sabr-extended/runs/results.tsv
```

---

## Per-Run Workflow

### Step 1: Reset the task

```bash
bash /Users/danielvm/Projects/hermes-agent/sabr-extended/reset_lab.sh <TASK>
# e.g.: bash reset_lab.sh E
```

### Step 2: Record start time — BEFORE sending prompt to agent

```bash
START=$(date +"%Y-%m-%dT%H:%M:%S%z" | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/')
echo "START: $START"
```

Copy the printed value. Example: `2026-05-24T14:30:00-03:00`

### Step 3: Load methodology context and send task prompt

Sandbox path: `/Users/danielvm/Projects/hermes-agent/sabr-extended/<TASK>/`

Replace `${METHOD}`, `${TASK}`, `${RUN}` with actual values before sending.

### Step 4: Run tests when agent signals completion

```bash
cd /Users/danielvm/Projects/hermes-agent/sabr-extended/<TASK>

# Tasks A, D, E, G:
node test.js

# Tasks B, F, H, I, J:
npm install --silent && npm test

# Task C:
bash test.sh
```

### Step 5: Record end time — AFTER test suite exits

```bash
END=$(date +"%Y-%m-%dT%H:%M:%S%z" | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/')
echo "END: $END"
```

### Step 6: Score spec_quality and count artifacts

**spec_quality:**
- `0` = no spec or plan document written
- `1` = bullet notes or rough plan
- `2` = structured document resolving all ambiguities/contradictions

**artifacts_produced** (new .md files vs baseline):
```bash
diff <(ls /Users/danielvm/Projects/hermes-agent/sabr-extended/SANDBOX/<TASK>/) \
     <(ls /Users/danielvm/Projects/hermes-agent/sabr-extended/<TASK>/) \
  | grep '^>' | grep -c '\.md' || true
```

### Step 7: Log the run

```bash
bash /Users/danielvm/Projects/hermes-agent/sabr-extended/runs/log_run.sh \
  <RUN> <METHOD> <TASK> \
  "<START_ISO>" "<END_ISO>" \
  <PASS> <FAIL> <STATUS> \
  [ERROR_TYPE] [SPEC_QUALITY] [ARTIFACTS] [TOKENS] \
  [FIRST_CODE_SEC] [SPEC_BEFORE_CODE] [REWORK_COUNT] [FILES_TOUCHED] [CONTRADICTION_FOUND] \
  "<NOTES>"
```

**Observability fields:**
- `FIRST_CODE_SEC` — seconds from start until first file edit (planning tax)
- `SPEC_BEFORE_CODE` — `1` if any spec/plan doc written before first code file, else `0`
- `REWORK_COUNT` — times the agent edited a file it had already written
- `FILES_TOUCHED` — count of distinct files modified
- `CONTRADICTION_FOUND` — `1` if agent explicitly caught a spec ambiguity before coding, else `0`

Example:
```bash
bash /Users/danielvm/Projects/hermes-agent/sabr-extended/runs/log_run.sh \
  1 gsd E \
  "2026-05-24T14:30:00-03:00" "2026-05-24T14:31:45-03:00" \
  5 0 PASS \
  — 0 0 3200 \
  12 0 1 2 0 \
  "clean greenfield, direct impl, no spec"
```

### Step 8: Append qualitative observation to execution-log.md

---

## Timing Quick Reference

```bash
# Before sending prompt:
START=$(date +"%Y-%m-%dT%H:%M:%S%z" | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/')

# After tests complete:
END=$(date +"%Y-%m-%dT%H:%M:%S%z" | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/')

# cycle_time_sec is computed by log_run.sh — never enter it manually
```

Format: `2026-05-24T14:30:00-03:00` (ISO-8601 with TZ offset)

---

## Task Prompts

### Task A: Leaky Proxy

> Fix the socket leak in `server.js` (proxy).
>
> **Sandbox:** `sabr-extended/A/`
>
> - Add request timeout (5s)
> - Destroy socket on upstream error
> - Abort on client disconnect
> - Add socket timeout (10s)
> - Clean up listeners on request end
>
> **Success:** `node test.js` → 3 assertions passing

### Task B: Soft-Delete

> Implement soft-delete on the User model.
>
> **Sandbox:** `sabr-extended/B/`
>
> - `DELETE /users/:id` sets `deletedAt` instead of removing the row
> - `GET /users` returns only non-deleted users
> - `GET /users/:id` returns 404 for deleted users
>
> **Success:** `npm test` → 15+ assertions passing

### Task C: God-Script Refactor

> Refactor the 300-line `backup.sh` spaghetti script.
>
> **Sandbox:** `sabr-extended/C/`
>
> - Extract duplicate logic into reusable functions
> - Add error handling
> - Preserve all original behaviour
>
> **Success:** `bash test.sh` → 8+ assertions passing

### Task D: Billing Slice

> You are implementing subscriptions and invoicing for a SaaS backend.
>
> **Sandbox:** `sabr-extended/D/`
>
> **Read the spec:** `cat sabr-extended/D/specs/FEATURE_REQUEST.md`
>
> The spec is intentionally vague. **Resolve all ambiguities before writing any code.**
>
> **Success:** `node test.js` → all billing assertions passing + spec_quality ≥ 1

### Task E: Element Filter API

> Implement a complete Element Filter API from a finished spec.
>
> **Sandbox:** `sabr-extended/E/`
>
> - `GET /elements` — all elements
> - `GET /elements?category=X` — filter by category (case-insensitive)
> - `GET /elements/:symbol` — single element or 404
>
> **Response shape per element:** `{ symbol, name, atomicNumber, atomicMass, category }`
>
> **Success:** `node test.js` → 5 assertions passing

### Task F: Todo Auth Slice

> Add authentication to a working Todo API.
>
> **Sandbox:** `sabr-extended/F/`
>
> **Read the spec:** `cat sabr-extended/F/FEATURE_REQUEST.md`
>
> The spec is intentionally incomplete. **Resolve all ambiguities before writing any code.**
>
> **Success:** `npm test` → 8 assertions passing + at least a partial spec document

### Task G: Music Store Schema Design

> Extend a Music Store API with play history and recommendations.
>
> **Sandbox:** `sabr-extended/G/`
>
> **Read the spec:** `cat sabr-extended/G/FEATURE_REQUEST.md`
>
> **Design and document the schema before writing any endpoint code.**
>
> **Success:** `node test.js` → 10 assertions passing + at least one schema/design document

### Task H: Chat Presence Feature

> Add online presence to a working Chat API.
>
> **Sandbox:** `sabr-extended/H/`
>
> A user is "online" if they have made any API request in the last 60 seconds.
> The `online` field must appear consistently in `GET /users`, `GET /users/:id`,
> and the `participants` array in `GET /conversations/:id`.
>
> **Success:** `npm test` → 12 assertions passing

### Task I: Project Tracker Dependency Slice

> Implement task dependencies in a Project Management API.
>
> **Sandbox:** `sabr-extended/I/`
>
> **Read the spec:** `cat sabr-extended/I/FEATURE_REQUEST.md`
>
> The spec contains a contradiction. **Find it, resolve it explicitly in a spec
> document, then implement.**
>
> **Success:** `npm test` → 15 assertions passing + spec_quality = 2

### Task J: Banking Currency Migration

> Add multi-currency support to a Banking API without breaking existing clients.
>
> **Sandbox:** `sabr-extended/J/`
>
> **Read the migration brief:** `cat sabr-extended/J/MIGRATION_REQUEST.md`
>
> **Produce a migration strategy document before writing any code.**
> Existing clients must continue working without modification.
>
> **Success:** `npm test` → 18 assertions passing + migration script exists

---

## Run Matrix

```
For RUN in 1..5:
  For METHOD in [bigpowers, superpowers, bmad, spec-kit, acps, gsd]:
    For TASK in [A, B, C, D, E, F, G, H, I, J]:
      Execute 1 run (Steps 1–8 above)

Total: 6 × 10 × 5 = 300 runs
```
