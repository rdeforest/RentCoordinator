# Bug 61 — Logger truncates before tokenizing, splitting addresses

**Reported:** 2026-09-23 by architectural review
**Status:** resolved 2026-09-24

## Resolution

`lib/logger.coffee::tokenizeString` now tokenizes the full string first and
truncates the result second. The truncation length (`MAX_LOGGED_STRING`,
4096) exists to bound a single log record's size, not to bound how much text
`tokenizeEmbedded` is allowed to see — that cost is already bounded
separately, per record, by the match budget threaded through from
`logger.error`/`logger.warn` (`tokenService.newBudget()` →
`MAX_TOKENIZE_MATCHES`).

Covered by `test/services/logger.coffee`
(`logger tokenizes before truncating (bug 61)`):
- a message padded so the old truncate-first order would have cut exactly
  one character off a real address, leaving `alice@example.co` — a
  complete-looking but wrong address that the old order tokenized as a
  distinct, fabricated row. The test asserts that token is absent from the
  log line.
- a message with the same address away from the size boundary, asserting the
  *whole* address's real token appears in the log line, unmutilated.

## Symptom

An error message or metadata value long enough to hit the per-string
truncation cap, with an email address straddling the cutoff, could log a
token for an address that was never actually present — one character (or
more) short of the real one. That wrong value is now a permanent row in
`pii_tokens`, indistinguishable from a real tokenized address without
comparing against the original (already-lost) text.

## Reproduction

1. Construct a string longer than `MAX_LOGGED_STRING` (4096 chars) where an
   email address's last character(s) fall past position 4096, but the
   remaining prefix (e.g. `alice@example.co`) still matches the email
   pattern (TLD of 2+ letters).
2. Log it via `logger.error` or `logger.warn`.
3. Old order: `tokenizeString` truncated to 4096 chars first — silently
   cutting the address — then tokenized what was left, minting a token for
   the truncated fragment as if it were a real, distinct address.

## Root cause

`tokenizeString` ran `value[0...MAX_LOGGED_STRING]` before checking whether
the (now truncated) value contained `'@'` and handing it to
`tokenizeEmbedded`. Any string long enough to be truncated had already lost
whatever fell past the cutoff before tokenization ever saw it — including,
sometimes, part of an email address that the truncation point happened to
land inside.

## Risk

None identified: the fix only changes ordering, not what gets logged or how
much. A message so long that even the *tokenized* result still exceeds
`MAX_LOGGED_STRING` can now have its trailing truncation marker land inside
the token text itself rather than inside a raw address — which trades a
possibly-truncated (but already-opaque) token for what used to be a
possibly-fabricated one. That's a strict improvement: a cut token reveals
nothing and creates no new tokenization guesses; a cut address used to.
