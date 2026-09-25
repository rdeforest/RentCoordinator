# migrations/2026-09-24_100000_add_sessions_table.coffee
#
# Bug 65 — express-session used the default MemoryStore: sessions died with
# the process and were never evicted. Adds the table the new SQLite-backed
# store (lib/services/session-store.coffee) reads and writes.
#
# lib/db/schema.coffee::initialize runs `db.exec SCHEMA` — which already
# contains this same `CREATE TABLE IF NOT EXISTS` — before it runs migrations,
# so on every boot the table exists before this file could ever run. This
# migration is the historical record for a database migrated by hand outside
# that path (see migrations/README.md); the schema is the one thing that
# actually has to create the table.
#
# Idempotent: skips if the table already exists.

{ DatabaseSync } = require 'node:sqlite'

DB_PATH = process.env.DB_PATH or './tenant-coordinator.db'
db      = new DatabaseSync DB_PATH

console.log "Running migration: add_sessions_table against #{DB_PATH}"

try
  existing = db.prepare("""
    SELECT name FROM sqlite_master WHERE type='table' AND name='sessions'
  """).get()

  if existing
    console.log '  sessions table already present — skipping'
  else
    db.exec '''
      CREATE TABLE sessions (
        sid TEXT PRIMARY KEY,
        sess TEXT NOT NULL,
        expires INTEGER NOT NULL
      );
      CREATE INDEX idx_sessions_expires ON sessions(expires);
    '''
    console.log 'Migration completed successfully'

catch err
  console.error 'Migration failed:', err.message
  throw err

finally
  db.close()
