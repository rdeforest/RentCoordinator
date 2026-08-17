# Bug 42 — health check opens/closes a fresh DB connection per hit

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

Every `/health` request opens a brand-new writer-capable SQLite
connection, runs a PRAGMA and a query, and closes it — instead of reusing
the already-open shared handle. The ALB polls this endpoint frequently.

## Reproduction

N/A — latent overhead; triggered under normal ALB health-check polling,
worst during concurrent writes on the main connection.

## Root cause

`lib/routing.coffee:46-55`. `healthCheck` does
`new DatabaseSync config.DB_PATH`, `PRAGMA foreign_keys = ON`, a
`sqlite_master` query, then `db.close()` on every request, rather than
querying the shared `db` already created in `lib/db/schema.coffee:4`.

A second writer-capable connection to the same SQLite file, opened and
closed per request, adds needless overhead and can contend for the
database lock with the main connection during writes.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Reuse the shared `db` handle from `schema.coffee`. A cheap `SELECT 1` (or
the existing `sqlite_master` check) against it proves connectivity
without opening a second connection.

## Risk

Low. The health check still validates the same invariants against the
live connection.
