# Pure functions for computing rent periods from an event log.
# No DB access, no persistence (config.coffee is pure constants). Caller
# passes events in, gets period views out. See docs/event-model.md.

config = require '../config.coffee'
money  = require '../money.coffee'


# Baseline the event fold starts from; config-changed events override these.
# Values come from config.coffee so the rent math and the /rent/constants
# endpoint can't drift apart (was bug 39 — these were hardcoded here too).
DEFAULT_CONFIG =
  base_rent:              config.BASE_RENT
  hourly_credit:          config.HOURLY_CREDIT
  max_monthly_hours:      config.MAX_MONTHLY_HOURS
  agreed_monthly_payment: config.AGREED_MONTHLY_PAYMENT
  rent_due_day:           config.RENT_DUE_DAY
  temporary_rent_amount:  null
  apply_override:         false


monthKey = (year, month) ->
  "#{year}-#{String(month).padStart 2, '0'}"


parseMonthKey = (key) ->
  [y, m] = key.split('-').map (n) -> parseInt n, 10
  { year: y, month: m }


META_ACTIONS = ['edited', 'deleted', 'undeleted']


# Which event ids are currently deleted. A delete and a later undelete both
# target the *original* event, so the answer is whichever came last — a
# delete/undelete/delete sequence resolves to deleted. Ordering is by
# occurred_at with the event id as tiebreak, matching the order the events
# model returns rows in.
deletedEventIds = (events) ->
  state = new Map()

  ordered = events
    .filter (e) -> e.action in ['deleted', 'undeleted'] and e.target_event_id
    .sort   (a, b) -> a.occurred_at.localeCompare(b.occurred_at) or a.id.localeCompare b.id

  for e in ordered
    state.set e.target_event_id, e.action is 'deleted'

  new Set (id for [id, isDeleted] from state when isDeleted)


# Every non-meta event with its edits folded in, deleted or not. `edited`
# events merge their new_payload onto the original, last write wins.
#
# Kept separate from the delete filter because the events list needs the
# edited payload for deleted rows too — folding and filtering together meant a
# deleted event displayed its pre-edit amount.
applyEdits = (events) ->
  byId = new Map()
  for e in events when e.action not in META_ACTIONS
    byId.set e.id, e

  for e in events when e.action is 'edited' and byId.has e.target_event_id
    orig    = byId.get e.target_event_id
    payload = Object.assign {}, orig.payload, e.payload.new_payload

    # `new_fields` replaces top-level columns — which month the event applies
    # to, and whose work it was. A work log corrected to a different date has
    # to take its rent credit with it. `id` and `action` are not replaceable:
    # an edit changes what an event says, not which event it is.
    fields = Object.assign {}, e.payload.new_fields
    delete fields[key] for key in ['id', 'action', 'target_event_id']

    byId.set e.target_event_id, Object.assign {}, orig, fields, { payload }

  Array.from byId.values()


# Given the raw event log, return events with edits applied and deletes
# removed. Pure — does not touch the input array.
resolveEditsAndDeletes = (events) ->
  deleted = deletedEventIds events
  (e for e in applyEdits events when not deleted.has e.id)


# Fold every config-changed event with occurred_at <= asOf into a config
# snapshot. asOf is a Date. Events should already have edits/deletes resolved.
resolveConfig = (events, asOf) ->
  configEvents = events
    .filter (e) -> e.action is 'config-changed' and new Date(e.occurred_at) <= asOf
    .sort (a, b) -> a.occurred_at.localeCompare b.occurred_at

  snapshot = Object.assign {}, DEFAULT_CONFIG
  for e in configEvents
    snapshot[e.payload.field] = e.payload.new_value
  snapshot


# Compute one month's view. Caller supplies carryOver hours from the previous
# month and shortfall accumulated from prior months. Returns the full period
# object the UI consumes.
computeMonth = (year, month, allEvents, carryOver, shortfall, now) ->
  ymKey       = monthKey year, month
  endOfMonth  = new Date Date.UTC(year, month, 0, 23, 59, 59)
  config      = resolveConfig allEvents, endOfMonth
  monthEvents = allEvents.filter (e) -> e.effective_for is ymKey

  hours_worked = 0
  amount_paid  = 0
  for e in monthEvents when e.actor is 'tenant'
    switch e.action
      when 'work-reported' then hours_worked += e.payload.hours
      when 'payment-made'  then amount_paid  += e.payload.amount

  total_available    = hours_worked + carryOver
  base_hours_applied = Math.min total_available, config.max_monthly_hours
  base_discount      = base_hours_applied * config.hourly_credit

  retroactive_credit = 0
  if shortfall > 0 and total_available > config.max_monthly_hours
    extra_hours        = total_available - config.max_monthly_hours
    max_retro_hours    = Math.min extra_hours, shortfall / config.hourly_credit
    retroactive_credit = max_retro_hours * config.hourly_credit

  total_discount = base_discount + retroactive_credit
  hours_used     = base_hours_applied + (retroactive_credit / config.hourly_credit)

  # Adjustments move the amount owed; they do not replace it. A $100 late fee
  # on a $1,600 month leaves $1,700 owing, and the month is still calculated
  # rather than pinned. Overrides below are the only thing that pins a value.
  adjustment_total = 0
  for e in monthEvents when e.action is 'adjustment' and e.payload.target?.field is 'amount_due'
    adjustment_total += e.payload.delta

  amount_due_calculated = config.base_rent - total_discount + adjustment_total
  amount_due            = amount_due_calculated
  amount_due_override   = false
  amount_paid_override  = false

  for e in monthEvents when e.action is 'override' and e.payload.target_kind is 'period-field'
    if e.payload.target?.field is 'amount_due'
      amount_due          = e.payload.new_value
      amount_due_override = true
    if e.payload.target?.field is 'amount_paid'
      amount_paid          = e.payload.new_value
      amount_paid_override = true

  cumulative_shortfall = shortfall - retroactive_credit
  if base_hours_applied < config.max_monthly_hours
    cumulative_shortfall += (config.max_monthly_hours - base_hours_applied) * config.hourly_credit

  agreed_payment = if config.apply_override and config.temporary_rent_amount?
    config.temporary_rent_amount
  else
    config.agreed_monthly_payment

  is_current = year is now.getFullYear() and month is (now.getMonth() + 1)
  is_future  = year > now.getFullYear() or (year is now.getFullYear() and month > (now.getMonth() + 1))

  # Past months show the real amount owed (calculated, or override if pinned).
  # The "stress-free agreed_payment" mask only applies to the current month —
  # and only after the due date — so the dashboard doesn't broadcast
  # "$1600 overdue!" the moment the new month rolls over. For historical
  # months, honesty wins.
  display_amount_due =
    if      amount_due_override then amount_due
    else if is_future           then amount_due
    else if is_current          then (if now.getDate() < config.rent_due_day then 0 else agreed_payment)
    else                             amount_due

  payment_status =
    if      is_current and now.getDate() < config.rent_due_day    then 'NOT DUE'
    else if money.cents(amount_paid) >= money.cents(display_amount_due) then 'PAID'
    else if money.cents(amount_paid) > 0                          then 'PARTIAL'
    else                                                               'UNPAID'

  # Every value the dashboard shows as money leaves this function rounded to
  # the cent. An hourly credit on fractional hours produces amounts like
  # $1,433.3333333333333, which no payment method can settle exactly — the
  # month would read PARTIAL for ever over a third of a cent (bug 35).
  #
  # Hours and cumulative_shortfall stay unrounded. Neither is displayed; both
  # are carried into the next month's arithmetic, and rounding a running
  # balance before feeding it forward makes it drift against the exact figure.
  # A value that is not a number cannot be reasoned about, and every route has
  # to say so the same way. Marking the month here means /rent/period,
  # /rent/summary and /rent/outstanding agree, instead of one throwing while
  # another serves null.
  corrupt = not (Number.isFinite(amount_due) and Number.isFinite(amount_paid))

  {
    year, month
    corrupt
    hours_worked
    hours_from_previous:      carryOver
    hours_to_next:            total_available - hours_used
    hours_applied:            base_hours_applied
    discount_applied:         money.dollars base_discount
    retroactive_credit:       money.dollars retroactive_credit
    total_discount:           money.dollars total_discount
    base_rent:                money.dollars config.base_rent
    agreed_payment:           money.dollars agreed_payment
    effective_agreed_payment: money.dollars agreed_payment
    amount_due:               money.dollars amount_due
    amount_due_calculated:    money.dollars amount_due_calculated
    adjustment_total:         money.dollars adjustment_total
    amount_due_override
    amount_paid:              money.dollars amount_paid
    amount_paid_override
    display_amount_due:       money.dollars display_amount_due
    payment_status
    cumulative_shortfall
  }


# Fold every event into a map of monthKey → period view. Walks every month
# from the first month with activity through the current month, so months
# with only carry-over (no work-reported, no payment-made) still appear.
# Future months are not computed here — caller can computeMonth for those.
#
# opts.includeSuppressed (default false): if true, include months that have
# a `period-suppressed` event; otherwise skip them. Suppression hides a
# period from the dashboard ("this month isn't part of the rent arrangement")
# without destroying the underlying work-reported events.
#
# Carry-over still flows through suppressed months — the hours Lyndzie
# worked are still hers, even if the landlord said "don't bill this month."
computeAllPeriods = (events, now = new Date(), opts = {}) ->
  resolved = resolveEditsAndDeletes events

  suppressed = new Set()
  for e in resolved when e.action is 'period-suppressed' and e.effective_for
    suppressed.add e.effective_for

  monthKeys = new Set()
  for e in resolved when e.effective_for
    monthKeys.add e.effective_for

  return {} if monthKeys.size is 0

  sorted = [...monthKeys].sort()
  first  = parseMonthKey sorted[0]
  last   = parseMonthKey sorted[sorted.length - 1]

  currentY = now.getFullYear()
  currentM = now.getMonth() + 1
  if currentY > last.year or (currentY is last.year and currentM > last.month)
    last = { year: currentY, month: currentM }

  result    = {}
  carryOver = 0
  shortfall = 0
  { year, month } = first

  loop
    key = monthKey year, month
    if suppressed.has key
      # Suppression takes the month out of the rent calculation entirely:
      # work hours don't credit, payments don't apply, carry-over from the
      # previous month passes through unchanged. Conceptually: "this month
      # isn't part of the rent arrangement; whatever Lyndzie did that month
      # was for some other reason." includeSuppressed surfaces it in the
      # output for display (with `suppressed: true`) without affecting math.
      if opts.includeSuppressed
        period = computeMonth year, month, resolved, carryOver, shortfall, now
        result[key] = Object.assign {}, period, suppressed: true
    else
      period = computeMonth year, month, resolved, carryOver, shortfall, now
      result[key] = period
      carryOver  = period.hours_to_next
      shortfall  = period.cumulative_shortfall

    break if year is last.year and month is last.month
    month += 1
    if month > 12
      month  = 1
      year  += 1

  result


# What is actually owed, oldest month first. Months still NOT DUE are excluded
# — they can be paid early, but they are not part of "what do I owe".
#
# Pure, and here rather than in period_viewer, because this is the rule that
# decides what the tenant is billed: /payment/create-intent creates a Stripe
# intent from it and /rent/outstanding displays it. In period_viewer it could
# not be tested without a database, so it had no unit test at all.
computeOutstanding = (periods) ->
  rows = Object.values(periods)
    .filter (p) -> p.payment_status isnt 'NOT DUE'
    .map (p) ->
      owed = p.display_amount_due
      paid = p.amount_paid or 0
      outstanding = if p.corrupt then 0 else Math.max 0, money.minus owed, paid
      { year: p.year, month: p.month, owed, paid, outstanding, corrupt: p.corrupt is true }
    .filter (r) ->
      # A corrupt month is reported, not billed and not silently dropped:
      # `NaN > 0` is false, so filtering on the number alone would have made it
      # vanish from both the list and the total — "you are paid up".
      return true if r.corrupt

      # A month settled to the cent is settled; comparing raw floats left
      # fully-paid months outstanding by fractions of a cent (bug 35).
      money.cents(r.outstanding) > 0
    .sort (a, b) -> (a.year - b.year) or (a.month - b.month)

  # A corrupt month contributes nothing to the total — billing a figure nobody
  # can compute would be worse than showing it as unresolved — but it stays in
  # the list, flagged, so the page can say so.
  total:  money.dollars rows.reduce ((s, r) -> s + r.outstanding), 0
  months: rows
  corrupt: (r for r in rows when r.corrupt)


module.exports = {
  DEFAULT_CONFIG
  computeOutstanding
  META_ACTIONS
  monthKey
  parseMonthKey
  deletedEventIds
  applyEdits
  resolveEditsAndDeletes
  resolveConfig
  computeMonth
  computeAllPeriods
}
