# Bugs 07 / 30 / 32 — the timer's duration accounting.
#
# These run against a throwaway database rather than a live server so the
# elapsed times can be dictated instead of waited for: an eight-hour timeout
# is not something an integration test can sit through.

fs   = require 'node:fs'
os   = require 'node:os'
path = require 'node:path'

DB_PATH = path.join fs.mkdtempSync(path.join os.tmpdir(), 'rc-timer-'), 'timer-test.db'
process.env.DB_PATH  = DB_PATH
process.env.NODE_ENV = 'test'

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
{ v1 }                          = require 'uuid'
schema                          = require '../../lib/db/schema.coffee'
config                          = require '../../lib/config.coffee'
workSessionModel                = require '../../lib/models/work_session.coffee'

{ db } = schema

MINUTE = 60 * 1000
HOUR   = 60 * MINUTE

before -> await schema.initialize()
after  -> fs.rmSync path.dirname(DB_PATH), recursive: true, force: true


# Build a session whose event timeline is stated outright, so the duration
# under test is a known quantity rather than however long the test ran.
seedSession = (worker, events) ->
  id  = v1()
  now = new Date().toISOString()

  db.prepare("""
    INSERT INTO work_sessions (id, worker, description, status, total_duration, billable, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  """).run id, worker, 'seeded session', 'active', 0, 1, now, now

  for [type, at] in events
    db.prepare("""
      INSERT INTO work_events (id, session_id, event_type, timestamp, created_at)
      VALUES (?, ?, ?, ?, ?)
    """).run v1(), id, type, at.toISOString(), now

  last = events[events.length - 1][0]
  status = switch last
    when 'start', 'resume' then 'active'
    when 'pause'           then 'paused'
    when 'stop'            then 'completed'
    when 'cancel'          then 'cancelled'

  db.prepare("UPDATE work_sessions SET status = ? WHERE id = ?").run status, id

  db.prepare("SELECT * FROM work_sessions WHERE id = ?").get id


describe 'Timer duration accounting (bugs 07/30)', ->
  it 'a stopped session converts to a work log with its real duration (bug 07)', ->
    start   = new Date Date.now() - 90 * MINUTE
    session = seedSession 'lyndzie', [['start', start], ['stop', new Date start.getTime() + 90 * MINUTE]]

    log = workSessionModel.sessionToWorkLog session

    assert.equal log.duration, 90,
      'the log must carry the elapsed time, not work_sessions.total_duration (always 0)'
    assert.equal session.total_duration, 0,
      'the stale column is still 0 — which is exactly why it must not be read'


  it 'sums only the running segments, not the paused gap', ->
    start   = new Date Date.now() - 4 * HOUR
    session = seedSession 'lyndzie', [
      ['start',  start]
      ['pause',  new Date start.getTime() + 30 * MINUTE]
      ['resume', new Date start.getTime() + 2 * HOUR]
      ['stop',   new Date start.getTime() + 2 * HOUR + 15 * MINUTE]
    ]

    assert.equal workSessionModel.sessionToWorkLog(session).duration, 45,
      '30 minutes plus 15 minutes; the 90-minute pause does not count'


  it 'caps an abandoned running session at SESSION_TIMEOUT (bug 30)', ->
    start   = new Date Date.now() - 30 * HOUR
    session = seedSession 'robert', [['start', start]]

    seconds = workSessionModel.calculateSessionDuration session.id

    assert.equal seconds, config.SESSION_TIMEOUT / 1000,
      "a timer left running for 30 hours should report the 8-hour cap, got #{seconds / 3600}h"


  it 'leaves a session inside the cap alone', ->
    start   = new Date Date.now() - 2 * HOUR
    session = seedSession 'robert', [['start', start]]

    seconds = workSessionModel.calculateSessionDuration session.id

    assert.ok Math.abs(seconds - 2 * 3600) <= 2, "expected about 2h, got #{seconds}s"
    assert.ok seconds < config.SESSION_TIMEOUT / 1000, 'and well under the cap'


  it 'reports where the clock is still running, and where it is not', ->
    start = new Date Date.now() - HOUR

    running = seedSession 'robert', [['start', start]]
    assert.ok workSessionModel.openSegmentStart(running.id),
      'an active session has an open segment'

    paused = seedSession 'robert', [['start', start], ['pause', new Date()]]
    assert.equal workSessionModel.openSegmentStart(paused.id), null,
      'a paused session does not'


describe 'Resume validation (bug 32)', ->
  it 'refuses to resume another worker\'s session', ->
    session = seedSession 'lyndzie', [['start', new Date()], ['pause', new Date()]]

    await assert.rejects (-> workSessionModel.resumeSession session.id, 'robert'),
      /does not belong/,
      'robert must not be able to claim lyndzie\'s paused session'

  it 'refuses to resume a session that is not paused', ->
    session = seedSession 'robert', [['start', new Date()], ['stop', new Date()]]

    await assert.rejects (-> workSessionModel.resumeSession session.id, 'robert'),
      /Cannot resume a completed session/

  it 'refuses an unknown session id', ->
    await assert.rejects (-> workSessionModel.resumeSession 'no-such-session', 'robert'),
      /Session not found/

  it 'still resumes the worker\'s own paused session', ->
    session = seedSession 'robert', [['start', new Date()], ['pause', new Date()]]

    resumed = await workSessionModel.resumeSession session.id, 'robert'
    assert.equal resumed.status, 'active'
