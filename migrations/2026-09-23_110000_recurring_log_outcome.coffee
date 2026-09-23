# migrations/2026-09-23_110000_recurring_log_outcome.coffee
#
# Bug 28 — recurring_event_logs stored only id/event/period/amount/time, so
# createProcessingLog silently dropped the status, message, error details and
# created-event ids it was handed, and getProcessingLogs hardcoded
# status='success' on the way back out. A run that threw was logged, read back,
# and displayed as a success with no detail.
#
# Existing rows get status NULL — honestly unknown — rather than being
# backfilled as successes, which is the lie this replaces.
#
# Idempotent: each column add is skipped if it is already present.

{ DatabaseSync } = require 'node:sqlite'

DB_PATH = process.env.DB_PATH or './tenant-coordinator.db'
db      = new DatabaseSync DB_PATH

console.log "Running migration: recurring_log_outcome against #{DB_PATH}"


COLUMNS =
  status:         'TEXT'
  message:        'TEXT'
  error_details:  'TEXT'
  events_created: 'TEXT'   # JSON array of event ids

hasColumn = (table, column) ->
  db.prepare("PRAGMA table_info(#{table})").all().some (c) -> c.name is column


try
  db.exec 'BEGIN TRANSACTION'

  for column, type of COLUMNS
    if hasColumn 'recurring_event_logs', column
      console.log "  recurring_event_logs.#{column} already present — skipping"
    else
      console.log "  Adding recurring_event_logs.#{column}..."
      db.exec "ALTER TABLE recurring_event_logs ADD COLUMN #{column} #{type}"

  db.exec 'COMMIT'
  console.log 'Migration completed successfully'

catch err
  console.error 'Migration failed:', err.message
  try
    db.exec 'ROLLBACK'
  catch rollbackErr
    console.error 'Rollback ALSO failed — the database may be mid-transaction:',
      rollbackErr.message
  throw err

finally
  db.close()
