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
