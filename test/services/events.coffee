# Bug 57 — a malformed amount on an event write threw a plain Error, which
# lib/middleware.coffee's error handler treats as a 500 (it only special-cases
# a status the error already carries). This left an unambiguous client mistake
# — "amount" wasn't a number — reported to the caller as an internal server
# error and logged as one.

fs   = require 'node:fs'
os   = require 'node:os'
path = require 'node:path'

DB_PATH = path.join fs.mkdtempSync(path.join os.tmpdir(), 'rc-events-'), 'events-test.db'
process.env.DB_PATH  = DB_PATH
process.env.NODE_ENV = 'test'

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
schema                          = require '../../lib/db/schema.coffee'
eventsModel                     = require '../../lib/models/events.coffee'

before -> await schema.initialize()
after  -> fs.rmSync path.dirname(DB_PATH), recursive: true, force: true


baseEvent = (overrides = {}) ->
  Object.assign {
    occurred_at:   new Date().toISOString()
    effective_for: '2026-01'
    actor:         'tenant'
    actor_user:    'lynz57@hotmail.com'
    action:        'payment-made'
    payload:       { amount: 100, method: 'manual' }
  }, overrides


describe 'recordEvent rejects malformed amounts with a 400, not a 500 (bug 57)', ->
  it "a non-numeric payment amount throws with err.status = 400", ->
    event = baseEvent payload: { amount: 'not-a-number', method: 'manual' }

    threw = null
    try
      eventsModel.recordEvent event
    catch err
      threw = err

    assert.ok threw, 'recordEvent must reject this'
    assert.equal threw.status, 400,
      'a validation failure is the caller\'s mistake — err.status must mark it 4xx'

  it "a NaN adjustment delta throws with err.status = 400", ->
    event = baseEvent
      action:  'adjustment'
      payload: { target_kind: 'period-field', target: { field: 'amount_due' }, delta: NaN }

    threw = null
    try
      eventsModel.recordEvent event
    catch err
      threw = err

    assert.ok threw
    assert.equal threw.status, 400

  it "a well-formed event still records normally", ->
    event = eventsModel.recordEvent baseEvent()
    assert.ok event.id


describe 'recordEvent stores only whole cents (bug 35)', ->
  rejects = (event) ->
    assert.throws (-> eventsModel.recordEvent event), (err) ->
      err.status is 400 and /whole number of cents/.test err.message

  it 'refuses a fraction of a cent on a payment, an adjustment, an override and an edit', ->
    rejects baseEvent payload: { amount: 10.005, method: 'manual' }
    rejects baseEvent action: 'adjustment', payload: { target: { field: 'amount_due' }, delta: 0.001 }
    rejects baseEvent action: 'override', payload: { target_kind: 'period-field', target: { field: 'amount_due' }, new_value: 950.125 }
    rejects baseEvent action: 'edited', target_event_id: 'x', payload: { new_payload: { amount: 1.999 } }
    rejects baseEvent action: 'config-changed', effective_for: null, payload: { field: 'temporary_rent_amount', new_value: 950.5001 }

  it 'accepts real amounts, and hours that are not money', ->
    assert.ok eventsModel.recordEvent baseEvent payload: { amount: 1433.33, method: 'manual' }
    assert.ok eventsModel.recordEvent baseEvent action: 'work-reported', payload: { hours: 200 / 60 }
    assert.ok eventsModel.recordEvent baseEvent action: 'config-changed', effective_for: null, payload: { field: 'apply_override', new_value: true }


describe 'recordEvent rejects an effective_for outside a real calendar month (bug 62, F1)', ->
  it "a month of '13' throws with err.status = 400 rather than reaching the fold", ->
    event = baseEvent effective_for: '2026-13'

    threw = null
    try
      eventsModel.recordEvent event
    catch err
      threw = err

    assert.ok threw, 'recordEvent must reject this — computeAllPeriods would otherwise walk forever looking for it'
    assert.equal threw.status, 400

  it 'a malformed (non YYYY-MM) string is rejected', ->
    assert.throws (-> eventsModel.recordEvent baseEvent effective_for: 'not-a-month'),
      (err) -> err.status is 400

  it 'null is accepted (global events like config-changed carry no effective_for)', ->
    assert.ok eventsModel.recordEvent baseEvent action: 'config-changed', effective_for: null, payload: { field: 'apply_override', new_value: false }

  it 'a well-formed YYYY-MM is accepted', ->
    assert.ok eventsModel.recordEvent baseEvent effective_for: '2026-12'


describe 'effective_for is validated where an action owns a month', ->
  it 'refuses a payment filed under month 13', ->
    assert.throws (-> eventsModel.recordEvent baseEvent effective_for: '2026-13'), (err) -> err.status is 400

  it 'still lets a bad row be deleted through the app', ->
    # Meta events copy their target's effective_for; refusing them would make
    # the consistency finding for that row impossible to settle.
    schema.db.prepare("""
      INSERT INTO events (id, occurred_at, effective_for, actor, actor_user, action, payload)
      VALUES ('bad-row', '2026-05-01T00:00:00Z', '2026-13', 'tenant', 'lynz57@hotmail.com', 'payment-made', '{"amount":100}')
    """).run()

    assert.ok eventsModel.recordEvent baseEvent
      action:          'deleted'
      effective_for:   '2026-13'
      target_event_id: 'bad-row'
      payload:         {}
