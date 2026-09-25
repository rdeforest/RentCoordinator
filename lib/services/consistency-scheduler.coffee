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
# scheduled run worth doing? Exported so the decision is testable without a
# timer or a database.
shouldRunScheduled = (fingerprint, lastRun) ->
  not lastRun? or lastRun.fingerprint isnt fingerprint


# Milliseconds until the next 03:00 UTC, strictly in the future. Exported for
# testing the boundary (exactly 03:00, just before, just after).
msUntilNext3amUTC = (now = new Date()) ->
  next = new Date Date.UTC now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 3, 0, 0, 0
  next = new Date next.getTime() + DAY_MS if next <= now
  next.getTime() - now.getTime()


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
  newUnacknowledged = (f for f in findings when not previousKeys.has(f.key) and not acked.has(f.key))

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
  return unless shouldRunScheduled fingerprint, lastRun

  await runAndStore()


scheduleDailyCheck = ->
  fire = ->
    try
      await runIfNeeded()
    catch err
      logger.error 'consistency.scheduledRun', err

    timer = setTimeout fire, DAY_MS
    timer.unref()

  timer = setTimeout fire, msUntilNext3amUTC()
  timer.unref()


# Fire the startup run (unconditional — see docs/bugs/62) without delaying
# the caller, and arm the daily schedule.
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
}
