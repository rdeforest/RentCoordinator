# Bug 65 — Login sessions live in memory, so every restart logs everyone out

**Reported:** 2026-09-24, found while preparing the 2026-09 sweep deploy
**Status:** open

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
