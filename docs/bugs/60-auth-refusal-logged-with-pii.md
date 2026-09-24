# Bug 60 — Refused send-code address logged into the permanent PII store

**Reported:** 2026-09-23 by architectural review
**Status:** resolved 2026-09-24

## Resolution

`POST /auth/send-code`'s handler (`lib/routes/auth.coffee`) now checks for
`AUTHORIZATION_REJECTION` first, before any logging happens. A refused
address is logged with `logger.warn`, no stack, and no address in the
metadata — just the fact that a refusal happened. Only a genuine failure
(an address on the allowlist whose code could not be sent — an SMTP error,
for instance) still goes through `logger.error` with the address attached,
which is the case that address is actually worth debugging.

Covered by `test/integration/auth-hardening.coffee`
(`does not log a refused address into the permanent PII store (bug 60)`):
posts a made-up address, reads the server's log file, and asserts the raw
address never appears in it, that the refusal is logged as a `warn`, and
that it carries no stack.

## Symptom

Every rejected `/auth/send-code` call — from a typo, a scanner, or anyone
poking at the login form — permanently tokenized the attempted address into
`pii_tokens`. Unlike a real user's address, these have no legitimate reason
to be retained: they belong to whoever typed them, not to anyone on the
allowlist, and there is no operational reason to keep them once the request
is refused.

## Reproduction

1. `POST /auth/send-code` with an address not on the allowlist.
2. The route's `catch` called `logger.error 'auth.sendCode', err, { email
   }, req.id` unconditionally, before checking what kind of error it was.
3. `logger.error` tokenizes `metadata.email` via `tokenizeMetadata` →
   `tokenizeString`, minting a permanent row in `pii_tokens` — with a full
   stack trace attached, for a rejection that is not an error at all.

## Root cause

`lib/routes/auth.coffee`'s `catch` block logged first and branched on the
error type second. The type check (`err.message is AUTHORIZATION_REJECTION`)
existed only to pick the HTTP status and response body — it never gated
whether or how the error got logged.

## Risk

None identified. The allowlist rejection path already returns the same
response body and status; only what gets logged, and at what level, has
changed.
