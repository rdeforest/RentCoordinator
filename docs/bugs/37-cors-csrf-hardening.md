# Bug 37 — Wide-open CORS, no explicit cookie sameSite, no CSRF token

**Reported:** 2026-08-15 by codebase audit
**Status:** active
**Category:** security (low-medium)

## Symptom

CORS reflects all origins, the session cookie sets no explicit `sameSite`
attribute, and there is no CSRF token anywhere. State-changing POSTs are
protected against CSRF only by the browser's default cookie behavior.

## Reproduction

N/A — latent defense-in-depth gap. Would become directly exploitable if
the session cookie were later changed to `sameSite: 'none'`, at which
point nothing else guards state-changing requests.

## Root cause

- `app.use cors()` (`lib/middleware.coffee:12`) reflects every origin.
- The session cookie (`lib/middleware.coffee:20-23`) sets `httpOnly` and
  `secure` but no `sameSite`, so it relies on the browser default (Lax)
  as the only CSRF mitigation.
- No CSRF token is issued or checked anywhere.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

- Restrict CORS to the known origin(s) instead of the reflect-all
  default.
- Set `sameSite` explicitly on the session cookie (e.g. `'lax'`) so the
  CSRF stance doesn't depend on an implicit browser default.
- Document the CSRF stance. For a 2-user same-origin app an explicit
  `sameSite` may be sufficient; if cross-site POSTs are ever needed, add
  a real CSRF token then.

## Risk

Low to apply. Tightening CORS could break any cross-origin client — for
this app there shouldn't be one, but verify before deploying.
