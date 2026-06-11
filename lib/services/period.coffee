# Pure functions for computing rent periods from an event log.
# No DB access, no persistence. Caller passes events in, gets period views out.
# See docs/event-model.md for the conceptual model.


DEFAULT_CONFIG =
  base_rent:              1600
  hourly_credit:          50
  max_monthly_hours:      8
  agreed_monthly_payment: 950
  rent_due_day:           15
  temporary_rent_amount:  null
  apply_override:         false


monthKey = (year, month) ->
  "#{year}-#{String(month).padStart 2, '0'}"


parseMonthKey = (key) ->
  [y, m] = key.split('-').map (n) -> parseInt n, 10
  { year: y, month: m }


# Given the raw event log, return events with edits applied and deletes
# removed. Pure — does not touch the input array. `edited` events fold their
# new_payload onto the original (last write wins). `deleted` events drop
# their target from the result.
resolveEditsAndDeletes = (events) ->
  byId = new Map()
  for e in events when e.action not in ['edited', 'deleted']
    byId.set e.id, e

  for e in events when e.action is 'edited' and byId.has e.target_event_id
    orig    = byId.get e.target_event_id
    payload = Object.assign {}, orig.payload, e.payload.new_payload
    byId.set e.target_event_id, Object.assign {}, orig, { payload }

  for e in events when e.action is 'deleted'
    byId.delete e.target_event_id

  Array.from byId.values()


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
  for e in monthEvents
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

  amount_due_calculated = config.base_rent - total_discount
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

  display_amount_due =
    if      amount_due_override then amount_due
    else if is_future           then amount_due
    else if is_current          then (if now.getDate() < config.rent_due_day then 0 else agreed_payment)
    else                             agreed_payment

  payment_status =
    if      is_current and now.getDate() < config.rent_due_day then 'NOT DUE'
    else if amount_paid >= display_amount_due                  then 'PAID'
    else if amount_paid > 0                                    then 'PARTIAL'
    else                                                            'UNPAID'

  {
    year, month
    hours_worked
    hours_from_previous:      carryOver
    hours_to_next:            total_available - hours_used
    hours_applied:            base_hours_applied
    discount_applied:         base_discount
    retroactive_credit
    total_discount
    base_rent:                config.base_rent
    agreed_payment
    effective_agreed_payment: agreed_payment
    amount_due
    amount_due_calculated
    amount_due_override
    amount_paid
    amount_paid_override
    display_amount_due
    payment_status
    cumulative_shortfall
  }


# Fold every event into a map of monthKey → period view. Walks every month
# from the first month with activity through the current month, so months
# with only carry-over (no work-reported, no payment-made) still appear.
# Future months are not computed here — caller can computeMonth for those.
computeAllPeriods = (events, now = new Date()) ->
  resolved = resolveEditsAndDeletes events

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
    period = computeMonth year, month, resolved, carryOver, shortfall, now
    result[monthKey year, month] = period
    carryOver = period.hours_to_next
    shortfall = period.cumulative_shortfall

    break if year is last.year and month is last.month
    month += 1
    if month > 12
      month  = 1
      year  += 1

  result


module.exports = {
  DEFAULT_CONFIG
  monthKey
  parseMonthKey
  resolveEditsAndDeletes
  resolveConfig
  computeMonth
  computeAllPeriods
}
