# Bug 11 — SESSION_SECRET falls back to a public default in production

**Reported:** 2026-08-15 by codebase audit
**Status:** active (security)

## Symptom

If `SESSION_SECRET` is unset, the server still starts and signs session
cookies with a hardcoded secret that is committed to the public repo.
Anyone who knows that secret can forge a valid, signed session for a
whitelisted email — a complete authentication bypass.

## Reproduction

1. Start the server with `NODE_ENV=production` and `SESSION_SECRET`
   unset (env file not loaded, or a fresh box before secrets are
   restored).
2. The server boots normally.
3. Using the known default secret, mint an `express-session` cookie
   whose session has `authenticated: true` and
   `email: robert@defore.st`.
4. Send it to any protected route.

Expected: unset secret in production is a hard failure (or the forged
cookie is rejected).
Actual: the request is accepted as an authenticated whitelisted user.

## Root cause

```
SESSION_SECRET = process.env.SESSION_SECRET or 'dev-secret-change-in-production'   # config.coffee:21
```

This value is passed straight to `express-session` as the signing secret
in `lib/middleware.coffee`. Nothing enforces that the env var is actually
set in production, and the fallback string lives in a public repository.
Cookie signatures are only as secret as that key, so with the default in
force an attacker can construct a cookie the server will trust for any
allowed email.

## Proposed fix

Fail closed at startup: when `NODE_ENV` is `production` (or anything
other than `development`/`test`) and `SESSION_SECRET` is unset, throw
during config load so the process refuses to start. Keep the
`dev-secret-...` fallback only for the dev/test paths. This turns a
silent auth bypass into a loud, obvious boot failure.

## Risk

A production box currently relying on the default would stop booting
until a real `SESSION_SECRET` is provided — which is the point, but it
means the fix must land together with confirming the secret is present
in the environment (it is stored in AWS Secrets Manager as
`rent-coordinator/config`). Rotating to a new secret invalidates all
existing sessions, forcing everyone to log in again; acceptable for a
two-user app but worth doing deliberately. Make sure the `test`
environment is exempted so the test suite keeps running.
