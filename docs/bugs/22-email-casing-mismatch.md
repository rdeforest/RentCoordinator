# Bug 22 — Email casing mismatch can break verification

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

A whitelisted user requests a login code, enters the correct code, and
gets "No verification code found" — as if the code never existed. The
whitelist check passed (they got the email), but the verify step can't
find their code. The trigger is casing: the send request and the verify
request used the email with different capitalization.

## Reproduction

1. POST to the send-code endpoint with `Robert@Defore.st`.
2. Receive the code by email.
3. POST to the verify endpoint with `robert@defore.st` (lowercased by
   the client, autofill, or the user typing).

Expected: code verifies.
Actual: `getVerificationCode` returns nothing → "No verification code
found".

## Root cause

`lib/models/auth.coffee` treats email casing inconsistently:

- `isEmailAllowed` (60-63) normalizes with `.toLowerCase().trim()` before
  comparing to the whitelist, so the send step passes regardless of
  casing.
- `storeVerificationCode` (7-15) persists the email exactly as received —
  raw casing.
- `getVerificationCode` (20-26) and `deleteVerificationCode` (53-57) match
  with a case-sensitive SQLite `WHERE email = ?`.

So if the stored casing and the lookup casing differ, the row never
matches. The same split also means `session.email` and the `pii_tokens`
mapping vary by casing — the same person can produce different tokens and
identities depending on how they typed their address.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Normalize the email once at the route boundary (lowercase + trim) before
it reaches any model function, and store, query, and compare only the
normalized form everywhere. Normalizing inside each model function would
also work but leaves the door open for the next caller to forget; doing it
at the boundary makes the normalized address the only thing the rest of
the system ever sees.

## Risk

Low. Existing unverified rows with mixed-case emails would no longer match
after the change, but those are short-lived (10-minute expiry) and a user
can just request a new code. No stored authoritative data keys off email
casing beyond the pii_tokens mapping, which self-heals on next login.
