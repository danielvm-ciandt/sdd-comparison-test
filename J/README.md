# Task J: Banking Currency Migration

**Type:** Brownfield at scale (schema migration + backwards compat)  
**Tier:** Heavy (~10–15 min)  
**Dimension:** Safe migration without breaking existing clients

## The Problem

`server.js` has a working banking API but no currency support. All accounts are
implicitly USD. `MIGRATION_REQUEST.md` requires adding multi-currency support
while keeping existing API clients working without changes.

## What to Do

1. Read `MIGRATION_REQUEST.md`
2. **Produce a migration strategy document before writing any code**
3. Add `currency` field (ISO 4217, default USD) to accounts
4. Ensure existing `GET /accounts` and `POST /transactions` still work unchanged
5. Add `GET /accounts?currency=X` filter
6. Block cross-currency transfers with 422
7. Produce a migration script (`migration.sql` or `migrate.js`)

## Test

```bash
npm install && npm test
```

Success = 18 assertions passing + migration script exists.
