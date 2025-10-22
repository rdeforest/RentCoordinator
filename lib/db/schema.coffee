# lib/db/schema.coffee
# SQLite database schema and initialization

{ DatabaseSync } = require 'node:sqlite'
config           = require '../config.coffee'

# Open database connection
db = new DatabaseSync(config.DB_PATH)

# Enable foreign keys
db.exec('PRAGMA foreign_keys = ON')


# Schema definition
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
    project_id TEXT REFERENCES projects(id),
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
    session_id TEXT NOT NULL REFERENCES work_sessions(id),
    event_type TEXT NOT NULL,
    timestamp DATETIME NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE INDEX IF NOT EXISTS idx_work_events_session ON work_events(session_id);

  CREATE TABLE IF NOT EXISTS current_sessions (
    worker TEXT PRIMARY KEY,
    session_id TEXT REFERENCES work_sessions(id)
  );

  CREATE TABLE IF NOT EXISTS work_logs (
    id TEXT PRIMARY KEY,
    worker TEXT NOT NULL,
    start_time DATETIME NOT NULL,
    end_time DATETIME NOT NULL,
    duration INTEGER NOT NULL, -- minutes
    description TEXT NOT NULL,
    project_id TEXT REFERENCES projects(id),
    task_id TEXT REFERENCES tasks(id),
    billable BOOLEAN DEFAULT 1,
    submitted BOOLEAN DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE INDEX IF NOT EXISTS idx_work_logs_worker ON work_logs(worker);
  CREATE INDEX IF NOT EXISTS idx_work_logs_start_time ON work_logs(start_time);
  CREATE INDEX IF NOT EXISTS idx_work_logs_date ON work_logs(DATE(start_time));

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
    amount_due REAL NOT NULL,
    amount_paid REAL DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(year, month)
  );

  CREATE TABLE IF NOT EXISTS rent_events (
    id TEXT PRIMARY KEY,
    period_id TEXT NOT NULL REFERENCES rent_periods(id),
    type TEXT NOT NULL,
    amount REAL NOT NULL,
    description TEXT,
    metadata TEXT, -- JSON
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE INDEX IF NOT EXISTS idx_rent_events_period ON rent_events(period_id);
  CREATE INDEX IF NOT EXISTS idx_rent_events_type ON rent_events(type);

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
    recurring_event_id TEXT NOT NULL REFERENCES recurring_events(id),
    period_id TEXT NOT NULL REFERENCES rent_periods(id),
    amount REAL NOT NULL,
    processed_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS auth_sessions (
    id TEXT PRIMARY KEY,
    email TEXT NOT NULL,
    code TEXT NOT NULL,
    expires_at DATETIME NOT NULL,
    verified BOOLEAN DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE INDEX IF NOT EXISTS idx_auth_sessions_email ON auth_sessions(email);
  CREATE INDEX IF NOT EXISTS idx_auth_sessions_code ON auth_sessions(code);
"""


initialize = ->
  console.log "Initializing SQLite database at #{config.DB_PATH}"

  # Execute schema
  db.exec(SCHEMA)

  # Initialize timer states for each worker
  initTimerState = db.prepare("""
    INSERT OR IGNORE INTO timer_state (worker, status, session_id, start_time, project_id, task_id)
    VALUES (?, 'stopped', NULL, NULL, NULL, NULL)
  """)

  for worker in config.WORKERS
    initTimerState.run(worker)

  console.log "Database initialized successfully"

  # Initialize recurring events system
  recurringEventsService = require '../services/recurring_events.coffee'
  await recurringEventsService.initializeRecurringEvents()


module.exports = { db, initialize }
