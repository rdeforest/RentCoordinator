{ DatabaseSync } = require 'node:sqlite'
config           = require '../config.coffee'


openConnection = ->
  handle = new DatabaseSync config.DB_PATH
  handle.exec 'PRAGMA foreign_keys = ON'
  handle


connection = openConnection()


# Callers hold this object, not the connection underneath it.
#
# A restore renames a new file over the database path, and an open handle
# follows the inode rather than the name: after a restore the process would
# keep answering reads from the pre-restore database and fail every write with
# SQLITE_READONLY, while /health — which queries this same handle — went on
# reporting healthy. The indirection lets reopen() swap the connection without
# every module re-requiring it. Nothing caches a prepared statement across
# calls, so there is nothing to invalidate.
db =
  prepare: (args...) -> connection.prepare args...
  exec:    (args...) -> connection.exec    args...
  close:   (args...) -> connection.close   args...


reopen = ->
  # Open before closing. Closing first and assigning second means a failed
  # open — a bad mount, a permission change on the restored file, no disk —
  # leaves `connection` pointing at a closed handle, and every query in the
  # process throws "database is not open" for ever with no path back.
  replacement = openConnection()
  previous    = connection
  connection  = replacement

  # Anything cached from the old database is now wrong. Required lazily: this
  # module loads before the services that depend on it.
  require('../services/tokenization.coffee').clearCaches()

  try
    previous.close()
  catch err
    # The new handle is already in place, so a failure here costs a file
    # descriptor rather than the process. Worth saying out loud, not worth
    # unwinding a restore for.
    console.warn "Could not close the previous database handle: #{err.message}"

  db

SCHEMA = """
  CREATE TABLE IF NOT EXISTS projects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'planning',
    stakeholders TEXT, -- JSON array
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY,
    project_id TEXT REFERENCES projects(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'pending',
    estimated_hours REAL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS work_sessions (
    id TEXT PRIMARY KEY,
    worker TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    description TEXT,
    total_duration INTEGER DEFAULT 0,
    billable BOOLEAN DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS work_events (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES work_sessions(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL,
    timestamp DATETIME NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE INDEX IF NOT EXISTS idx_work_events_session ON work_events(session_id);

  CREATE TABLE IF NOT EXISTS current_sessions (
    worker TEXT PRIMARY KEY,
    session_id TEXT REFERENCES work_sessions(id) ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS work_logs (
    id TEXT PRIMARY KEY,
    worker TEXT NOT NULL,
    start_time DATETIME NOT NULL,
    end_time DATETIME NOT NULL,
    duration INTEGER NOT NULL, -- minutes
    description TEXT NOT NULL,
    project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
    task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
    billable BOOLEAN DEFAULT 1,
    submitted BOOLEAN DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE INDEX IF NOT EXISTS idx_work_logs_worker ON work_logs(worker);
  CREATE INDEX IF NOT EXISTS idx_work_logs_start_time ON work_logs(start_time);
  CREATE INDEX IF NOT EXISTS idx_work_logs_date ON work_logs(DATE(start_time));

  -- Vestigial. Nothing in lib/ reads or writes this table; the only reference
  -- left is the health check asserting it exists. Its project_id/task_id are
  -- where an earlier design kept the timer's project — they are not a working
  -- alternative to giving work_sessions those columns (bug 29).
  CREATE TABLE IF NOT EXISTS timer_state (
    worker TEXT PRIMARY KEY,
    session_id TEXT,
    start_time DATETIME,
    project_id TEXT,
    task_id TEXT,
    status TEXT DEFAULT 'stopped'
  );

  CREATE TABLE IF NOT EXISTS rent_periods (
    id TEXT PRIMARY KEY,
    year INTEGER NOT NULL,
    month INTEGER NOT NULL,
    base_rent REAL NOT NULL,
    hourly_credit REAL NOT NULL,
    max_monthly_hours REAL NOT NULL,
    hours_worked REAL DEFAULT 0,
    hours_from_previous REAL DEFAULT 0,
    hours_to_next REAL DEFAULT 0,
    manual_adjustments REAL DEFAULT 0,
    discount_applied REAL DEFAULT 0,
    amount_due REAL NOT NULL,
    amount_due_manual BOOLEAN DEFAULT 0,
    amount_paid REAL DEFAULT 0,
    amount_paid_manual BOOLEAN DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(year, month)
  );

  CREATE TABLE IF NOT EXISTS rent_events (
    id TEXT PRIMARY KEY,
    period_id TEXT NOT NULL REFERENCES rent_periods(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    amount REAL NOT NULL,
    description TEXT,
    metadata TEXT, -- JSON
    deleted_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE INDEX IF NOT EXISTS idx_rent_events_period     ON rent_events(period_id);
  CREATE INDEX IF NOT EXISTS idx_rent_events_type       ON rent_events(type);
  CREATE INDEX IF NOT EXISTS idx_rent_events_deleted_at ON rent_events(deleted_at);

  CREATE TABLE IF NOT EXISTS audit_logs (
    id TEXT PRIMARY KEY,
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    user TEXT,
    changes TEXT, -- JSON
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON audit_logs(entity_type, entity_id);

  -- See docs/event-model.md. Single source of truth for the rent system:
  -- payments, work reports, config changes, overrides, edits, deletes. The
  -- per-period state shown in the UI is computed from this table on demand.
  CREATE TABLE IF NOT EXISTS events (
    id              TEXT PRIMARY KEY,
    occurred_at     DATETIME NOT NULL,
    effective_for   TEXT,  -- 'YYYY-MM' or NULL for events that apply globally
    actor           TEXT NOT NULL,  -- 'tenant' | 'landlord'
    actor_user      TEXT NOT NULL,  -- email
    action          TEXT NOT NULL,  -- see docs/event-model.md
    payload         TEXT NOT NULL,  -- JSON, shape depends on action
    target_event_id TEXT REFERENCES events(id) ON DELETE CASCADE,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE INDEX IF NOT EXISTS idx_events_effective_for   ON events(effective_for);
  CREATE INDEX IF NOT EXISTS idx_events_actor_user      ON events(actor_user);
  CREATE INDEX IF NOT EXISTS idx_events_target_event_id ON events(target_event_id);
  CREATE INDEX IF NOT EXISTS idx_events_action          ON events(action);

  CREATE TABLE IF NOT EXISTS recurring_events (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    description TEXT NOT NULL,
    amount REAL NOT NULL,
    frequency TEXT NOT NULL,
    day_of_month INTEGER,
    start_date DATE NOT NULL,
    end_date DATE,
    last_processed DATE,
    active BOOLEAN DEFAULT 1,
    metadata TEXT, -- JSON
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS recurring_event_logs (
    id TEXT PRIMARY KEY,
    recurring_event_id TEXT NOT NULL REFERENCES recurring_events(id) ON DELETE CASCADE,
    period_id TEXT NOT NULL REFERENCES rent_periods(id) ON DELETE CASCADE,
    amount REAL NOT NULL,
    status TEXT,
    message TEXT,
    error_details TEXT,
    events_created TEXT, -- JSON array of event ids
    processed_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS auth_sessions (
    id TEXT PRIMARY KEY,
    email TEXT NOT NULL,
    code TEXT NOT NULL,
    expires_at DATETIME NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE INDEX IF NOT EXISTS idx_auth_sessions_email ON auth_sessions(email);
  CREATE INDEX IF NOT EXISTS idx_auth_sessions_code ON auth_sessions(code);

  CREATE TABLE IF NOT EXISTS pii_tokens (
    token TEXT PRIMARY KEY,
    value TEXT NOT NULL UNIQUE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_accessed DATETIME DEFAULT CURRENT_TIMESTAMP,
    access_count INTEGER DEFAULT 0
  );

  CREATE INDEX IF NOT EXISTS idx_pii_tokens_value ON pii_tokens(value);

  CREATE TABLE IF NOT EXISTS rent_configuration (
    id TEXT PRIMARY KEY,
    temporary_rent_amount REAL,
    apply_override BOOLEAN DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  -- Bug 65: express-session's default MemoryStore dies with the process and
  -- never evicts. expires is a millisecond epoch (session.cookie.expires, or
  -- now + SESSION_MAX_AGE for a session with no persistent cookie), so the
  -- sweep in lib/services/session-store.coffee can compare it against
  -- Date.now() without parsing a string on every pass.
  CREATE TABLE IF NOT EXISTS sessions (
    sid TEXT PRIMARY KEY,
    sess TEXT NOT NULL,
    expires INTEGER NOT NULL
  );

  CREATE INDEX IF NOT EXISTS idx_sessions_expires ON sessions(expires);

  -- Bug 62: consistency checks that report and never block. One row per
  -- scheduled/manual run; findings is the JSON array the checks produced.
  -- Pruned to the last ~30 rows by lib/models/consistency.coffee.
  CREATE TABLE IF NOT EXISTS consistency_runs (
    id          INTEGER PRIMARY KEY,
    ran_at      TEXT NOT NULL,
    fingerprint TEXT NOT NULL,
    findings    TEXT NOT NULL
  );

  -- A finding's key is stable across runs (it encodes the values involved),
  -- so acknowledging it here survives it reappearing in the next run.
  CREATE TABLE IF NOT EXISTS finding_acknowledgments (
    finding_key     TEXT PRIMARY KEY,
    note            TEXT NOT NULL,
    acknowledged_by TEXT,
    acknowledged_at TEXT NOT NULL
  );
"""


# CREATE ... IF NOT EXISTS only: brings an older database's tables up to date
# without touching the ones it has.
ensureTables = -> db.exec SCHEMA


initialize = ->
  console.log "Initializing SQLite database at #{config.DB_PATH}"

  ensureTables()

  # Migrations run here, not only in the instance bootstrap. CREATE TABLE IF
  # NOT EXISTS above never alters an existing table, so a database that
  # predates a column the running code needs would otherwise serve errors
  # until someone remembered to migrate by hand — and the documented in-place
  # upgrade (git pull, restart) has no such step. Failing to migrate has to
  # stop the boot; old schema plus new code is the outage.
  # db.exec SCHEMA above has already created the file, so the runner's
  # "no database" guard cannot fire here.
  { runMigrations } = require '../../scripts/run-migrations.coffee'
  runMigrations()

  initTimerState = db.prepare """
    INSERT OR IGNORE INTO timer_state (worker, status, session_id, start_time, project_id, task_id)
    VALUES (?, 'stopped', NULL, NULL, NULL, NULL)
  """

  for worker in config.WORKERS
    initTimerState.run worker

  console.log "Database initialized successfully"


module.exports = { db, reopen, ensureTables, initialize }
