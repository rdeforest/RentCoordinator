# lib/db/schema.coffee

config = await import('../config.coffee')

# Open database connection
db = await Deno.openKv(config.DB_PATH)


# Schema definition as SQL statements
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

  CREATE TABLE IF NOT EXISTS timer_state (
    worker TEXT PRIMARY KEY,
    session_id TEXT,
    start_time DATETIME,
    project_id TEXT,
    task_id TEXT,
    status TEXT DEFAULT 'stopped'
  );
"""


export initialize = ->
  # For now, using Deno KV as SQLite isn't built-in yet
  # This will be migrated when SQLite support lands
  console.log "Database initialized at #{config.DB_PATH}"
  
  # Initialize timer states for each worker
  for worker in config.WORKERS
    key = ['timer_state', worker]
    existing = await db.get(key)
    
    if not existing.value
      await db.set key,
        worker: worker
        status: 'stopped'
        session_id: null
        start_time: null
        project_id: null
        task_id: null

  # Initialize recurring events system
  recurringEventsService = await import('../services/recurring_events.coffee')
  await recurringEventsService.initializeRecurringEvents()


export { db }