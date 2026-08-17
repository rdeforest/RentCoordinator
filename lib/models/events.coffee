# Data access for the events table. Thin layer — the interesting logic is
# in lib/services/period.coffee (the fold). See docs/event-model.md.

{ v7: uuidv7 }                         = require 'uuid'
{ db }                                  = require '../db/schema.coffee'
{ formatSQLParameters, transaction }    = require '../db/utils.coffee'


# Parse the JSON payload back into an object on the way out.
hydrate = (row) ->
  return null unless row
  Object.assign {}, row, payload: JSON.parse row.payload


recordEvent = (event) ->
  params = formatSQLParameters
    id:              event.id              ? uuidv7()
    occurred_at:     event.occurred_at     ? new Date().toISOString()
    effective_for:   event.effective_for   ? null
    actor:           event.actor
    actor_user:      event.actor_user
    action:          event.action
    payload:         JSON.stringify(event.payload ? {})
    target_event_id: event.target_event_id ? null

  db.prepare("""
    INSERT INTO events
      (id, occurred_at, effective_for, actor, actor_user, action, payload, target_event_id)
    VALUES
      (:id, :occurred_at, :effective_for, :actor, :actor_user, :action, :payload, :target_event_id)
  """).run params

  getEvent params[':id']


getEvent = (id) ->
  hydrate db.prepare('SELECT * FROM events WHERE id = ?').get id


# Returns every event in chronological order. The calc needs the whole log
# because retroactive credit folds forward from the earliest month.
listAllEvents = ->
  hydrate row for row in db.prepare('SELECT * FROM events ORDER BY occurred_at, id').all()


listEventsByMonth = (monthKey) ->
  rows = db.prepare("""
    SELECT * FROM events WHERE effective_for = ? ORDER BY occurred_at, id
  """).all monthKey
  hydrate row for row in rows


listEventsByActor = (actor_user) ->
  rows = db.prepare("""
    SELECT * FROM events WHERE actor_user = ? ORDER BY occurred_at, id
  """).all actor_user
  hydrate row for row in rows


# Every payment-made event carrying a given Stripe PaymentIntent id. Lets
# payment recording be idempotent (bug 10): one settled intent credits once,
# no matter how many times confirm/webhook fire for it.
paymentEventsForIntent = (intentId) ->
  rows = db.prepare("""
    SELECT * FROM events
    WHERE action = 'payment-made'
      AND json_extract(payload, '$.stripe_payment_intent_id') = ?
    ORDER BY occurred_at, id
  """).all intentId
  hydrate row for row in rows


# Atomic batch insert. Used by the seed migration and any route that needs
# to emit multiple related events together (e.g. an edit + a follow-on).
recordEvents = (events) ->
  transaction ->
    recordEvent e for e in events


module.exports = {
  recordEvent
  recordEvents
  getEvent
  listAllEvents
  listEventsByMonth
  listEventsByActor
  paymentEventsForIntent
}
