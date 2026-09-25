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

{ shouldRunScheduled, msUntilNext3amUTC, newlyUnacknowledgedFindings } = require '../../lib/services/consistency-scheduler.coffee'


test 'shouldRunScheduled runs when there is no previous run', ->
  assert.equal shouldRunScheduled('fp-1', null), true


test 'shouldRunScheduled skips when the fingerprint has not changed and nothing external is stale', ->
  lastRun = { fingerprint: 'fp-1', findings: [ { key: 'k', kind: 'ledger-corrupt-month' } ] }
  assert.equal shouldRunScheduled('fp-1', lastRun), false


test 'shouldRunScheduled runs when the fingerprint has changed', ->
  assert.equal shouldRunScheduled('fp-2', { fingerprint: 'fp-1', findings: [] }), true


# --- bug 62, F3: a stale-fingerprint run still reruns when the last run has
# a finding about state outside our own data (backup age, Stripe) --------

test 'shouldRunScheduled reruns on an unchanged fingerprint when the last run has a backup-* finding', ->
  lastRun = { fingerprint: 'fp-1', findings: [ { key: 'k', kind: 'backup-stale' } ] }
  assert.equal shouldRunScheduled('fp-1', lastRun), true

test 'shouldRunScheduled reruns on an unchanged fingerprint when the last run has a stripe-* finding', ->
  lastRun = { fingerprint: 'fp-1', findings: [ { key: 'k', kind: 'stripe-unlinked' } ] }
  assert.equal shouldRunScheduled('fp-1', lastRun), true

test 'shouldRunScheduled reruns on an unchanged fingerprint when the last run has any *-error finding', ->
  lastRun = { fingerprint: 'fp-1', findings: [ { key: 'k', kind: 'db-integrity-error' } ] }
  assert.equal shouldRunScheduled('fp-1', lastRun), true

test 'shouldRunScheduled still skips on an unchanged fingerprint when findings are ordinary ledger findings', ->
  lastRun = { fingerprint: 'fp-1', findings: [ { key: 'k', kind: 'manual-payment-after-pin' } ] }
  assert.equal shouldRunScheduled('fp-1', lastRun), false


# --- bug 62, F5: runAndStore warns only for new, unacknowledged findings —
# exposed as a pure function so the decision is testable without stubbing
# consistency.runChecks or the logger. -------------------------------------

test 'newlyUnacknowledgedFindings excludes a finding present in the previous run', ->
  findings = [ { key: 'a' }, { key: 'b' } ]
  result = newlyUnacknowledgedFindings findings, new Set(['a']), new Set()
  assert.deepEqual (f.key for f in result), ['b']

test 'newlyUnacknowledgedFindings excludes an acknowledged finding even if it is new', ->
  findings = [ { key: 'a' }, { key: 'b' } ]
  result = newlyUnacknowledgedFindings findings, new Set(), new Set(['b'])
  assert.deepEqual (f.key for f in result), ['a']

test 'newlyUnacknowledgedFindings warns on a finding that is both new and unacknowledged', ->
  findings = [ { key: 'a' }, { key: 'b' }, { key: 'c' } ]
  result = newlyUnacknowledgedFindings findings, new Set(['a']), new Set(['b'])
  assert.deepEqual (f.key for f in result), ['c']


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


test 'shouldRunScheduled ignores external findings Robert has acknowledged', ->
  lastRun = { fingerprint: 'fp-1', findings: [{ key: 'stripe-unlinked:pi_1', kind: 'stripe-unlinked' }] }
  assert.equal shouldRunScheduled('fp-1', lastRun), true, 'open: rerun to see whether it cleared'
  assert.equal shouldRunScheduled('fp-1', lastRun, new Set ['stripe-unlinked:pi_1']), false,
    'acknowledged: a settled finding must not call Stripe every day'
