# Task H: Chat Presence Feature

**Type:** Brownfield (extend across multiple endpoints)  
**Tier:** Medium (~5–8 min)  
**Dimension:** Cross-endpoint consistency

## The Problem

`server.js` has a working chat API but no online presence. The `online` field
is missing from three places: `GET /users`, `GET /users/:id`, and the
`participants` array in `GET /conversations/:id`. All three must be consistent.

## Definition

A user is **online** if they have made any API request in the last 60 seconds.

## What to Add

- Presence tracking middleware or per-request timestamp update
- `online: boolean` field in all three response shapes

## Test

```bash
npm install && npm test
```

Success = 12 assertions passing.
