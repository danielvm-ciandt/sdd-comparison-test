# Task G: Music Store Schema Design

**Type:** Brownfield (extend existing API)  
**Tier:** Medium (~5–8 min)  
**Dimension:** Architecture decision — schema must be designed before coding

## The Problem

`server.js` serves artists, albums, and songs but has no play history or
recommendations. `FEATURE_REQUEST.md` describes what users want but gives
no schema, no endpoint contract, and no algorithm definition.

## What to Build

Read `FEATURE_REQUEST.md`. Design the schema for play history first (document it),
then implement:
- `POST /plays` — record that a user played a song
- `GET /plays?userId=X` — return play history, newest first
- `GET /recommendations?userId=X` — return unplayed songs

## Test

```bash
node test.js
```

Success = 10 assertions passing + at least one schema/design document created.
