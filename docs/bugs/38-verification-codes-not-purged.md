# Bug 38 — Used/expired verification codes are never purged

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

`auth_sessions` grows without bound and retains plaintext verification
codes indefinitely. Successfully used codes stay in the table forever;
superseded and expired codes linger.

## Reproduction

N/A — latent; triggered by normal login over time. Every successful
verification leaves a `verified = 1` row that is never deleted, and every
expired-but-unused code stays until a later login for the same email
clears it.

## Root cause

`verifyCode` (`lib/models/auth.coffee:44-50`) sets `verified = 1` on
success and never deletes the row. `deleteVerificationCode`
(`lib/models/auth.coffee:53-57`) only removes `verified = 0` rows, so it
can't clean up used codes. Nothing purges expired rows on a schedule.

Not directly exploitable — `getVerificationCode` filters to
`verified = 0`, newest-first — but it's needless retention of
plaintext secrets.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

- Delete the code row on successful verification (the session cookie, not
  the DB row, is what keeps the user logged in).
- Add a periodic purge of expired rows (e.g. as part of the existing
  scheduled task machinery).

## Risk

Low. Deleting on success has no effect on live sessions. The periodic
purge only touches already-expired rows.
