# migrations/2026-05-19_120000_cascade_period_deletes.coffee
#
# Adds ON DELETE CASCADE to the two foreign keys that reference
# rent_periods(id):
#   - rent_events.period_id
#   - recurring_event_logs.period_id
#
# SQLite doesn't support modifying constraints in place, so we rebuild
# each affected table. The whole operation runs in a single transaction;
# if anything fails, ROLLBACK leaves the database unchanged.
#
# This migration is idempotent: it detects whether cascades are already
# present and skips work that's already done.

{ DatabaseSync } = require 'node:sqlite'

DB_PATH = process.env.DB_PATH or './tenant-coordinator.db'
db      = new DatabaseSync DB_PATH

console.log "Running migration: cascade_period_deletes against #{DB_PATH}"


# Returns true if the named table's CREATE TABLE statement contains
# 'ON DELETE CASCADE' anywhere — good enough as an idempotency check
# since neither of these tables had cascade behavior before.
tableHasCascade = (tableName) ->
  row = db.prepare("""
    SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?
  """).get tableName

  return false unless row?.sql
  return row.sql.toUpperCase().includes 'ON DELETE CASCADE'


rebuildRentEvents = ->
  if tableHasCascade 'rent_events'
    console.log '  rent_events already has cascade — skipping'
    return

  console.log '  Rebuilding rent_events with ON DELETE CASCADE...'
  db.exec '''
    CREATE TABLE rent_events_new (
      id          TEXT PRIMARY KEY,
      period_id   TEXT NOT NULL REFERENCES rent_periods(id) ON DELETE CASCADE,
      type        TEXT NOT NULL,
      amount      REAL NOT NULL,
      description TEXT,
      metadata    TEXT,
      created_at  DATETIME DEFAULT CURRENT_TIMESTAMP
    );
    INSERT INTO rent_events_new
      (id, period_id, type, amount, description, metadata, created_at)
      SELECT id, period_id, type, amount, description, metadata, created_at
      FROM rent_events;
    DROP TABLE rent_events;
    ALTER TABLE rent_events_new RENAME TO rent_events;
    CREATE INDEX IF NOT EXISTS idx_rent_events_period ON rent_events(period_id);
    CREATE INDEX IF NOT EXISTS idx_rent_events_type   ON rent_events(type);
  '''


rebuildRecurringEventLogs = ->
  if tableHasCascade 'recurring_event_logs'
    console.log '  recurring_event_logs already has cascade — skipping'
    return

  console.log '  Rebuilding recurring_event_logs with ON DELETE CASCADE...'
  db.exec '''
    CREATE TABLE recurring_event_logs_new (
      id                 TEXT PRIMARY KEY,
      recurring_event_id TEXT NOT NULL REFERENCES recurring_events(id) ON DELETE CASCADE,
      period_id          TEXT NOT NULL REFERENCES rent_periods(id) ON DELETE CASCADE,
      amount             REAL NOT NULL,
      processed_at       DATETIME DEFAULT CURRENT_TIMESTAMP
    );
    INSERT INTO recurring_event_logs_new
      (id, recurring_event_id, period_id, amount, processed_at)
      SELECT id, recurring_event_id, period_id, amount, processed_at
      FROM recurring_event_logs;
    DROP TABLE recurring_event_logs;
    ALTER TABLE recurring_event_logs_new RENAME TO recurring_event_logs;
  '''


try
  # foreign_keys must be OFF during the table rebuild, or SQLite tries
  # to validate the temporary rent_events_new before we rename it.
  db.exec 'PRAGMA foreign_keys = OFF'
  db.exec 'BEGIN TRANSACTION'

  rebuildRentEvents()
  rebuildRecurringEventLogs()

  # Sanity check: ensure foreign keys are still valid before commit.
  violations = db.prepare('PRAGMA foreign_key_check').all()
  if violations.length > 0
    throw new Error "FK violations after rebuild: #{JSON.stringify violations}"

  db.exec 'COMMIT'
  console.log 'Migration completed successfully'

catch err
  console.error 'Migration failed:', err.message
  try
    db.exec 'ROLLBACK'
  throw err

finally
  db.exec 'PRAGMA foreign_keys = ON'
  db.close()
