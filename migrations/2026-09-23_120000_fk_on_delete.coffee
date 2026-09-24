# migrations/2026-09-23_120000_fk_on_delete.coffee
#
# Bug 48 — the same footgun as bug 02, on a different set of tables. With
# PRAGMA foreign_keys = ON, a foreign key with no ON DELETE action makes
# deleting the parent an error. The 2026-05-19 migration fixed this for the
# rent_periods children; these five were never touched, so the day a delete
# path is added for a project or a work session it 500s.
#
# The semantics are not uniform, and that is the point:
#
#   tasks.project_id            CASCADE   a task has no meaning without its
#   work_events.session_id      CASCADE   project / session — it is a part of
#   current_sessions.session_id CASCADE   it, not a reference to it.
#
#   work_logs.project_id        SET NULL  the log is a record of work that
#   work_logs.task_id           SET NULL  happened. Deleting the project it
#                                         was filed under must not delete the
#                                         hours, and must not credit rent
#                                         differently either.
#
# SQLite cannot alter a constraint in place, so each table is rebuilt. The
# whole thing runs in one transaction; a failure leaves the database as it was.
#
# Idempotent: a table whose definition already carries ON DELETE is skipped.

{ DatabaseSync } = require 'node:sqlite'

DB_PATH = process.env.DB_PATH or './tenant-coordinator.db'
db      = new DatabaseSync DB_PATH

console.log "Running migration: fk_on_delete against #{DB_PATH}"


definitionOf = (table) ->
  db.prepare("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?").get(table)?.sql


needsRebuild = (table) ->
  sql = definitionOf table
  return false unless sql
  not sql.toUpperCase().includes 'ON DELETE'


# Rebuild `table` with `createSql`, copying `columns` across.
rebuild = (table, columns, createSql, indexes = []) ->
  unless needsRebuild table
    console.log "  #{table} already has ON DELETE actions — skipping"
    return

  console.log "  Rebuilding #{table}..."
  list = columns.join ', '

  db.exec createSql.replace "CREATE TABLE #{table}", "CREATE TABLE #{table}_new"
  db.exec "INSERT INTO #{table}_new (#{list}) SELECT #{list} FROM #{table}"
  db.exec "DROP TABLE #{table}"
  db.exec "ALTER TABLE #{table}_new RENAME TO #{table}"
  db.exec index for index in indexes


try
  # foreign_keys must be OFF during a rebuild, or SQLite validates the
  # half-built table before the rename. Matches the 2026-05-19 migration.
  db.exec 'PRAGMA foreign_keys = OFF'
  db.exec 'BEGIN TRANSACTION'

  rebuild 'tasks',
    ['id', 'project_id', 'name', 'description', 'status', 'estimated_hours', 'created_at', 'updated_at'],
    """
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        project_id TEXT REFERENCES projects(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        description TEXT,
        status TEXT DEFAULT 'pending',
        estimated_hours REAL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    """

  rebuild 'work_events',
    ['id', 'session_id', 'event_type', 'timestamp', 'created_at'],
    """
      CREATE TABLE work_events (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL REFERENCES work_sessions(id) ON DELETE CASCADE,
        event_type TEXT NOT NULL,
        timestamp DATETIME NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    """,
    ['CREATE INDEX IF NOT EXISTS idx_work_events_session ON work_events(session_id)']

  rebuild 'current_sessions',
    ['worker', 'session_id'],
    """
      CREATE TABLE current_sessions (
        worker TEXT PRIMARY KEY,
        session_id TEXT REFERENCES work_sessions(id) ON DELETE CASCADE
      )
    """

  rebuild 'work_logs',
    ['id', 'worker', 'start_time', 'end_time', 'duration', 'description',
     'project_id', 'task_id', 'billable', 'submitted', 'created_at'],
    """
      CREATE TABLE work_logs (
        id TEXT PRIMARY KEY,
        worker TEXT NOT NULL,
        start_time DATETIME NOT NULL,
        end_time DATETIME NOT NULL,
        duration INTEGER NOT NULL,
        description TEXT NOT NULL,
        project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
        task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
        billable BOOLEAN DEFAULT 1,
        submitted BOOLEAN DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    """,
    [
      'CREATE INDEX IF NOT EXISTS idx_work_logs_worker ON work_logs(worker)'
      'CREATE INDEX IF NOT EXISTS idx_work_logs_start_time ON work_logs(start_time)'
      'CREATE INDEX IF NOT EXISTS idx_work_logs_date ON work_logs(DATE(start_time))'
    ]

  # Scoped to the tables this migration rebuilt. `PRAGMA foreign_key_check`
  # with no argument checks every table in the database — including legacy
  # ones (e.g. an orphaned rent_events row) this migration has nothing to do
  # with. Since migrations run from schema.initialize at every boot (bug 54),
  # an unrelated pre-existing orphan aborted this migration, and therefore
  # boot, every single time.
  # PRAGMA does not accept a bound parameter for its argument; these four
  # names are the fixed list rebuilt above, not external input.
  for table in ['tasks', 'work_events', 'current_sessions', 'work_logs']
    violations = db.prepare("PRAGMA foreign_key_check(#{table})").all()
    if violations.length > 0
      throw new Error "FK violations in #{table} after rebuild: #{JSON.stringify violations}"

  db.exec 'COMMIT'
  console.log 'Migration completed successfully'

catch err
  console.error 'Migration failed:', err.message
  try
    db.exec 'ROLLBACK'
  catch rollbackErr
    console.error 'Rollback ALSO failed — the database may be mid-transaction:',
      rollbackErr.message
  throw err

finally
  db.exec 'PRAGMA foreign_keys = ON'
  db.close()
