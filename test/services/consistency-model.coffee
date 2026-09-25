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

  it 'keeps only the most recent 30 runs', ->
    fingerprint = consistencyModel.currentFingerprint()
    consistencyModel.recordRun fingerprint, [] for [1..35]
    assert.ok consistencyModel.listRuns(100).length <= 30


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
