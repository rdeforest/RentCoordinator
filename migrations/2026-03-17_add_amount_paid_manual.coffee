{ DatabaseSync } = require 'node:sqlite'

DB_PATH = process.env.DB_PATH or './tenant-coordinator.db'

db = new DatabaseSync DB_PATH

console.log 'Running migration: add amount_paid_manual column'

try
  db.exec 'ALTER TABLE rent_periods ADD COLUMN amount_paid_manual BOOLEAN DEFAULT 0'
  console.log 'Migration completed successfully'
catch err
  if err.message.includes 'duplicate column'
    console.log 'Column already exists, skipping'
  else
    throw err
finally
  db.close()
