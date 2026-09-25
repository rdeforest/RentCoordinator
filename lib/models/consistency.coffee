# Data access for consistency_runs / finding_acknowledgments. See
# lib/services/consistency.coffee for the checks and
# docs/bugs/62-no-consistency-checking.md for the design.

{ db } = require '../db/schema.coffee'

MAX_RUNS = 30

# Tables judged to hold real data for deciding whether the daily scheduled
# check needs to rerun — see docs/bugs/62-no-consistency-checking.md. events
# is the ledger every check reads; work_logs is named explicitly in the spec
# and still receives writes independent of events (lib/models/work_log.coffee
# emits both). Sessions, auth codes, pii tokens and the consistency tables
# themselves are workflow/audit machinery, not facts to reconcile.
FINGERPRINT_TABLES = ['events', 'work_logs']

tableFingerprint = (table) ->
  row = db.prepare("SELECT COUNT(*) AS n, MAX(rowid) AS maxRowid FROM #{table}").get()
  "#{table}:#{row.n}:#{row.maxRowid ? 0}"

# A digest of "has the real data changed", not a hash of its contents — cheap
# to compute, and any insert/delete moves the count or the max rowid.
currentFingerprint = ->
  FINGERPRINT_TABLES.map(tableFingerprint).join '|'


recordRun = (fingerprint, findings) ->
  db.prepare("""
    INSERT INTO consistency_runs (ran_at, fingerprint, findings) VALUES (?, ?, ?)
  """).run new Date().toISOString(), fingerprint, JSON.stringify(findings)

  db.prepare("""
    DELETE FROM consistency_runs
    WHERE id NOT IN (SELECT id FROM consistency_runs ORDER BY id DESC LIMIT ?)
  """).run MAX_RUNS

  latestRun()


hydrateRun = (row) ->
  return null unless row
  Object.assign {}, row, findings: JSON.parse row.findings


latestRun = ->
  hydrateRun db.prepare('SELECT * FROM consistency_runs ORDER BY id DESC LIMIT 1').get()


listRuns = (limit = MAX_RUNS) ->
  rows = db.prepare('SELECT * FROM consistency_runs ORDER BY id DESC LIMIT ?').all limit
  hydrateRun row for row in rows


listAcknowledgments = ->
  db.prepare('SELECT * FROM finding_acknowledgments').all()


acknowledgedKeys = ->
  new Set (row.finding_key for row in listAcknowledgments())


getAck = (key) ->
  db.prepare('SELECT * FROM finding_acknowledgments WHERE finding_key = ?').get key


ack = (key, note, acknowledgedBy) ->
  db.prepare("""
    INSERT INTO finding_acknowledgments (finding_key, note, acknowledged_by, acknowledged_at)
    VALUES (?, ?, ?, ?)
    ON CONFLICT(finding_key) DO UPDATE SET
      note            = excluded.note,
      acknowledged_by = excluded.acknowledged_by,
      acknowledged_at = excluded.acknowledged_at
  """).run key, note, acknowledgedBy, new Date().toISOString()

  getAck key


unack = (key) ->
  db.prepare('DELETE FROM finding_acknowledgments WHERE finding_key = ?').run key


module.exports = {
  FINGERPRINT_TABLES
  currentFingerprint
  recordRun
  latestRun
  listRuns
  listAcknowledgments
  acknowledgedKeys
  getAck
  ack
  unack
}
