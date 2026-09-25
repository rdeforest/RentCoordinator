# Bug 62 — lib/models/consistency.coffee: the fingerprint that decides
# whether a scheduled run is worth doing, and the run/acknowledgment storage.

fs   = require 'node:fs'
os   = require 'node:os'
path = require 'node:path'

DB_PATH = path.join fs.mkdtempSync(path.join os.tmpdir(), 'rc-consistency-model-'), 'test.db'
process.env.DB_PATH  = DB_PATH
process.env.NODE_ENV = 'test'

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
schema                          = require '../../lib/db/schema.coffee'
eventsModel                     = require '../../lib/models/events.coffee'
workLogModel                    = require '../../lib/models/work_log.coffee'
consistencyModel                = require '../../lib/models/consistency.coffee'

before -> await schema.initialize()
after  -> fs.rmSync path.dirname(DB_PATH), recursive: true, force: true


describe 'currentFingerprint', ->
  it 'changes when a new event is recorded', ->
    before_ = consistencyModel.currentFingerprint()
    eventsModel.recordEvent
      occurred_at:   new Date().toISOString()
      effective_for: '2026-05'
      actor:         'tenant'
      actor_user:    'lynz57@hotmail.com'
      action:        'payment-made'
      payload:       { amount: 100, method: 'manual' }
    after_ = consistencyModel.currentFingerprint()
    assert.notEqual before_, after_

  it 'is stable when nothing has changed', ->
    a = consistencyModel.currentFingerprint()
    b = consistencyModel.currentFingerprint()
    assert.equal a, b


describe 'recordRun / latestRun', ->
  it 'round-trips findings as stored JSON', ->
    fingerprint = consistencyModel.currentFingerprint()
    findings    = [ { key: 'k1', kind: 'test', severity: 'warning', message: 'm' } ]
    consistencyModel.recordRun fingerprint, findings
    run = consistencyModel.latestRun()
    assert.equal run.fingerprint, fingerprint
    assert.deepEqual run.findings, findings

  it 'keeps exactly the most recent 30 runs after 35 have been recorded', ->
    fingerprint = consistencyModel.currentFingerprint()
    consistencyModel.recordRun fingerprint, [] for [1..35]
    assert.equal consistencyModel.listRuns(100).length, 30


describe 'acknowledgments are never deleted by a run', ->
  it 'keeps the note through a long Stripe outage and matches the finding when it returns', ->
    fingerprint = consistencyModel.currentFingerprint()
    legacy      = { key: 'stripe-unlinked:pi_legacy', kind: 'stripe-unlinked', severity: 'warning', message: 'm' }
    outage      = { key: 'stripe-error:connect ECONNREFUSED', kind: 'stripe-error', severity: 'error', message: 'm' }

    consistencyModel.recordRun fingerprint, [legacy]
    consistencyModel.ack legacy.key, 'paid 2026-06-12 before bug 09; recorded by hand', 'robert@defore.st'

    consistencyModel.recordRun fingerprint, [outage] for [1..31]
    consistencyModel.recordRun fingerprint, [legacy]

    assert.equal consistencyModel.getAck(legacy.key)?.note, 'paid 2026-06-12 before bug 09; recorded by hand',
      'a note Robert wrote must outlive any number of runs that could not see its finding'


describe 'acknowledgments', ->
  it 'ack requires a note (enforced by the route; the model stores whatever it is given) and round-trips', ->
    ack = consistencyModel.ack 'finding-key-1', 'looked into it, expected', 'robert@defore.st'
    assert.equal ack.note, 'looked into it, expected'
    assert.ok consistencyModel.acknowledgedKeys().has 'finding-key-1'

  it 're-acking the same key updates the note rather than duplicating', ->
    consistencyModel.ack 'finding-key-1', 'first note', 'robert@defore.st'
    consistencyModel.ack 'finding-key-1', 'second note', 'robert@defore.st'
    assert.equal consistencyModel.getAck('finding-key-1').note, 'second note'

  it 'unack removes it', ->
    consistencyModel.ack 'finding-key-2', 'note', 'robert@defore.st'
    consistencyModel.unack 'finding-key-2'
    assert.equal consistencyModel.getAck('finding-key-2'), undefined
    assert.ok not consistencyModel.acknowledgedKeys().has 'finding-key-2'


describe 'lastDataWriteMs (bug 62, F2)', ->
  it 'is finite and recent through the real work_log insert path (created_at is an ISO string there, not SQLite CURRENT_TIMESTAMP)', ->
    before_ = Date.now()
    workLogModel.createWorkLog
      worker:      'lyndzie'
      start_time:  new Date().toISOString()
      end_time:    new Date().toISOString()
      duration:    60
      description: 'F2 coverage'

    result = consistencyModel.lastDataWriteMs()
    assert.ok Number.isFinite(result), "expected a finite epoch ms, got #{result}"
    assert.ok result >= before_ - 1000 and result <= Date.now() + 1000,
      'expected the timestamp to be roughly now, not NaN from a mis-parsed ISO string'


describe 'lastDataWriteMs', ->
  it 'moves on a ledger write and not on a login', ->
    { db } = schema
    db.prepare("UPDATE events SET created_at = '2026-01-01 00:00:00'").run()
    db.prepare("UPDATE work_logs SET created_at = '2026-01-01 00:00:00'").run()
    settled = consistencyModel.lastDataWriteMs()

    db.prepare("INSERT INTO sessions (sid, sess, expires) VALUES ('s', '{}', ?)").run Date.now() + 60_000
    assert.equal consistencyModel.lastDataWriteMs(), settled,
      'a login is not data; counting it reported a stale backup after every login'

    eventsModel.recordEvent
      occurred_at:   '2026-01-15T00:00:00Z'
      effective_for: '2026-01'
      actor:         'tenant'
      actor_user:    'lynz57@hotmail.com'
      action:        'payment-made'
      payload:       { amount: 10, method: 'manual' }
    assert.ok consistencyModel.lastDataWriteMs() > settled
    assert.ok Math.abs(consistencyModel.lastDataWriteMs() - Date.now()) < 5 * 60_000,
      'created_at is UTC; reading it as local time would be off by hours'
