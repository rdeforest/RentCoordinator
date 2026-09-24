# Bug 31/55 — stopping a timer session must credit rent through the event
# fold (period.coffee's computeMonth reading events), not the legacy
# rent_periods table.
#
# lib/services/timer.coffee used to call
# rentService.createOrUpdateRentPeriod after every stop — writing
# rent_periods, a table nothing authoritative reads any more (see
# migrations/2026-09-23_130000_disable_recurring_scheduler.coffee) — after
# the work log (and its work-reported event) had already committed. A throw
# in that legacy write would 500 a stop that had already succeeded, and the
# call was redundant: createWorkLog itself emits the work-reported event
# (bug 06). This test asserts the fold sees timer-sourced work with the
# legacy call gone.
#
# Seeded timestamps, not real sleeps — an integration test cannot sit
# through minute-scale timing to get a non-zero rounded duration.

fs   = require 'node:fs'
os   = require 'node:os'
path = require 'node:path'

DB_PATH = path.join fs.mkdtempSync(path.join os.tmpdir(), 'rc-timer-credit-'), 'timer-test.db'
process.env.DB_PATH  = DB_PATH
process.env.NODE_ENV = 'test'

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
{ v1 }                          = require 'uuid'
schema                          = require '../../lib/db/schema.coffee'
workSessionModel                = require '../../lib/models/work_session.coffee'
eventsModel                     = require '../../lib/models/events.coffee'
period                          = require '../../lib/services/period.coffee'
timerService                    = require '../../lib/services/timer.coffee'

{ db } = schema

MINUTE = 60 * 1000

before -> await schema.initialize()
after  -> fs.rmSync path.dirname(DB_PATH), recursive: true, force: true


# Same shape as the running server: a work_sessions row, its work_events
# timeline, and the current_sessions pointer stopTimer reads through.
seedActiveSession = (worker, start) ->
  id  = v1()
  now = new Date().toISOString()

  db.prepare("""
    INSERT INTO work_sessions (id, worker, description, status, total_duration, billable, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  """).run id, worker, '', 'active', 0, 1, now, now

  db.prepare("""
    INSERT INTO work_events (id, session_id, event_type, timestamp, created_at)
    VALUES (?, ?, 'start', ?, ?)
  """).run v1(), id, start.toISOString(), now

  db.prepare("""
    INSERT OR REPLACE INTO current_sessions (worker, session_id) VALUES (?, ?)
  """).run worker, id

  id


describe 'stopTimer credits rent through the event fold, not rent_periods (bug 31/55)', ->
  it "a 90-minute lyndzie session shows up in computeMonth's hours_worked", ->
    start = new Date Date.now() - 90 * MINUTE
    seedActiveSession 'lyndzie', start

    result = await timerService.stopTimer 'lyndzie', true
    assert.ok result.work_log, 'a work log was created'
    assert.equal result.work_log.duration, 90

    year  = start.getFullYear()
    month = start.getMonth() + 1
    events = eventsModel.listAllEvents()
    reported = events.filter (e) -> e.action is 'work-reported'
    assert.equal reported.length, 1, 'createWorkLog emitted the work-reported event on its own'

    periods = period.computeAllPeriods events, new Date()
    key = period.monthKey year, month
    assert.equal periods[key].hours_worked, 1.5, '90 minutes credited through the fold'


  it "stopping a session does not fail even if the legacy rent_periods table is gone", ->
    # The old call wrote rent_periods, a table nothing authoritative reads
    # (migrations/2026-09-23_130000_disable_recurring_scheduler.coffee), after
    # the work log had already committed — so a throw in that dead write used
    # to turn a stop that had already succeeded into a 500. Dropping the table
    # stands in for "the legacy write path is broken"; a stop must still
    # succeed because nothing in the write path depends on it any more.
    db.exec 'DROP TABLE IF EXISTS rent_periods'

    start = new Date Date.now() - 45 * MINUTE
    seedActiveSession 'lyndzie', start

    result = await timerService.stopTimer 'lyndzie', true
    assert.equal result.event, 'completed'
    assert.ok result.work_log, 'the work log still commits with rent_periods gone'
