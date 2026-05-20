# Task I: Project Tracker Dependency Slice

**Type:** Brownfield (complex feature, adversarial spec)  
**Tier:** Heavy (~10–15 min)  
**Dimension:** Vague spec with planted contradiction

## The Problem

`server.js` has a working project/task/team API but no dependency tracking.
`FEATURE_REQUEST.md` describes dependencies but contains a contradiction:
it says blocked tasks cannot start, then says they can be marked in-progress
before deps complete.

## What to Do

1. Read `FEATURE_REQUEST.md` carefully
2. **Find the contradiction**
3. **Resolve it explicitly in a spec document** (spec_quality = 2 required)
4. Implement task dependencies with the resolved behavior

## The resolution

The expected resolution is a `force: true` flag on `PATCH /tasks/:id` that
allows bypassing the blocked-task guard for planning purposes. This must be
documented in your spec before coding.

## Test

```bash
npm install && npm test
```

Success = 15 assertions passing + `spec_quality = 2`.
