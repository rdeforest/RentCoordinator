#!/usr/bin/env coffee

# Apply migration: Add amount_due_manual column to rent_periods table

{ db, initialize } = require '../lib/db/schema.coffee'

do ->
  console.log 'Initializing database...'
  await initialize()

  console.log 'Applying migration: Add amount_due_manual column...'

  try
    db.prepare('ALTER TABLE rent_periods ADD COLUMN amount_due_manual BOOLEAN DEFAULT 0').run()
    console.log '✓ Migration applied successfully!'
  catch err
    if err.message.includes 'duplicate column'
      console.log '⚠ Column already exists, skipping migration'
    else
      console.error '✗ Migration failed:', err.message
      process.exit 1

  # Verify the column exists
  columns = db.prepare('PRAGMA table_info(rent_periods)').all()
  hasColumn = columns.some (col) -> col.name is 'amount_due_manual'

  if hasColumn
    console.log '✓ Verified: amount_due_manual column exists'
  else
    console.error '✗ Error: Column was not added'
    process.exit 1

  process.exit 0
