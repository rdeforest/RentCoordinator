# Thin orchestrator: load events from the DB, fold them with the pure
# compute function, hand callers the period view they want. No persistence.
# This is the bridge between events (the model) and the routes (the API).

eventsModel  = require '../models/events.coffee'
period       = require './period.coffee'


getAllPeriods = (opts = {}, now = new Date()) ->
  period.computeAllPeriods eventsModel.listAllEvents(), now, opts


getPeriod = (year, month, now = new Date()) ->
  periods = getAllPeriods { includeSuppressed: true }, now
  periods[period.monthKey year, month]


# Resolve config as of a point in time (defaults to now). Used by routes
# that need the current config snapshot (e.g. /rent/configuration GET).
getConfig = (asOf = new Date()) ->
  period.resolveConfig eventsModel.listAllEvents(), asOf


# One definition of what is owed, in period.coffee next to the fold that
# produces the periods. This supplies them.
computeOutstanding = (now = new Date()) ->
  period.computeOutstanding getAllPeriods {}, now


module.exports = {
  computeOutstanding
  getAllPeriods
  getPeriod
  getConfig
}
