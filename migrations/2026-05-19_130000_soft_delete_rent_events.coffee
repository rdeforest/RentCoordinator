# migrations/2026-05-19_130000_soft_delete_rent_events.coffee
#
# Adds a nullable deleted_at timestamp to rent_events so that the soft-delete
# UI (Show Deleted toggle, Undelete button) actually has a column to read
# and write. Idempotent — skips if the column already exists.

{ DatabaseSync } = require 'node:sqlite'

DB_PATH = process.env.DB_PATH or './tenant-coordinator.db'
db      = new DatabaseSync DB_PATH

console.log "Running migration: soft_delete_rent_events against #{DB_PATH}"

try
  columns      = db.prepare('PRAGMA table_info(rent_events)').all()
  hasDeletedAt = columns.some (col) -> col.name is 'deleted_at'

  if hasDeletedAt
    console.log '  Column deleted_at already present — skipping'
  else
    db.exec 'ALTER TABLE rent_events ADD COLUMN deleted_at DATETIME'
    db.exec 'CREATE INDEX IF NOT EXISTS idx_rent_events_deleted_at ON rent_events(deleted_at)'
    console.log 'Migration completed successfully'

catch err
  console.error 'Migration failed:', err.message
  throw err

finally
  db.close()
