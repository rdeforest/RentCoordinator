# Data access for the events table. Thin layer — the interesting logic is
# in lib/services/period.coffee (the fold). See docs/event-model.md.

{ v7: uuidv7 }                         = require 'uuid'
{ db }                                  = require '../db/schema.coffee'
{ formatSQLParameters, transaction }    = require '../db/utils.coffee'
money                                   = require '../money.coffee'


# Parse the JSON payload back into an object on the way out.
hydrate = (row) ->
  return null unless row
  Object.assign {}, row, payload: JSON.parse row.payload


# Amounts that are not numbers poison every downstream sum, and the event log
# is append-only — a bad row cannot be taken back. Reject at the boundary
# rather than discovering it as a month that quietly reports nothing owed.
#
# By action, not by key name. `new_value` is a number on an `override` and a
# boolean or null on a `config-changed` — validating the key wherever it
# appeared rejected every save from the rent configuration UI.
NUMERIC_FIELDS =
  'payment-made':  ['amount']
  'adjustment':    ['delta']
  'override':      ['new_value']
  'work-reported': ['hours']

# An `edited` event carries the replacement figure nested under `new_payload`,
# keyed for the action it targets. That is the one path that parses
# user-supplied text, and it was the one path the check could not see.
EDITABLE_FIELDS = ['amount', 'delta', 'new_value']

# Hours are the one numeric field that is not money.
NOT_MONEY = ['hours']

# config-changed payloads name their field; these hold dollars.
MONEY_CONFIG_FIELDS = ['temporary_rent_amount', 'base_rent', 'hourly_credit', 'agreed_monthly_payment']


describeValue = (value) ->
  return 'NaN' if typeof value is 'number' and Number.isNaN value
  JSON.stringify value


# A malformed amount is the caller's mistake, not the server's — err.status
# lets the error handler (lib/middleware.coffee) respond 400 instead of the
# 500 a plain Error produces, so a bad request doesn't get logged and
# reported as an internal failure.
badRequest = (message) ->
  err = new Error message
  err.status = 400
  err

# The fold computes in integer cents from these (lib/money.coffee), so a
# stored amount has to be one: $10.005 has no exact meaning.
checkWholeCents = (action, key, value) ->
  unless money.isWholeCents value
    throw badRequest "#{action} payload.#{key} must be a whole number of cents, got #{describeValue value}"

checkFields = (action, payload, fields) ->
  for key in fields when payload?[key]?
    value = payload[key]
    unless typeof value is 'number' and Number.isFinite value
      throw badRequest "#{action} payload.#{key} must be a finite number, got #{describeValue value}"
    checkWholeCents action, key, value unless key in NOT_MONEY

  return


validateAmounts = (event) ->
  checkFields event.action, event.payload, NUMERIC_FIELDS[event.action] ? []

  if event.action is 'edited'
    checkFields 'edited', event.payload?.new_payload, EDITABLE_FIELDS

  if event.action is 'config-changed' and event.payload?.field in MONEY_CONFIG_FIELDS and event.payload.new_value?
    checkWholeCents 'config-changed', 'new_value', event.payload.new_value

  return


recordEvent = (event) ->
  validateAmounts event

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
