# Pure-function tests for lib/services/period.coffee
# No DB, no fixtures — events are built inline so each test is self-contained.

{ test } = require 'node:test'
assert   = require 'node:assert/strict'

{ computeAllPeriods, computeMonth, resolveEditsAndDeletes, resolveConfig, monthKey } =
  require '../../lib/services/period.coffee'


# --- helpers ------------------------------------------------------------------

uid = 0
newId = -> uid += 1; "e#{uid}"

evt = (action, effective_for, payload, occurred_at = "2026-01-01T00:00:00Z", extras = {}) ->
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
payment = (ym, amount, occurred = "#{ym}-15T10:00:00Z") -> evt 'payment-made', ym, { amount }, occurred
configChange = (field, new_value, occurred = "2025-01-01T00:00:00Z") ->
  evt 'config-changed', null, { field, new_value }, occurred, { actor: 'landlord', actor_user: 'robert@defore.st' }
override = (ym, field, new_value, occurred = "#{ym}-20T00:00:00Z") ->
  evt 'override', ym, { target_kind: 'period-field', target: { field }, new_value }, occurred,
    { actor: 'landlord', actor_user: 'robert@defore.st' }

# fixed "now" so tests are deterministic
NOW = new Date '2026-06-11T12:00:00Z'


# --- basic math ---------------------------------------------------------------

test "no events → empty result", ->
  assert.deepEqual computeAllPeriods([], NOW), {}


test "single month, no work, no payment → full base rent", ->
  events = [ work('2026-04', 0) ]
  result = computeAllPeriods events, NOW
  apr    = result['2026-04']
  assert.equal apr.hours_worked,          0
  assert.equal apr.discount_applied,      0
  assert.equal apr.amount_due_calculated, 1600
  assert.equal apr.amount_due,            1600


test "5 hours worked → $250 credit, $1350 amount_due_calculated", ->
  events = [ work('2026-04', 5) ]
  apr    = computeAllPeriods(events, NOW)['2026-04']
  assert.equal apr.hours_worked,          5
  assert.equal apr.hours_applied,         5
  assert.equal apr.discount_applied,      250
  assert.equal apr.amount_due_calculated, 1350
  assert.equal apr.hours_to_next,         0


test "10 hours worked → cap at 8, carry 2 to next month", ->
  events = [ work('2026-04', 10) ]
  apr    = computeAllPeriods(events, NOW)['2026-04']
  assert.equal apr.hours_applied,         8
  assert.equal apr.discount_applied,      400
  assert.equal apr.amount_due_calculated, 1200
  assert.equal apr.hours_to_next,         2


test "payment-made events sum into amount_paid", ->
  events = [
    payment '2026-04', 500
    payment '2026-04', 700
  ]
  apr = computeAllPeriods(events, NOW)['2026-04']
  assert.equal apr.amount_paid, 1200


# --- carry-over + retroactive credit ------------------------------------------

test "retroactive credit retires prior shortfall (bug 05 case)", ->
  # April: 4 hours → 4 applied, shortfall = (8-4) * 50 = 200
  # May:   16 hours + 0 carry → 8 applied + 4 retro hours (200/50) = 200 retroactive
  events = [
    work '2026-04', 4
    work '2026-05', 16
  ]
  result = computeAllPeriods events, NOW
  apr = result['2026-04']
  may = result['2026-05']

  assert.equal apr.hours_applied,         4
  assert.equal apr.discount_applied,      200
  assert.equal apr.amount_due_calculated, 1400
  assert.equal apr.cumulative_shortfall,  200, "April leaves $200 shortfall"

  assert.equal may.hours_applied,        8
  assert.equal may.retroactive_credit,   200, "May retires April's full $200 shortfall"
  assert.equal may.total_discount,       600
  assert.equal may.amount_due_calculated, 1000
  assert.equal may.cumulative_shortfall,  0


test "carry-over hours flow forward", ->
  events = [
    work '2026-04', 12   # 8 applied, 4 carry
    work '2026-05', 3    # 3 + 4 carry = 7 applied
  ]
  result = computeAllPeriods events, NOW
  assert.equal result['2026-04'].hours_to_next,       4
  assert.equal result['2026-05'].hours_from_previous, 4
  assert.equal result['2026-05'].hours_applied,       7
  assert.equal result['2026-05'].discount_applied,    350


# --- edits, deletes, overrides ------------------------------------------------

test "edited work-reported uses new payload", ->
  w  = work '2026-04', 5
  ed = evt 'edited', null, { new_payload: { hours: 10 } }, "2026-04-15T00:00:00Z",
    { target_event_id: w.id, actor: 'tenant', actor_user: 'lynz57@hotmail.com' }
  apr = computeAllPeriods([ w, ed ], NOW)['2026-04']
  assert.equal apr.hours_worked, 10


test "deleted work-reported is ignored", ->
  w   = work '2026-04', 5
  d   = evt 'deleted', null, {}, "2026-04-15T00:00:00Z",
    { target_event_id: w.id, actor: 'tenant', actor_user: 'lynz57@hotmail.com' }
  # add a payment so April still gets enumerated after the work is deleted
  p   = payment '2026-04', 100
  apr = computeAllPeriods([ w, d, p ], NOW)['2026-04']
  assert.equal apr.hours_worked, 0
  assert.equal apr.amount_paid,  100


test "period-field override pins amount_due regardless of calc", ->
  events = [
    work '2026-04', 0    # would calc to $1600
    override '2026-04', 'amount_due', 1200
  ]
  apr = computeAllPeriods(events, NOW)['2026-04']
  assert.equal apr.amount_due_calculated, 1600
  assert.equal apr.amount_due,            1200
  assert.equal apr.amount_due_override,   true


test "period-field override pins amount_paid", ->
  events = [
    payment '2026-04', 500
    override '2026-04', 'amount_paid', 950
  ]
  apr = computeAllPeriods(events, NOW)['2026-04']
  assert.equal apr.amount_paid,          950
  assert.equal apr.amount_paid_override, true


# --- config snapshot ----------------------------------------------------------

test "config-changed shifts numbers for periods after the change", ->
  events = [
    configChange 'base_rent', 1800, "2026-05-01T00:00:00Z"
    work '2026-04', 0
    work '2026-05', 0
  ]
  result = computeAllPeriods events, NOW
  assert.equal result['2026-04'].base_rent,             1600, "April predates the change"
  assert.equal result['2026-04'].amount_due_calculated, 1600
  assert.equal result['2026-05'].base_rent,             1800, "May sees the new value"
  assert.equal result['2026-05'].amount_due_calculated, 1800


# --- stress-free display + payment status -------------------------------------

test "current month before the 15th: display_amount_due = 0, status NOT DUE", ->
  events = [ work '2026-06', 0 ]
  jun    = computeAllPeriods(events, NOW)['2026-06']
  assert.equal jun.display_amount_due, 0
  assert.equal jun.payment_status,     'NOT DUE'


test "past month with no payment: display=$950, status UNPAID", ->
  events = [ work '2026-04', 0 ]
  apr    = computeAllPeriods(events, NOW)['2026-04']
  assert.equal apr.display_amount_due, 950
  assert.equal apr.payment_status,     'UNPAID'


test "past month fully paid agreed_payment: PAID", ->
  events = [ work('2026-04', 0), payment('2026-04', 950) ]
  apr    = computeAllPeriods(events, NOW)['2026-04']
  assert.equal apr.display_amount_due, 950
  assert.equal apr.payment_status,     'PAID'


# --- regression: no phantom "rent_due" event biting the calc ------------------

test "regression: model has no slot for the old type=manual amount=-1600 events", ->
  # In the new model there's no 'manual' action and no metadata.category
  # path that could double-count BASE_RENT. This test asserts that an
  # incoming events array containing only legitimate work/payment events
  # produces a correct amount_due regardless of how cluttered the surrounding
  # event log might be.
  events = [
    work '2026-05', 4
    work '2026-04', 12
    payment '2026-05', 0
  ]
  may = computeAllPeriods(events, NOW)['2026-05']
  # April carries 4 to May. May has 4 worked + 4 carry = 8 applied = $400 discount.
  # amount_due_calculated = $1600 - $400 = $1200.
  assert.equal may.amount_due_calculated, 1200, "no phantom -$1600 event can leak in"


# --- helpers themselves -------------------------------------------------------

test "monthKey zero-pads single-digit months", ->
  assert.equal monthKey(2026, 4),  '2026-04'
  assert.equal monthKey(2026, 12), '2026-12'


test "resolveConfig returns defaults if no config events", ->
  snap = resolveConfig [], new Date '2026-06-01T00:00:00Z'
  assert.equal snap.base_rent,              1600
  assert.equal snap.agreed_monthly_payment, 950


test "resolveEditsAndDeletes preserves non-edit events untouched", ->
  events = [ work('2026-04', 5), payment('2026-04', 100) ]
  out    = resolveEditsAndDeletes events
  assert.equal out.length, 2
