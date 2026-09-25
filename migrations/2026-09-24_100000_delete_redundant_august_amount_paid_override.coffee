# migrations/2026-09-24_100000_delete_redundant_august_amount_paid_override.coffee
#
# Bug 66: 2026-08's amount_paid override (id 01a06834-16fc-73ff-a366-e2c1ae188cde,
# pinning 1200) is redundant — Stripe shows one $1,200 payment for August,
# initiated 08-30; the payment-made event dated 09-04 is its ACH settlement.
# The pin was a stopgap during the 09-03 recovery. Removing it before the
# amount_paid override rule changes to apply later payments on top of the pin
# (see lib/services/period.coffee) keeps August at $1,200 paid instead of
# double-counting to $2,400.
#
# Recorded the same way DELETE /rent/events/:id does: a `deleted` event
# targeting the override, not a row mutation — the ledger's own correction
# mechanism. See docs/event-model.md.
#
# Idempotent: no-op if the target event does not exist (fresh DBs, tests) or
# is already deleted (re-runs).

{ DatabaseSync } = require 'node:sqlite'
{ v7: uuidv7 }   = require 'uuid'

DB_PATH = process.env.DB_PATH or './tenant-coordinator.db'
db      = new DatabaseSync DB_PATH

TARGET_EVENT_ID = '01a06834-16fc-73ff-a366-e2c1ae188cde'
LANDLORD_EMAIL  = 'robert@defore.st'
REASON          = 'redundant: August paid once via Stripe (bug 66)'

console.log "Running migration: delete_redundant_august_amount_paid_override against #{DB_PATH}"

try
  target = db.prepare('SELECT id, effective_for FROM events WHERE id = ?').get TARGET_EVENT_ID

  unless target
    console.log '  target override event not found — nothing to delete'
  else
    alreadyDeleted = db.prepare("""
      SELECT COUNT(*) AS n FROM events WHERE action = 'deleted' AND target_event_id = ?
    """).get(TARGET_EVENT_ID).n

    if alreadyDeleted > 0
      console.log '  already deleted — no-op'
    else
      db.prepare("""
        INSERT INTO events
          (id, occurred_at, effective_for, actor, actor_user, action, payload, target_event_id)
        VALUES
          (?, ?, ?, 'landlord', ?, 'deleted', ?, ?)
      """).run(
        uuidv7()
        new Date().toISOString()
        target.effective_for
        LANDLORD_EMAIL
        JSON.stringify(reason: REASON)
        TARGET_EVENT_ID
      )
      console.log '  recorded a deleted event targeting the redundant override'

  console.log 'Migration completed successfully'

catch err
  console.error 'Migration failed:', err.message
  throw err

finally
  db.close()
