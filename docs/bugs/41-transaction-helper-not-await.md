# Bug 41 — transaction() helper doesn't await its callback and can't nest

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

`transaction()` gives a false guarantee of atomicity for any async
callback, and throws if called inside an already-open transaction.

## Reproduction

N/A — latent; triggered if a caller passes an async `fn` to
`transaction`, or nests one `transaction` call inside another.

## Root cause

`lib/db/utils.coffee:10-19`:

- `result = fn()` is not awaited (`:13`). If `fn` returns a promise,
  `db.exec 'COMMIT'` fires before the awaited work runs — a silent
  partial commit. This is safe today only because `node:sqlite` is
  synchronous and every current caller is synchronous.
- `db.exec 'BEGIN'` (`:11`) throws if a transaction is already open —
  there is no savepoint/nesting support.
- The bare `try db.exec 'ROLLBACK'` with no `catch` (`:17-18`)
  deliberately swallows a failed rollback. On its own that's defensible,
  but combined with the above it hides real failures.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Pick one and make it explicit:

- Document and enforce sync-only callbacks (keep it simple, matches
  today's usage), or
- Make the helper `await fn()` and use `SAVEPOINT`/`RELEASE`/`ROLLBACK
  TO` so it can nest and so async callbacks commit correctly.

## Risk

Low. No async or nested caller exists today.
