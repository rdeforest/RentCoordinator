# migrations/002-add-amount-due-manual.coffee
#
# Adds amount_due_manual to rent_periods. Tracks when amount_due is a
# manual override vs computed. Idempotent.

{ DatabaseSync } = require 'node:sqlite'

DB_PATH = process.env.DB_PATH or './tenant-coordinator.db'
db      = new DatabaseSync DB_PATH

console.log "Running migration: 002-add-amount-due-manual against #{DB_PATH}"

try
  db.exec 'ALTER TABLE rent_periods ADD COLUMN amount_due_manual BOOLEAN DEFAULT 0'
  console.log 'Migration completed successfully'
catch err
  if err.message.includes 'duplicate column'
    console.log 'Column already exists, skipping'
  else
    console.error 'Migration failed:', err.message
    throw err
finally
  db.close()
