# Bug 36 — Logger tokenizes metadata but not the error message/stack

**Reported:** 2026-08-15 by codebase audit
**Status:** resolved 2026-09-23

## Resolution

`logger.tokenizeString` runs error messages and stacks through a shared tokenizer that replaces only the address and leaves the surrounding text intact — a stack reduced to a single token is a different way of losing the log. The pattern is anchored to address characters so a stack frame naming a scoped package (`node_modules/@aws-sdk/client-s3/index.js`) is not matched and filed in the PII store as somebody's address. Tokenizing writes to SQLite, so a failure there falls back to a visible redaction marker rather than throwing from inside the error handler.

Per-match tokenization also needed bounding. `/auth/send-code` logs
`req.body.email` before any authentication, and one request carrying a 50 kB
field of addresses wrote three thousand `pii_tokens` rows, blocked the event
loop long enough for other connections to see "database is locked", and
produced a 73 kB log line. Free text is now capped at 4,096 characters and 20
matches, and the auth routes reject an address longer than RFC 5321 allows.
Found by the second review round.

## Symptom

An email address embedded in an error message or stack trace is written
to logs (and shipped to CloudWatch) in cleartext, defeating the PII
tokenization the logger is supposed to enforce.

## Reproduction

N/A — latent; triggered when an error's `message` or `stack` contains an
email, e.g. a DB uniqueness violation echoing the value or a nodemailer
error naming the recipient.

## Root cause

`error` (`lib/logger.coffee:34,36`) writes `errorObj.message` and
`errorObj.stack` verbatim. Only `tokenizeMetadata` runs a tokenizing
pass, and it walks the metadata object replacing strings containing `@`
— it never touches the error message or stack.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Run the error message (and optionally the stack) through the same
email-tokenizing pass before assigning them to the log object. Factor the
per-string `@`-detect-and-tokenize step out of `tokenizeMetadata` so both
metadata and error text share one implementation.

## Risk

Low. Confined to the logger. Tokenizing the stack may make traces
slightly harder to read, hence the "optionally" — at minimum tokenize the
message.
