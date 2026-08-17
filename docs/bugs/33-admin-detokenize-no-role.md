# Bug 33 — admin/detokenize gated only by shared auth, not an admin role

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

`POST /admin/detokenize` reverses tokenized PII back to original values
and is available to any authenticated session — including the tenant
(Lyndzie), not just the landlord.

## Reproduction

N/A — latent; triggered when the tenant's authenticated session calls
`POST /admin/detokenize` with a token and receives the original PII.

## Root cause

The route (`lib/routes/admin.coffee:7-20`) is protected only by the
global `requireAuth` (`lib/routing.coffee` / `lib/middleware.coffee:55`),
which passes any session with `authenticated` set — i.e. either
whitelisted user. There is no per-user/admin gate, so the tenant can
recover the landlord's tokenized PII.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Restrict admin routes to a specific user. Add a guard that checks
`req.session.email` against the landlord's address (or a small admin
list) and rejects everyone else, then mount it on the `/admin/*` routes.

## Risk

Low severity for a 2-user app, but the fix is cheap and closes a real PII
disclosure. Guard must not break the `NODE_ENV is 'test'` bypass path
that `requireAuth` already honors.
