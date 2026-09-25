# Bug 62 — the scheduler's decide-to-run logic, pure and timer-free.
# Requiring the module still pulls in db/schema.coffee transitively (it opens
# a connection at require time), so point DB_PATH at a throwaway file rather
# than let it touch the real one in the working directory.

fs   = require 'node:fs'
os   = require 'node:os'
path = require 'node:path'

process.env.DB_PATH  = path.join fs.mkdtempSync(path.join os.tmpdir(), 'rc-consistency-sched-'), 'test.db'
process.env.NODE_ENV = 'test'

{ test } = require 'node:test'
assert   = require 'node:assert/strict'

{ shouldRunScheduled, msUntilNext3amUTC } = require '../../lib/services/consistency-scheduler.coffee'


test 'shouldRunScheduled runs when there is no previous run', ->
  assert.equal shouldRunScheduled('fp-1', null), true


test 'shouldRunScheduled skips when the fingerprint has not changed', ->
  assert.equal shouldRunScheduled('fp-1', { fingerprint: 'fp-1' }), false


test 'shouldRunScheduled runs when the fingerprint has changed', ->
  assert.equal shouldRunScheduled('fp-2', { fingerprint: 'fp-1' }), true


test 'msUntilNext3amUTC is 0 < ms <= 24h, and lands on 03:00 UTC', ->
  now = new Date '2026-05-15T10:00:00Z'
  ms  = msUntilNext3amUTC now
  next = new Date now.getTime() + ms
  assert.equal next.getUTCHours(), 3
  assert.equal next.getUTCMinutes(), 0
  assert.ok ms > 0 and ms <= 24 * 60 * 60 * 1000


test 'msUntilNext3amUTC rolls to tomorrow when already past 03:00 today', ->
  now  = new Date '2026-05-15T03:00:01Z'
  ms   = msUntilNext3amUTC now
  next = new Date now.getTime() + ms
  assert.equal next.getUTCDate(), 16
  assert.equal next.getUTCHours(), 3


test 'msUntilNext3amUTC rolls to tomorrow exactly at 03:00 (strictly future)', ->
  now  = new Date '2026-05-15T03:00:00Z'
  ms   = msUntilNext3amUTC now
  next = new Date now.getTime() + ms
  assert.equal next.getUTCDate(), 16


test 'msUntilNext3amUTC targets today when called before 03:00', ->
  now  = new Date '2026-05-15T01:00:00Z'
  ms   = msUntilNext3amUTC now
  next = new Date now.getTime() + ms
  assert.equal next.getUTCDate(), 15
  assert.equal next.getUTCHours(), 3
