# Bug 62 — run the consistency checks at startup and once a day, without
# delaying either the server listening or (on the daily run) rerunning
# against data that hasn't changed. Pattern follows
# lib/services/session-store.coffee::startSweep and
# lib/services/backup.coffee::startIdleBackup: an unref'd timer, errors
# logged and swallowed, never fatal.

logger           = require '../logger.coffee'
consistency      = require './consistency.coffee'
consistencyModel = require '../models/consistency.coffee'

DAY_MS = 24 * 60 * 60 * 1000

# Pure: given the current fingerprint and the last stored run (or null), is a
# scheduled run worth doing? When the data changed, or when the last run left
# anything open: an open finding may have been fixed by something the
# fingerprint can't see (a backup landing, Stripe recovering, a hand repair).
# A quiet day with nothing open still skips. Exported so the decision is
# testable without a timer or a database.
shouldRunScheduled = (fingerprint, lastRun, ackedKeys = new Set()) ->
  return true unless lastRun?
  return true if lastRun.fingerprint isnt fingerprint

  (lastRun.findings ? []).some (f) -> not ackedKeys.has f.key


# Milliseconds until the next 03:00 UTC, strictly in the future. Exported for
# testing the boundary (exactly 03:00, just before, just after).
msUntilNext3amUTC = (now = new Date()) ->
  next = new Date Date.UTC now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 3, 0, 0, 0
  next = new Date next.getTime() + DAY_MS if next <= now
  next.getTime() - now.getTime()


# Pure: which findings are worth a log warning — present now, absent from the
# previous run's keys, and not already acknowledged. Exported so the decision
# is testable without stubbing consistency.runChecks or the logger (bug 62,
# F5).
newlyUnacknowledgedFindings = (findings, previousKeys, ackedKeys) ->
  (f for f in findings when not previousKeys.has(f.key) and not ackedKeys.has(f.key))


# Run the checks, store the result, and warn on anything newly surfaced
# (present now, absent from the previous run, not already acknowledged) so a
# fresh problem is visible in the log the moment it's found, not only on the
# issues page.
runAndStore = ->
  previous     = consistencyModel.latestRun()
  previousKeys = new Set (if previous then (f.key for f in previous.findings) else [])

  findings    = await consistency.runChecks()
  fingerprint = consistencyModel.currentFingerprint()
  consistencyModel.recordRun fingerprint, findings

  acked = consistencyModel.acknowledgedKeys()
  newUnacknowledged = newlyUnacknowledgedFindings findings, previousKeys, acked

  for f in newUnacknowledged
    logger.warn 'consistency.finding', f.message,
      { key: f.key, kind: f.kind, severity: f.severity, month: f.month }

  logger.info 'consistency.run',
    "consistency check: #{findings.length} finding(s), #{newUnacknowledged.length} new"
  , { findings: findings.length, new: newUnacknowledged.length }

  findings


runIfNeeded = ->
  fingerprint = consistencyModel.currentFingerprint()
  lastRun     = consistencyModel.latestRun()
  return unless shouldRunScheduled fingerprint, lastRun, consistencyModel.acknowledgedKeys()

  await runAndStore()


# Re-arms against msUntilNext3amUTC(), not a flat DAY_MS from when the run
# finished — a run that takes any real time (or a slow Stripe page) would
# otherwise push tomorrow's fire time later every day (bug 62, F8).
scheduleDailyCheck = ->
  fire = ->
    try
      await runIfNeeded()
    catch err
      logger.error 'consistency.scheduledRun', err

    timer = setTimeout fire, msUntilNext3amUTC()
    timer.unref()

  timer = setTimeout fire, msUntilNext3amUTC()
  timer.unref()


# Fire the startup run (unconditional — see docs/bugs/62) and arm the daily
# schedule. main.coffee calls this after markAppReady. The run is synchronous
# until its first await, so it must not be able to hang: the fold ignores
# malformed month keys rather than walking towards them.
start = ->
  runAndStore().catch (err) -> logger.error 'consistency.startupRun', err
  scheduleDailyCheck()


module.exports = {
  start
  runAndStore
  runIfNeeded
  scheduleDailyCheck
  shouldRunScheduled
  msUntilNext3amUTC
  newlyUnacknowledgedFindings
}
