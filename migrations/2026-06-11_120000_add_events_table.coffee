# migrations/2026-06-11_120000_add_events_table.coffee
#
# Creates the events table that will become the single source of truth for
# the rent system. See docs/event-model.md.
#
# Idempotent: skips if the table already exists. Does not migrate any data
# into it — that's a separate seed migration so we can verify the conversion
# before the cutover.

{ DatabaseSync } = require 'node:sqlite'

DB_PATH = process.env.DB_PATH or './tenant-coordinator.db'
db      = new DatabaseSync DB_PATH

console.log "Running migration: add_events_table against #{DB_PATH}"

try
  existing = db.prepare("""
    SELECT name FROM sqlite_master WHERE type='table' AND name='events'
  """).get()

  if existing
    console.log '  events table already present — skipping'
  else
    db.exec '''
      CREATE TABLE events (
        id              TEXT PRIMARY KEY,
        occurred_at     DATETIME NOT NULL,
        effective_for   TEXT,
        actor           TEXT NOT NULL,
        actor_user      TEXT NOT NULL,
        action          TEXT NOT NULL,
        payload         TEXT NOT NULL,
        target_event_id TEXT REFERENCES events(id) ON DELETE CASCADE,
        created_at      DATETIME DEFAULT CURRENT_TIMESTAMP
      );
      CREATE INDEX idx_events_effective_for   ON events(effective_for);
      CREATE INDEX idx_events_actor_user      ON events(actor_user);
      CREATE INDEX idx_events_target_event_id ON events(target_event_id);
      CREATE INDEX idx_events_action          ON events(action);
    '''
    console.log 'Migration completed successfully'

catch err
  console.error 'Migration failed:', err.message
  throw err

finally
  db.close()
