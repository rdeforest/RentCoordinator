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


test "past month with no payment: display = full calculated, status UNPAID", ->
  # Past months show the real amount owed, not the stress-free agreed_payment.
  # The temporary $950 arrangement that the dashboard used to mask with is
  # not a permanent fixture — when it's not active, past months must be honest.
  events = [ work '2026-04', 0 ]
  apr    = computeAllPeriods(events, NOW)['2026-04']
  assert.equal apr.display_amount_due, 1600
  assert.equal apr.payment_status,     'UNPAID'


test "past month fully paid against override: PAID", ->
  # The agreed-payment masking is now expressed as an explicit override
  # event, not a global fallback. This still lets historical months pinned
  # at $950 display as such, while uncovered months show their calculation.
  events = [ work('2026-04', 0), payment('2026-04', 950), override('2026-04', 'amount_due', 950) ]
  apr    = computeAllPeriods(events, NOW)['2026-04']
  assert.equal apr.display_amount_due, 950
  assert.equal apr.payment_status,     'PAID'


test "past month with calc=$1200 and no override: shows $1200 (the bug 2026-06-12)", ->
  # April 2026: 16h carry from March + 4h worked = 8 applied = $400 credit
  # → $1600 - $400 = $1200. No override events. Used to display $950
  # because the stress-free fallback applied agreed_monthly_payment to past
  # months. Now displays the real $1200.
  events = [
    work '2026-03', 16
    work '2026-04', 4
  ]
  apr = computeAllPeriods(events, NOW)['2026-04']
  assert.equal apr.amount_due_calculated, 1200
  assert.equal apr.display_amount_due,    1200, "no more $950 mask on uncovered past months"


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


test "a landlord-recorded payment still counts toward amount_paid (bug 51)", ->
  # POST /rent/events stamps actor: 'landlord' for anything the landlord
  # records, including a payment. Only work-reported credit is tenant-only.
  landlordPayment = Object.assign {}, payment('2026-04', 500),
    { actor: 'landlord', actor_user: 'robert@defore.st' }
  apr = computeAllPeriods([ landlordPayment ], NOW)['2026-04']
  assert.equal apr.amount_paid, 500


test "non-tenant work-reported events don't count toward credit", ->
  tenantWork   = work '2026-04', 5
  landlordWork = Object.assign {}, work('2026-04', 100), { actor: 'landlord', actor_user: 'robert@defore.st' }
  apr = computeAllPeriods([ tenantWork, landlordWork ], NOW)['2026-04']
  assert.equal apr.hours_worked, 5, "only the tenant's 5 hours count"


test "period-suppressed hides month from default output", ->
  suppress = (ym) ->
    evt 'period-suppressed', ym, { reason: 'test' }, "#{ym}-15T00:00:00Z",
      { actor: 'landlord', actor_user: 'robert@defore.st' }

  events = [
    work '2026-03', 4
    work '2026-04', 4
    suppress '2026-04'
  ]
  result = computeAllPeriods events, NOW
  assert.equal result['2026-03']?, true,  "March still visible"
  assert.equal result['2026-04']?, false, "April hidden by suppression"


test "period-suppressed: carry-over still flows through hidden month", ->
  suppress = (ym) ->
    evt 'period-suppressed', ym, { reason: 'test' }, "#{ym}-15T00:00:00Z",
      { actor: 'landlord', actor_user: 'robert@defore.st' }

  events = [
    work '2026-03', 12         # 8 applied, 4 carry to April
    work '2026-04', 0
    suppress '2026-04'
    work '2026-05', 3          # April's 4 carry + 3 worked = 7 applied if April carries
  ]
  result = computeAllPeriods events, NOW
  # April carries 4 hours of credit forward despite being suppressed
  assert.equal result['2026-05'].hours_from_previous, 4
  assert.equal result['2026-05'].hours_applied,        7
  assert.equal result['2026-05'].discount_applied,    350


test "period-suppressed: includeSuppressed=true brings it back", ->
  suppress = (ym) ->
    evt 'period-suppressed', ym, { reason: 'test' }, "#{ym}-15T00:00:00Z",
      { actor: 'landlord', actor_user: 'robert@defore.st' }

  events = [ work('2026-04', 5), suppress('2026-04') ]
  result = computeAllPeriods events, NOW, { includeSuppressed: true }
  assert.equal result['2026-04']?, true
  assert.equal result['2026-04'].suppressed, true


test "resolveEditsAndDeletes preserves non-edit events untouched", ->
  events = [ work('2026-04', 5), payment('2026-04', 100) ]
  out    = resolveEditsAndDeletes events
  assert.equal out.length, 2


# --- additive adjustments (bug 14) -------------------------------------------

adjustment = (ym, delta, occurred = "#{ym}-20T00:00:00Z") ->
  evt 'adjustment', ym, { target_kind: 'period-field', target: { field: 'amount_due' }, delta }, occurred,
    { actor: 'landlord', actor_user: 'robert@defore.st' }

deleteOf = (target, occurred) ->
  evt 'deleted', null, { reason: 'test' }, occurred, { target_event_id: target.id }

undeleteOf = (target, occurred) ->
  evt 'undeleted', null, {}, occurred, { target_event_id: target.id }


test "an adjustment adds to the amount due instead of replacing it (bug 14)", ->
  periods = computeAllPeriods [work('2026-01', 0), adjustment('2026-01', 100)], NOW
  p       = periods['2026-01']

  assert.equal p.amount_due, 1700,
    'a $100 late fee on a $1,600 month leaves $1,700 owing, not $100'
  assert.equal p.adjustment_total, 100
  assert.equal p.amount_due_override, false,
    'an adjustment must not pin the month as manually overridden'


test "a negative adjustment reduces the amount due", ->
  periods = computeAllPeriods [work('2026-01', 0), adjustment('2026-01', -250)], NOW
  assert.equal periods['2026-01'].amount_due, 1350


test "adjustments accumulate, and stack on top of work credit", ->
  events  = [work('2026-01', 4), adjustment('2026-01', 100), adjustment('2026-01', 25)]
  periods = computeAllPeriods events, NOW

  assert.equal periods['2026-01'].amount_due, 1600 - 200 + 125


test "an override still pins the month absolutely", ->
  periods = computeAllPeriods [work('2026-01', 0), override('2026-01', 'amount_due', 100)], NOW
  p       = periods['2026-01']

  assert.equal p.amount_due, 100, 'an override is an absolute pin — unchanged behaviour'
  assert.equal p.amount_due_override, true


test "an override wins over an adjustment made before it (bug 56)", ->
  # adjustment() defaults occurred_at to the 20th; override() also defaults to
  # the 20th, so give the adjustment an explicit earlier time to make "before
  # the override" unambiguous.
  events  = [
    work('2026-01', 0)
    adjustment('2026-01', 100, '2026-01-10T00:00:00Z')
    override('2026-01', 'amount_due', 500, '2026-01-20T00:00:00Z')
  ]
  periods = computeAllPeriods events, NOW

  assert.equal periods['2026-01'].amount_due, 500,
    'an adjustment made before the pin is superseded by it, same as if it had never happened'
  assert.equal periods['2026-01'].amount_due_calculated, 1700,
    'the calculated value still reflects the adjustment underneath the pin'


test "an adjustment made after an override applies on top of the pin (bug 56)", ->
  # The landlord pins the month at $500, then adds a $100 late fee afterward.
  # The fee must not be silently dropped just because a pin already exists.
  events  = [
    work('2026-01', 0)
    override('2026-01', 'amount_due', 500, '2026-01-10T00:00:00Z')
    adjustment('2026-01', 100, '2026-01-20T00:00:00Z')
  ]
  periods = computeAllPeriods events, NOW

  assert.equal periods['2026-01'].amount_due, 600,
    'the later adjustment applies on top of the pin: 500 + 100'
  assert.equal periods['2026-01'].amount_due_override, true


test "the later amount_due override wins by occurred_at, not array position (bug 66)", ->
  # The smaller-valued override is later in time but first in the array — if
  # the fold picked "last event seen" instead of "latest occurred_at" this
  # would come out 800, not 500.
  events  = [
    work('2026-01', 0)
    override('2026-01', 'amount_due', 500, '2026-01-20T00:00:00Z')
    override('2026-01', 'amount_due', 800, '2026-01-10T00:00:00Z')
  ]
  periods = computeAllPeriods events, NOW

  assert.equal periods['2026-01'].amount_due, 500,
    'the override at 01-20 is the latest by occurred_at and must win over the earlier 01-10 one'


test "an adjustment at the same occurred_at as the override is superseded by it, not after it (bug 66)", ->
  # Equal is not "after" — an adjustment recorded at the exact instant of the
  # pin does not get to apply on top of it.
  events  = [
    work('2026-01', 0)
    adjustment('2026-01', 100, '2026-01-20T00:00:00Z')
    override('2026-01', 'amount_due', 500, '2026-01-20T00:00:00Z')
  ]
  periods = computeAllPeriods events, NOW

  assert.equal periods['2026-01'].amount_due, 500,
    'an adjustment at the same instant as the override is treated as not-after it, so it is superseded rather than added on top (500, not 600)'


test "the later amount_paid override wins by occurred_at, not array position (bug 66)", ->
  events  = [
    payment('2026-01', 100)
    override('2026-01', 'amount_paid', 500, '2026-01-20T00:00:00Z')
    override('2026-01', 'amount_paid', 800, '2026-01-10T00:00:00Z')
  ]
  periods = computeAllPeriods events, NOW

  assert.equal periods['2026-01'].amount_paid, 500,
    'the amount_paid override at 01-20 is the latest by occurred_at and must win over the earlier 01-10 one'


test "a payment at the same occurred_at as the amount_paid override is superseded by it, not after it (bug 66)", ->
  events  = [
    payment('2026-01', 100, '2026-01-20T00:00:00Z')
    override('2026-01', 'amount_paid', 500, '2026-01-20T00:00:00Z')
  ]
  periods = computeAllPeriods events, NOW

  assert.equal periods['2026-01'].amount_paid, 500,
    'a payment at the same instant as the amount_paid override is treated as not-after it, so it is superseded rather than added on top (500, not 600)'


test "an amount_paid override stands against a payment recorded after it (bug 66)", ->
  events  = [
    override('2026-01', 'amount_paid', 500, '2026-01-10T00:00:00Z')
    payment('2026-01', 100, '2026-01-20T00:00:00Z')
  ]
  periods = computeAllPeriods events, NOW

  assert.equal periods['2026-01'].amount_paid, 500,
    'a later payment is usually the one the pin describes (an ACH settling); adding it double-counts'
  assert.equal periods['2026-01'].amount_paid_override, true


# --- delete / undelete (bug 16) ----------------------------------------------

test "undelete restores an event to the fold (bug 16)", ->
  p1 = payment '2026-01', 500
  d  = deleteOf   p1, '2026-02-01T00:00:00Z'
  u  = undeleteOf p1, '2026-02-02T00:00:00Z'

  assert.equal computeAllPeriods([work('2026-01', 0), p1], NOW)['2026-01'].amount_paid, 500
  assert.equal computeAllPeriods([work('2026-01', 0), p1, d], NOW)['2026-01'].amount_paid, 0,
    'the delete still removes it'
  assert.equal computeAllPeriods([work('2026-01', 0), p1, d, u], NOW)['2026-01'].amount_paid, 500,
    'the undelete must bring it back — this was the no-op'


test "delete → undelete → delete resolves to deleted, by time not by count", ->
  p1     = payment '2026-01', 500
  events = [
    work('2026-01', 0)
    p1
    deleteOf   p1, '2026-02-01T00:00:00Z'
    undeleteOf p1, '2026-02-02T00:00:00Z'
    deleteOf   p1, '2026-02-03T00:00:00Z'
  ]

  assert.equal computeAllPeriods(events, NOW)['2026-01'].amount_paid, 0


test "order is by occurred_at, not by position in the array", ->
  p1     = payment '2026-01', 500
  events = [
    work('2026-01', 0)
    p1
    undeleteOf p1, '2026-02-09T00:00:00Z'   # later, but listed first
    deleteOf   p1, '2026-02-01T00:00:00Z'
  ]

  assert.equal computeAllPeriods(events, NOW)['2026-01'].amount_paid, 500,
    'the undelete happened last in time, so the event is live'


test "deletedEventIds reports what the events list should mark deleted", ->
  { deletedEventIds } = require '../../lib/services/period.coffee'

  p1 = payment '2026-01', 500
  p2 = payment '2026-01', 300
  d1 = deleteOf p1, '2026-02-01T00:00:00Z'

  ids = deletedEventIds [p1, p2, d1]
  assert.ok  ids.has(p1.id), 'the deleted event is reported'
  assert.ok !ids.has(p2.id), 'an untouched event is not'
  assert.ok !ids.has(d1.id),
    'the delete event itself is not deleted — targeting it was the old undelete bug'

  ids2 = deletedEventIds [p1, p2, d1, undeleteOf(p1, '2026-02-02T00:00:00Z')]
  assert.ok !ids2.has(p1.id), 'and an undelete clears it'


# --- what is owed -------------------------------------------------------------
#
# This is the rule that decides what the tenant is billed: /payment/create-intent
# creates a Stripe intent from it and /rent/outstanding displays it. It lived in
# period_viewer, which cannot be reached without a database, so it had no test.

{ computeOutstanding } = require '../../lib/services/period.coffee'

owedFrom = (events, now) -> computeOutstanding computeAllPeriods events, now

# computeAllPeriods walks every month from the first with activity through the
# current one — rent is owed whether or not anything was logged that month. So
# each test anchors "now" just after the months it cares about, where the
# current month is still NOT DUE and therefore excluded.
earlyIn = (year, month) -> new Date "#{year}-#{String(month).padStart 2, '0'}-10T12:00:00Z"


test "a month paid in full is not outstanding", ->
  owed = owedFrom [work('2026-01', 0), payment('2026-01', 1600)], earlyIn 2026, 2

  assert.deepEqual owed.months, []
  assert.equal     owed.total, 0


test "a month paid to the cent is settled, despite float residue", ->
  # 200 minutes of work credits $166.666…, so the month owes $1,433.33 — and
  # raw float subtraction left it owing a third of a cent for ever.
  events = [work('2026-01', 200 / 60)]
  due    = computeAllPeriods(events, earlyIn 2026, 2)['2026-01'].display_amount_due

  assert.deepEqual owedFrom([events..., payment('2026-01', due)], earlyIn 2026, 2).months, []


test "an unpaid past month is owed in full", ->
  [row] = owedFrom([work('2026-01', 0)], earlyIn 2026, 2).months

  assert.equal row.owed,        1600
  assert.equal row.paid,        0
  assert.equal row.outstanding, 1600


test "a partly paid month is owed the remainder", ->
  [row] = owedFrom([work('2026-01', 0), payment('2026-01', 600)], earlyIn 2026, 2).months
  assert.equal row.outstanding, 1000


test "an overpaid month does not cancel out a month that is owed", ->
  events = [
    work('2026-01', 0), payment('2026-01', 5000)   # wildly overpaid
    work('2026-02', 0)                             # and nothing paid here
  ]
  { total, months } = owedFrom events, earlyIn 2026, 3

  assert.equal months.length, 1, 'only the unpaid month is listed'
  assert.equal months[0].month, 2
  assert.equal total, 1600, 'the overpayment must not reduce what February owes'


test "the current month before the due date is not yet owed", ->
  months = owedFrom([work('2026-06', 0)], earlyIn 2026, 6).months

  assert.deepEqual months, [], 'NOT DUE months are excluded from what is owed'


test "months come back oldest first, so a payment is applied to the oldest debt", ->
  events = [work('2026-03', 0), work('2026-01', 0), work('2026-02', 0)]
  order  = owedFrom(events, earlyIn 2026, 4).months.map (r) -> "#{r.year}-#{r.month}"

  assert.deepEqual order, ['2026-1', '2026-2', '2026-3']


test "the total is the sum of the months, to the cent", ->
  events = [work('2026-01', 200 / 60), work('2026-02', 100 / 60)]
  { total, months } = owedFrom events, earlyIn 2026, 3

  assert.equal total, months.reduce ((s, r) -> s + r.outstanding), 0
  assert.equal total, Math.round(total * 100) / 100, 'and it is a payable amount'


test "a corrupt month is flagged, not quietly dropped", ->
  # NaN > 0 is false, so filtering on the number alone would have removed the
  # month from both the list and the total — reporting "you are paid up" for a
  # month nobody can reason about.
  events = [work('2026-01', 0), override('2026-01', 'amount_due', NaN)]
  { months, corrupt, total } = owedFrom events, earlyIn 2026, 2

  assert.equal months.length,  1
  assert.equal corrupt.length, 1, 'the month is reported'
  assert.equal corrupt[0].month, 1
  assert.equal total, 0, 'and contributes nothing to a figure anyone is billed'


test "one corrupt month does not stop the others being paid", ->
  # Throwing from the aggregate meant a single bad historical row blocked the
  # tenant from paying any month at all, and showed a raw internal message.
  events = [
    work('2026-01', 0), override('2026-01', 'amount_due', NaN)
    work('2026-02', 0)
  ]
  { months, corrupt, total } = owedFrom events, earlyIn 2026, 3

  assert.equal total, 1600, 'February is still payable'
  assert.equal corrupt.length, 1
  assert.equal months.length,  2, 'and both months are still listed'


test "computeMonth marks the month so every route agrees", ->
  # /rent/period used to serve the row as null while /rent/outstanding threw.
  periods = computeAllPeriods [work('2026-01', 0), override('2026-01', 'amount_due', NaN)], earlyIn 2026, 2

  assert.equal periods['2026-01'].corrupt, true
  assert.equal periods['2026-02'].corrupt, false


# --- the current month, after the due date ------------------------------------
#
# Every test above this point puts "now" before the 15th, so the branch that
# decides what the tenant sees for the second half of every month was computed
# by nothing. These pin "now" after the due date.

AFTER_DUE  = new Date '2026-06-20T12:00:00Z'   # current month = 2026-06, past the 15th
ON_DUE_DAY = new Date '2026-06-15T09:00:00Z'
DAY_BEFORE = new Date '2026-06-14T23:00:00Z'

currentMonth = (events, now) -> computeAllPeriods(events, now)['2026-06']


test "current month on the due date shows the agreed payment, not the full rent", ->
  p = currentMonth [work('2026-06', 0)], ON_DUE_DAY

  assert.equal p.display_amount_due, 950, 'the 15th is due, not the day before due'
  assert.equal p.amount_due,         1600, 'while the real figure is untouched underneath'
  assert.notEqual p.payment_status,  'NOT DUE'


test "the day before the due date is still NOT DUE", ->
  p = currentMonth [work('2026-06', 0)], DAY_BEFORE

  assert.equal p.display_amount_due, 0
  assert.equal p.payment_status,     'NOT DUE'


test "current month after the due date, nothing paid: UNPAID at the agreed payment", ->
  p = currentMonth [work('2026-06', 0)], AFTER_DUE

  assert.equal p.display_amount_due, 950
  assert.equal p.payment_status,     'UNPAID'


test "current month after the due date, agreed payment received: PAID", ->
  p = currentMonth [work('2026-06', 0), payment('2026-06', 950)], AFTER_DUE

  assert.equal p.payment_status, 'PAID',
    'paying the displayed figure settles the month, even though $1,600 is owed underneath'


test "current month after the due date, part paid: PARTIAL", ->
  p = currentMonth [work('2026-06', 0), payment('2026-06', 400)], AFTER_DUE

  assert.equal p.payment_status, 'PARTIAL'


test "work credit does not reduce what the current month displays after the due date", ->
  # The mask is a flat agreed payment; the credit shows up in the real figure.
  p = currentMonth [work('2026-06', 4)], AFTER_DUE

  assert.equal p.display_amount_due, 950,  'the tenant still sees the agreed payment'
  assert.equal p.amount_due,         1400, 'and the credit is real underneath it'
  assert.equal p.discount_applied,   200


test "an override pins the current month even after the due date", ->
  p = currentMonth [work('2026-06', 0), override('2026-06', 'amount_due', 725)], AFTER_DUE

  assert.equal p.display_amount_due, 725, 'a pinned month shows the pin, not the mask'
  assert.equal p.amount_due_override, true


test "a future month shows the real figure, never the mask", ->
  p = computeAllPeriods([work('2026-06', 0), work('2026-08', 0)], AFTER_DUE)['2026-08']

  assert.equal p.display_amount_due, 1600


test "the current month after the due date is owed, and enters the outstanding total", ->
  # computeOutstanding drops NOT DUE months. Before the 15th the current month
  # is excluded; after it, it has to appear or the tenant cannot pay it.
  events = [work('2026-06', 0)]

  assert.deepEqual owedFrom(events, DAY_BEFORE).months, [], 'not yet'

  { months, total } = owedFrom events, AFTER_DUE
  assert.equal months.length, 1
  assert.equal months[0].month, 6
  assert.equal total, 950, 'and it is the displayed figure that is billed, not $1,600'


# --- the temporary rent override ---------------------------------------------
#
# apply_override + temporary_rent_amount replace the agreed payment. Nothing
# tested that it changes a number — only that the config value round-trips.

test "a temporary rent amount replaces the agreed payment once applied", ->
  events = [
    work('2026-06', 0)
    configChange 'temporary_rent_amount', 700
    configChange 'apply_override',        true
  ]
  p = currentMonth events, AFTER_DUE

  assert.equal p.agreed_payment,     700
  assert.equal p.display_amount_due, 700, 'this is what the tenant is asked for'
  assert.equal owedFrom(events, AFTER_DUE).total, 700


test "a temporary amount that is not applied changes nothing", ->
  events = [work('2026-06', 0), configChange 'temporary_rent_amount', 700]
  p = currentMonth events, AFTER_DUE

  assert.equal p.agreed_payment,     950
  assert.equal p.display_amount_due, 950


test "apply_override with no amount falls back to the configured payment", ->
  events = [work('2026-06', 0), configChange 'apply_override', true]

  assert.equal currentMonth(events, AFTER_DUE).display_amount_due, 950


test "clearing the amount reverts the month, even with the override still on", ->
  # Bug 20: an explicit null is a clear. The fold has to honour it.
  events = [
    work('2026-06', 0)
    configChange 'temporary_rent_amount', 700,  '2025-01-01T00:00:00Z'
    configChange 'apply_override',        true, '2025-01-02T00:00:00Z'
    configChange 'temporary_rent_amount', null, '2025-01-03T00:00:00Z'
  ]

  assert.equal currentMonth(events, AFTER_DUE).display_amount_due, 950


test "a temporary amount does not reach into past months", ->
  events = [
    work('2026-05', 0), work('2026-06', 0)
    configChange 'temporary_rent_amount', 700
    configChange 'apply_override',        true
  ]
  periods = computeAllPeriods events, AFTER_DUE

  assert.equal periods['2026-05'].display_amount_due, 1600,
    'past months show what was actually owed; the mask is current-month only'
  assert.equal periods['2026-06'].display_amount_due, 700
