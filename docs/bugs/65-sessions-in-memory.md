# Bug 65 — Login sessions live in memory, so every restart logs everyone out

**Reported:** 2026-09-24, found while preparing the 2026-09 sweep deploy
**Status:** resolved

## Symptom

CLAUDE.md promises 90-day sessions. In practice a session lasts until the
next deploy, crash, or instance replacement, after which both users must
request a new email code.

## Root cause

`lib/middleware.coffee` configures `express-session` with no `store`, so it
uses the default MemoryStore. The express-session docs say MemoryStore is not
meant for production: sessions die with the process, and it never evicts
expired entries.

## Proposed fix

A SQLite-backed session store in the existing database (the app already
depends on `node:sqlite`; a small store keyed by session id with an expiry
column and a sweep is about the size of the verification-code table). Once
it exists, the deploy procedure no longer logs anyone out.

Relevant to the OAuth work too: a provider login ends in the same session.

## Resolution

Added `SQLiteSessionStore` (`lib/services/session-store.coffee`), a small
class extending `express-session`'s `Store` that implements the required
`get`/`set`/`destroy` and the recommended `touch`, all against a new
`sessions` table (`sid` primary key, JSON `sess`, `expires` as an epoch-ms
integer). `lib/middleware.coffee` now passes `store: new
sessionStore.SQLiteSessionStore()` to `express-session`, no new dependency.

**Table definition — single source of truth:** `lib/db/schema.coffee`'s
`SCHEMA` (`CREATE TABLE IF NOT EXISTS sessions ...`). `db.exec SCHEMA` runs
unconditionally on every boot, before migrations, so this is what actually
creates the table — for a fresh database and for one already running the old
code. `migrations/2026-09-24_100000_add_sessions_table.coffee` mirrors the
`add_events_table` migration's shape (same idempotent
`CREATE TABLE IF NOT EXISTS` pattern) for consistency with how this repo
records schema changes and for a database migrated by hand outside the
`schema.initialize` path, but by the time it would run in the normal boot
sequence, `SCHEMA` has already created the table on that same boot.

**Expiry:** `expiryOf` reads `sess.cookie.expires` (the cookie's own
computed expiry) and falls back to `Date.now() + config.SESSION_MAX_AGE` for
a session with no persistent cookie — the same fallback express-session uses
internally. `get` treats a row with `expires < Date.now()` as absent, same
as `getVerificationCode`/`verifyCode` do for `auth_sessions` (bug 38). A
hidden `setInterval` (`startSweep`, unref'd like `backup.coffee`'s idle-backup
timer) deletes expired rows hourly so the table stays bounded even between
logins — verification codes instead sweep opportunistically on every new
code, but sessions have no equivalent per-request write to piggyback on.

**Tests:**
- `test/services/session-store.coffee` — unit coverage: round-trip,
  expired session not returned, `touch` extends expiry, `destroy` removes,
  `sweepExpired` deletes only expired rows.
- `test/integration/session-persistence.coffee` — starts a server, logs in,
  shuts it down, starts a *second* process against the same database file,
  and asserts the first process's cookie still authenticates. Verified this
  fails against the stock `MemoryStore` (temporarily removed the `store:`
  option from `middleware.coffee`, reran — failed with "the session written
  by the first process must be readable by the second"; restored the fix,
  reran — passed).

`npm test` (13 unit suites) and `npm run test:integration` both pass; no
stray `coffee main.coffee` processes remained afterward.
