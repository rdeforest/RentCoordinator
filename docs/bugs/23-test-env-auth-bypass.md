# Bug 23 — NODE_ENV=test fully bypasses authentication

**Reported:** 2026-08-15 by codebase audit
**Status:** resolved 2026-09-23

## Resolution

The bypass is gone. `requireAuth` checks the session and nothing else.

The security argument was already in this file. What decided it was a second
one, found by a mutation audit of the test suite: **the bypass made the gate
invisible to the tests.** Deleting `app.use middleware.requireAuth` from
`routing.coffee` outright — removing the gate in front of every route — left
all twelve integration suites green. So did making `requireAuth` call `next()`
unconditionally. Ten of the twelve booted with `NODE_ENV=test`, and the two
that did not only exercised `/auth/*`, which registers before the gate.

So the bypass was not only a production footgun; it was the reason the
codebase's most important guard had zero coverage.

What changed:

- `test/server.coffee` gained `authenticate` and `authenticatedClient`. They
  log in the way a real client does — request a code, read it from the
  database, verify it, keep the cookie — and hand back a session-holding
  client. Every suite that touches a protected route now uses one.
- `lib/services/email.coffee` treats `test` as a local environment, printing
  the code rather than reaching for SMTP. Sending a code under `NODE_ENV=test`
  used to throw `SMTP not configured for production`, which is why the two auth
  suites had to pretend to be `development`.
- `test/integration/auth-gate.coffee` is new: unauthenticated requests to seven
  protected routes across every router, a write that must not land, a forged
  cookie, the browser redirect to `/login.html`, the open routes staying open,
  and the tenant/landlord distinction on an admin route.

Verified by mutation — each of these now fails the suite, and none did before:

| mutation | failures |
|---|---|
| delete `app.use middleware.requireAuth` | 4 |
| `requireAuth` always calls `next()` | 4 |
| strip `requireAdmin` from a backup route | 1 |

`NODE_ENV=test` still shortens `MIN_WORK_LOG_DURATION` and still gates
`/v1/shutdown`. Those are test affordances that cannot open a route.

## Symptom

If a deployed instance ever runs with `NODE_ENV=test`, every protected
route is wide open — no login, no session, no whitelist. Anyone who
reaches the server gets in.

## Reproduction

1. Set `NODE_ENV=test` in the environment (a copied `.env`, a misconfigured
   systemd unit, a leftover shell export).
2. Start the server.
3. Request any protected route without a session cookie.

Expected: 302 to `/login.html` (browser) or 401 JSON (API).
Actual: the request is served.

## Root cause

`lib/middleware.coffee:56-57`, `requireAuth` returns `next()`
unconditionally when `config.NODE_ENV is 'test'`, before any session
check. Auth that hinges on a single env string is fragile: the string is
easy to set by accident and there's no second line of defense. The bypass
was added for test convenience but nothing prevents it from being active
in production.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Stop granting access based on an env string. Tests should authenticate the
way real clients do — seed a valid `auth_sessions` row (or reuse the
existing verify flow) in the test helper and carry the session cookie
through requests. That removes the bypass entirely.

If a blanket bypass has to stay for now, at minimum assert
`NODE_ENV isnt 'test'` at production startup so the server refuses to boot
in the dangerous configuration rather than silently serving everything.

## Risk

Security footgun. The failure mode is total auth loss, triggered by a
single misplaced env var, with no other safeguard between it and the open
routes. Removing the bypass requires updating the test helper to establish
real sessions; the tests in `test/integration/auth.coffee` already
exercise session persistence, so the seam exists.
