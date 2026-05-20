# Task E: Element Filter API

**Type:** Greenfield  
**Tier:** Quick (~2–3 min)  
**Dimension:** Pure implementation speed on a well-defined spec

## The Problem

`server.js` has route stubs that return no data. The `elements` array is never loaded
and all endpoints return empty/404 responses.

## What to Fix

1. Load `data/elements.json` at startup
2. `GET /elements` — return all elements
3. `GET /elements?category=X` — filter by category (case-insensitive)
4. `GET /elements/:symbol` — return element or 404

## Response shape

```json
{ "symbol": "H", "name": "Hydrogen", "atomicNumber": 1, "atomicMass": 1.008, "category": "nonmetal" }
```

## Test

```bash
node test.js
```

Success = 5 assertions passing.
