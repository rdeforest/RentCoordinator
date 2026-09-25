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

# created_at has two shapes: events take the column default, SQLite's
# CURRENT_TIMESTAMP ('YYYY-MM-DD HH:MM:SS', UTC, no zone); work_logs are
# written with an ISO string. Parse each by its shape.
parseCreatedAt = (value) ->
  return NaN unless value?
  if value.includes 'T' then new Date(value).getTime() else new Date(value.replace(' ', 'T') + 'Z').getTime()

# When real data was last written, from the rows themselves. The file's mtime
# also moves on logins and on this check's own writes, so it would report a
# stale backup after every login. Compared as epoch ms across tables, not as
# strings — a MAX() per table is still per-table, and the two created_at
# shapes above don't sort against each other correctly as text. 0 when there
# is no data yet at all; NaN (via Math.max) when a value exists but couldn't
# be parsed, which checkBackupAge treats as its own error rather than silently
# skipping the check (bug 62, F2).
lastDataWriteMs = ->
  values = FINGERPRINT_TABLES
    .map (table) -> db.prepare("SELECT MAX(created_at) AS t FROM #{table}").get().t
    .filter (t) -> t?

  return 0 if values.length is 0

  epochs = values.map parseCreatedAt
  Math.max epochs...


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
  lastDataWriteMs
  recordRun
  latestRun
  listRuns
  listAcknowledgments
  acknowledgedKeys
  getAck
  ack
  unack
}
