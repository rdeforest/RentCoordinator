# migrations/001-add-discount-applied.coffee
#
# Adds the discount_applied column to rent_periods. Stores the calculated
# credit applied from work hours. Idempotent.

{ DatabaseSync } = require 'node:sqlite'

DB_PATH = process.env.DB_PATH or './tenant-coordinator.db'
db      = new DatabaseSync DB_PATH

console.log "Running migration: 001-add-discount-applied against #{DB_PATH}"

try
  db.exec 'ALTER TABLE rent_periods ADD COLUMN discount_applied REAL DEFAULT 0'
  console.log 'Migration completed successfully'
catch err
  if err.message.includes 'duplicate column'
    console.log 'Column already exists, skipping'
  else
    console.error 'Migration failed:', err.message
    throw err
finally
  db.close()
