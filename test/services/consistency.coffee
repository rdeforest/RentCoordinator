# Bug 62 — unit tests for lib/services/consistency.coffee. Most checks are
# pure functions of constructed events/periods (like test/services/period.coffee);
# the SQLite-backed ones (db-integrity, foreign-key) get a real temp database.

fs   = require 'node:fs'
os   = require 'node:os'
path = require 'node:path'

DB_PATH = path.join fs.mkdtempSync(path.join os.tmpdir(), 'rc-consistency-'), 'consistency-test.db'
process.env.DB_PATH  = DB_PATH
process.env.NODE_ENV = 'test'

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
schema                          = require '../../lib/db/schema.coffee'
consistency                     = require '../../lib/services/consistency.coffee'
period                          = require '../../lib/services/period.coffee'

before -> await schema.initialize()
after  -> fs.rmSync path.dirname(DB_PATH), recursive: true, force: true


uid = 0
newId = -> uid += 1; "e#{uid}"

evt = (action, effective_for, payload, occurred_at = '2026-05-01T00:00:00Z', extras = {}) ->
  Object.assign {
    id:         newId()
    occurred_at
    effective_for
    actor:      'tenant'
    actor_user: 'lynz57@hotmail.com'
    action
    payload
  }, extras

work    = (ym, hours, occurred = "#{ym}-01T10:00:00Z") -> evt 'work-reported', ym, { hours }, occurred
payment = (ym, amount, occurred = "#{ym}-15T10:00:00Z", extras = {}) ->
  evt 'payment-made', ym, { amount }, occurred, extras
override = (ym, field, new_value, occurred = "#{ym}-20T00:00:00Z") ->
  evt 'override', ym, { target_kind: 'period-field', target: { field }, new_value }, occurred,
    { actor: 'landlord', actor_user: 'robert@defore.st' }


# --- ledger invariants --------------------------------------------------------

describe 'checkCorruptMonths', ->
  it 'flags a month the fold marks corrupt', ->
    periods = { '2026-05': { corrupt: true, amount_due: NaN, amount_paid: 0 } }
    findings = consistency.checkCorruptMonths { periods }
    assert.equal findings.length, 1
    assert.equal findings[0].month, '2026-05'
    assert.equal findings[0].severity, 'error'

  it 'is silent on a healthy month', ->
    periods = { '2026-05': { corrupt: false } }
    assert.deepEqual consistency.checkCorruptMonths({ periods }), []


describe 'checkEffectiveFor', ->
  it 'flags a payment-made with a malformed effective_for', ->
    events = [ payment 'not-a-month', 100 ]
    events[0].effective_for = 'not-a-month'
    findings = consistency.checkEffectiveFor { events }
    assert.equal findings.length, 1
    assert.equal findings[0].kind, 'ledger-invalid-effective-for'

  it 'flags a null effective_for on an action that requires one', ->
    events = [ payment '2026-05', 100 ]
    events[0].effective_for = null
    findings = consistency.checkEffectiveFor { events }
    assert.equal findings.length, 1

  it 'is silent on a valid month key', ->
    events = [ payment '2026-05', 100 ]
    assert.deepEqual consistency.checkEffectiveFor({ events }), []

  it 'does not require effective_for on config-changed (global event)', ->
    events = [ evt 'config-changed', null, { field: 'base_rent', new_value: 1600 } ]
    assert.deepEqual consistency.checkEffectiveFor({ events }), []


describe 'checkTargetEventIds', ->
  it 'flags an edited event whose target does not exist', ->
    events = [ evt 'edited', null, { new_payload: {} }, '2026-05-01T00:00:00Z', { target_event_id: 'ghost' } ]
    findings = consistency.checkTargetEventIds { events }
    assert.equal findings.length, 1
    assert.equal findings[0].kind, 'ledger-missing-target'

  it 'is silent when the target exists', ->
    original = payment '2026-05', 100
    edit     = evt 'edited', null, { new_payload: {} }, '2026-05-02T00:00:00Z', { target_event_id: original.id }
    assert.deepEqual consistency.checkTargetEventIds({ events: [original, edit] }), []


describe 'checkDeleteOfDelete', ->
  it 'flags a deleted event targeting another deleted event (pre-bug-16 shape)', ->
    original = payment '2026-05', 100
    del1     = evt 'deleted', null, {}, '2026-05-02T00:00:00Z', { target_event_id: original.id }
    del2     = evt 'deleted', null, {}, '2026-05-03T00:00:00Z', { target_event_id: del1.id }
    findings = consistency.checkDeleteOfDelete { events: [original, del1, del2] }
    assert.equal findings.length, 1
    assert.deepEqual findings[0].event_ids, [del2.id, del1.id]

  it 'is silent on an ordinary delete of a real event', ->
    original = payment '2026-05', 100
    del      = evt 'deleted', null, {}, '2026-05-02T00:00:00Z', { target_event_id: original.id }
    assert.deepEqual consistency.checkDeleteOfDelete({ events: [original, del] }), []


# --- manual vs automatic -------------------------------------------------------

describe 'checkPaymentAfterPin', ->
  it 'flags a payment-made recorded after the amount_paid pin', ->
    pin   = override '2026-05', 'amount_paid', 500, '2026-05-10T00:00:00Z'
    later = payment '2026-05', 200, '2026-05-15T00:00:00Z'
    findings = consistency.checkPaymentAfterPin { events: [pin, later] }
    assert.equal findings.length, 1
    assert.equal findings[0].kind, 'manual-payment-after-pin'

  it 'is silent when the payment precedes the pin', ->
    early = payment '2026-05', 200, '2026-05-05T00:00:00Z'
    pin   = override '2026-05', 'amount_paid', 200, '2026-05-10T00:00:00Z'
    assert.deepEqual consistency.checkPaymentAfterPin({ events: [early, pin] }), []


describe 'checkAmountPaidPinMismatch', ->
  it 'flags a pin that disagrees with the summed payments', ->
    pay = payment '2026-05', 200, '2026-05-05T00:00:00Z'
    pin = override '2026-05', 'amount_paid', 500, '2026-05-10T00:00:00Z'
    findings = consistency.checkAmountPaidPinMismatch { events: [pay, pin] }
    assert.equal findings.length, 1
    assert.equal findings[0].detail.pinned, 500
    assert.equal findings[0].detail.summed, 200

  it 'is silent when the pin equals the sum', ->
    pay = payment '2026-05', 200, '2026-05-05T00:00:00Z'
    pin = override '2026-05', 'amount_paid', 200, '2026-05-10T00:00:00Z'
    assert.deepEqual consistency.checkAmountPaidPinMismatch({ events: [pay, pin] }), []

  it "the finding's key changes when the pinned value changes", ->
    pay  = payment '2026-05', 200, '2026-05-05T00:00:00Z'
    pinA = override '2026-05', 'amount_paid', 500, '2026-05-10T00:00:00Z'
    pinB = override '2026-05', 'amount_paid', 700, '2026-05-10T00:00:00Z'
    keyA = consistency.checkAmountPaidPinMismatch({ events: [pay, pinA] })[0].key
    keyB = consistency.checkAmountPaidPinMismatch({ events: [pay, pinB] })[0].key
    assert.notEqual keyA, keyB


describe 'checkAmountDuePinMismatch', ->
  it 'flags an amount_due override (it pins a different figure than the calc, by design)', ->
    periods =
      '2026-05': { amount_due_override: true, amount_due: 1500, amount_due_calculated: 1600 }
    findings = consistency.checkAmountDuePinMismatch { periods }
    assert.equal findings.length, 1
    assert.equal findings[0].detail.pinned, 1500
    assert.equal findings[0].detail.calculated, 1600

  it 'is silent when there is no override', ->
    periods = { '2026-05': { amount_due_override: false, amount_due: 1600, amount_due_calculated: 1600 } }
    assert.deepEqual consistency.checkAmountDuePinMismatch({ periods }), []

  it 'key stays the same across two runs of identical data (stability)', ->
    periods = { '2026-05': { amount_due_override: true, amount_due: 1500, amount_due_calculated: 1600 } }
    keyA = consistency.checkAmountDuePinMismatch({ periods })[0].key
    keyB = consistency.checkAmountDuePinMismatch({ periods })[0].key
    assert.equal keyA, keyB

  it 'key changes when the calculated amount changes', ->
    periodsA = { '2026-05': { amount_due_override: true, amount_due: 1500, amount_due_calculated: 1600 } }
    periodsB = { '2026-05': { amount_due_override: true, amount_due: 1500, amount_due_calculated: 1650 } }
    keyA = consistency.checkAmountDuePinMismatch({ periods: periodsA })[0].key
    keyB = consistency.checkAmountDuePinMismatch({ periods: periodsB })[0].key
    assert.notEqual keyA, keyB


# --- backup -------------------------------------------------------------------

describe 'checkBackupAge', ->
  it 'flags when the newest S3 backup predates the newest write', ->
    findings = await consistency.checkBackupAge
      s3Enabled:     true
      listS3Backups: -> [ { lastModified: new Date('2026-05-01T00:00:00Z') } ]
      dbLastWriteMs: -> new Date('2026-05-02T00:00:00Z').getTime()
    assert.equal findings.length, 1
    assert.equal findings[0].kind, 'backup-stale'

  it 'is silent when the newest backup is at or after the newest write', ->
    findings = await consistency.checkBackupAge
      s3Enabled:     true
      listS3Backups: -> [ { lastModified: new Date('2026-05-03T00:00:00Z') } ]
      dbLastWriteMs: -> new Date('2026-05-02T00:00:00Z').getTime()
    assert.deepEqual findings, []

  it 'is silent (skips) when S3 is disabled', ->
    findings = await consistency.checkBackupAge
      s3Enabled:     false
      listS3Backups: -> throw new Error 'must not be called'
      dbLastWriteMs: -> Date.now()
    assert.deepEqual findings, []


# --- stripe (stubbed client, never touches the network) -----------------------

describe 'checkStripePayments', ->
  it 'is silent (skips) when Stripe is not configured', ->
    findings = await consistency.checkStripePayments
      stripeEnabled: false
      events: []
      listSucceededPaymentIntents: -> throw new Error 'must not be called'
    assert.deepEqual findings, []

  it 'flags a succeeded PaymentIntent with no matching payment-made event', ->
    intent = { id: 'pi_1', amount: 160000, description: 'Rent payment for 2026-05', created: 1, metadata: {} }
    findings = await consistency.checkStripePayments
      stripeEnabled: true
      events: []
      listSucceededPaymentIntents: -> [intent]
    assert.equal findings.length, 1
    assert.equal findings[0].kind, 'stripe-unlinked'

  it 'is silent when the intent is linked and the allocation agrees', ->
    intent = { id: 'pi_2', amount: 160000, description: 'Rent payment for 2026-05', created: 1, metadata: {} }
    linked = payment '2026-05', 1600, '2026-05-15T00:00:00Z', payload: { amount: 1600, stripe_payment_intent_id: 'pi_2' }
    findings = await consistency.checkStripePayments
      stripeEnabled: true
      events: [linked]
      listSucceededPaymentIntents: -> [intent]
    assert.deepEqual findings, []

  it 'flags when the linked events disagree with the allocation (month or amount)', ->
    intent = { id: 'pi_3', amount: 160000, description: 'Rent payment for 2026-05', created: 1, metadata: {} }
    linked = payment '2026-06', 1600, '2026-06-15T00:00:00Z', payload: { amount: 1600, stripe_payment_intent_id: 'pi_3' }
    findings = await consistency.checkStripePayments
      stripeEnabled: true
      events: [linked]
      listSucceededPaymentIntents: -> [intent]
    assert.equal findings.length, 1
    assert.equal findings[0].kind, 'stripe-mismatch'


# --- orchestration: a check that throws becomes one error finding, others still run --

describe 'runChecks', ->
  it 'turns a throwing check into a single error finding without aborting the run', ->
    findings = await consistency.runChecks
      events:  []
      periods: {}
      db:
        prepare: -> throw new Error 'db exploded'
      s3Enabled:     false
      stripeEnabled: false

    dbErrors = (f for f in findings when f.kind is 'db-integrity-error')
    assert.equal dbErrors.length, 1
    # a later check (foreign-key, also touching the broken db) still ran and
    # produced its own error finding rather than the whole run aborting
    fkErrors = (f for f in findings when f.kind is 'db-foreign-key-error')
    assert.equal fkErrors.length, 1


# --- checkAllocationFor helper (used by the stripe check) ----------------------

describe 'allocationFor', ->
  it 'prefers metadata.allocation when present', ->
    intent = { metadata: { allocation: JSON.stringify [ { year: 2026, month: 5, amount: 800 }, { year: 2026, month: 6, amount: 800 } ] } }
    assert.deepEqual consistency.allocationFor(intent), [ { year: 2026, month: 5, amount: 800 }, { year: 2026, month: 6, amount: 800 } ]

  it 'falls back to metadata.year/month', ->
    intent = { metadata: { year: '2026', month: '5' }, amount: 160000 }
    assert.deepEqual consistency.allocationFor(intent), [ { year: 2026, month: 5, amount: 1600 } ]

  it 'falls back to a month mentioned in the description', ->
    intent = { metadata: {}, amount: 160000, description: 'Rent payment covering 2026-05' }
    assert.deepEqual consistency.allocationFor(intent), [ { year: 2026, month: 5, amount: 1600 } ]

  it 'returns null when nothing names a month', ->
    intent = { metadata: {}, amount: 160000, description: 'thanks!' }
    assert.equal consistency.allocationFor(intent), null


# --- db-integrity / foreign-key against a real (healthy) database -------------

describe 'checkDatabaseIntegrity and checkForeignKeys against a real database', ->
  it 'a freshly initialized database is clean', ->
    assert.deepEqual consistency.checkDatabaseIntegrity({ db: schema.db }), []
    assert.deepEqual consistency.checkForeignKeys({ db: schema.db }), []

  it 'foreign_key_check surfaces a row inserted with enforcement off', ->
    schema.db.exec 'PRAGMA foreign_keys = OFF'
    try
      schema.db.prepare("""
        INSERT INTO tasks (id, project_id, name) VALUES ('orphan-task', 'no-such-project', 'ghost')
      """).run()
      findings = consistency.checkForeignKeys { db: schema.db }
      assert.ok findings.length > 0, 'an orphaned FK row must be reported'
      assert.equal findings[0].kind, 'db-foreign-key'
    finally
      schema.db.exec "DELETE FROM tasks WHERE id = 'orphan-task'"
      schema.db.exec 'PRAGMA foreign_keys = ON'
