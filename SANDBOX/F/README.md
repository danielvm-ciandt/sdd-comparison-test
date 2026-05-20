# Task F: Todo Auth Slice

**Type:** Greenfield (ambiguous spec)  
**Tier:** Quick (~2–3 min)  
**Dimension:** Spec disambiguation before coding

## The Problem

`server.js` has working CRUD but no authentication. `FEATURE_REQUEST.md`
gives a vague requirement. The spec does NOT specify token format, expiry,
401 response body, whether signup returns a token, or how logout works.

## What to Implement

Read `FEATURE_REQUEST.md` first. Resolve the ambiguities, then implement:
- `POST /auth/signup` — create user, return JWT token
- `POST /auth/login` — return JWT token
- `POST /auth/logout` — invalidate token
- Auth middleware on `GET /tasks` and `POST /tasks`
- User-scoped task filtering

## Test

```bash
npm install && npm test
```

Success = 8 assertions passing + at least a partial spec doc created before coding.
