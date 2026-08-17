# Bug 36 — Logger tokenizes metadata but not the error message/stack

**Reported:** 2026-08-15 by codebase audit
**Status:** active

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
