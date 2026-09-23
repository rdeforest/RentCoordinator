# migrations/2026-09-23_130000_disable_recurring_scheduler.coffee
#
# Stops the recurring-events scheduler writing before the next commit removes
# it (bug 26). Two steps rather than one so each is revertible on its own: set
# this back to active = 1 and the old behaviour returns, without a code change.
#
# What it was doing: the `recalculation` template fired monthly and called
# rentService.recalculateAllRent(), which rewrites every rent_periods row from
# the legacy rent_events table — including the phantom -1600 "rent due" rows
# the event model was built to stop double-counting. Nothing reads the result.
# The `rent_due` template was already disabled by the 2026-06-11 seed.
#
# The tables are left in place. They hold real history, nothing writes to them
# after this, and dropping them is a separate decision with its own gotchas
# (the health check asserts rent_periods exists).
#
# Idempotent: disabling an already-disabled template changes nothing.

{ DatabaseSync } = require 'node:sqlite'

DB_PATH = process.env.DB_PATH or './tenant-coordinator.db'
db      = new DatabaseSync DB_PATH

console.log "Running migration: disable_recurring_scheduler against #{DB_PATH}"

try
  unless db.prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE type='table' AND name='recurring_events'").get().n
    console.log '  no recurring_events table — nothing to disable'
  else
    result = db.prepare('UPDATE recurring_events SET active = 0 WHERE active = 1').run()
    console.log "  Disabled #{result.changes} active recurring template(s)"

  console.log 'Migration completed successfully'

catch err
  console.error 'Migration failed:', err.message
  throw err

finally
  db.close()
