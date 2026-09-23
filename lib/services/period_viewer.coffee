# Thin orchestrator: load events from the DB, fold them with the pure
# compute function, hand callers the period view they want. No persistence.
# This is the bridge between events (the model) and the routes (the API).

eventsModel  = require '../models/events.coffee'
period       = require './period.coffee'
money        = require '../money.coffee'


getAllPeriods = (opts = {}, now = new Date()) ->
  period.computeAllPeriods eventsModel.listAllEvents(), now, opts


getPeriod = (year, month, now = new Date()) ->
  periods = getAllPeriods { includeSuppressed: true }, now
  periods[period.monthKey year, month]


# Resolve config as of a point in time (defaults to now). Used by routes
# that need the current config snapshot (e.g. /rent/configuration GET).
getConfig = (asOf = new Date()) ->
  period.resolveConfig eventsModel.listAllEvents(), asOf


# What is actually owed, oldest month first. Months still NOT DUE are
# excluded — they can be paid early, but they are not part of "what do I
# owe". A month settled to the cent is settled; comparing raw floats left
# fully-paid months outstanding by fractions of a cent (bug 35).
#
# One definition, because /payment/create-intent bills from it and
# /rent/outstanding displays it. They were separate copies of the same rule,
# so the bug-35 fix had to be made twice and the next change would have been
# applied to one of them.
computeOutstanding = (now = new Date()) ->
  rows = Object.values(getAllPeriods {}, now)
    .filter (p) -> p.payment_status isnt 'NOT DUE'
    .map (p) ->
      owed = p.display_amount_due
      paid = p.amount_paid or 0
      { year: p.year, month: p.month, owed, paid, outstanding: Math.max 0, money.minus owed, paid }
    .filter (r) -> money.cents(r.outstanding) > 0
    .sort   (a, b) -> (a.year - b.year) or (a.month - b.month)

  total:  money.dollars rows.reduce ((s, r) -> s + r.outstanding), 0
  months: rows


module.exports = {
  computeOutstanding
  getAllPeriods
  getPeriod
  getConfig
}
