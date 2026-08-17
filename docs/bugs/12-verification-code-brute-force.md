# Bug 12 — Verification code is brute-forceable (no lockout)

**Reported:** 2026-08-15 by codebase audit
**Status:** active (security)

## Symptom

An attacker who knows a whitelisted email address can guess the 6-digit
login code by brute force. There is no attempt limit, no lockout, and no
rate limit, so the full keyspace is reachable inside the code's validity
window.

## Reproduction

1. Trigger a code for a whitelisted email (`POST /auth/send-code`).
2. Repeatedly `POST /auth/verify-code` with that email and different
   6-digit guesses.
3. Observe that every wrong guess just returns
   `Invalid verification code` and the code remains usable.

Expected: the code is invalidated after a few failures, and/or the
endpoint is rate-limited.
Actual: unlimited guesses until the 10-minute expiry; any correct guess
authenticates.

## Root cause

`verifyCode` (auth.coffee:31-50) fetches the latest `verified = 0` code
for the email and compares:

```
unless stored.code is code
  return success: false, error: 'Invalid verification code'   # auth.coffee:41-42
```

On mismatch it returns an error and does nothing else — no failure
counter, no lockout, no deletion of the code. The code stays valid for
the full `config.CODE_EXPIRY` window (10 minutes, config.coffee:23). The
route `lib/routes/auth.coffee` applies no rate limiting to
`/auth/verify-code`. The `idx_auth_sessions_code` index makes each
lookup cheap.

With a 6-digit code there are 1,000,000 possibilities. Ten minutes is
ample to submit enough guesses to have a meaningful chance of hitting the
code, and with no per-attempt cost the whole space is within reach.

## Proposed fix

Two complementary changes:

- Track failed attempts per code (a counter column on `auth_sessions`)
  and delete/invalidate the code after N failures (e.g. 5), forcing the
  attacker to request a fresh code each time — which is itself
  observable and can be throttled.
- Rate-limit `/auth/verify-code` (and `/auth/send-code`) per email/IP so
  an attacker can't simply loop.

Either alone helps; both together close the window.

## Risk

An attempt counter that invalidates the code can be weaponized for
denial-of-service: an attacker who knows the email can burn the
legitimate user's code by submitting wrong guesses, forcing repeated
resends. Pair the counter with resend throttling and clear user
messaging. IP-based rate limiting behind the load balancer must read the
real client IP (`X-Forwarded-For`), not the LB's address, or it will
throttle everyone as one client.
