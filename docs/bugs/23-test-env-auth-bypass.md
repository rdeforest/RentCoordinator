# Bug 23 — NODE_ENV=test fully bypasses authentication

**Reported:** 2026-08-15 by codebase audit
**Status:** active

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
