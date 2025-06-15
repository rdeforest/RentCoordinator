{ v4: uuidv4 } = await import('uuid')
db = (await import('../db/schema.coffee')).db


export createWorkLog = (data) ->
  id = uuidv4.generate()

  workLog =
    id: id
    worker: data.worker
    start_time: data.start_time
    end_time: data.end_time
    duration: data.duration
    description: data.description
    project_id: data.project_id or null
    task_id: data.task_id or null
    billable: data.billable ? true
    submitted: false
    created_at: new Date().toISOString()

  # Store in KV store
  key = ['work_logs', id]
  await db.set key, workLog

  # Also maintain index by worker
  workerKey = ['work_logs_by_worker', data.worker, id]
  await db.set workerKey, id

  # And by date for efficient queries
  dateKey = ['work_logs_by_date', data.start_time.split('T')[0], id]
  await db.set dateKey, id

  return workLog


export getWorkLogs = (filters = {}) ->
  logs = []

  if filters.worker
    # Get logs for specific worker
    prefix = ['work_logs_by_worker', filters.worker]
    entries = db.list({ prefix })

    for await (entry from entries)
      logId = entry.value
      logKey = ['work_logs', logId]
      log = await db.get(logKey)
      if log.value
        logs.push log.value
  else
    # Get all logs
    prefix = ['work_logs']
    entries = db.list({ prefix })

    for await (entry from entries)
      if entry.value?.worker  # Make sure it's a log entry, not an index
        logs.push entry.value

  # Apply additional filters
  if filters.project_id
    logs = logs.filter (log) -> log.project_id is filters.project_id

  # Sort by start time descending
  logs.sort (a, b) -> new Date(b.start_time) - new Date(a.start_time)

  # Apply limit
  if filters.limit
    logs = logs.slice(0, parseInt(filters.limit))

  return logs


export getWorkLogById = (id) ->
  key = ['work_logs', id]
  result = await db.get(key)
  return result.value


export updateWorkLog = (id, updates) ->
  key = ['work_logs', id]
  existing = await db.get(key)

  if not existing.value
    throw new Error "Work log not found: #{id}"

  updated = {
    existing.value...
    updates...
    id: id  # Ensure ID doesn't change
    updated_at: new Date().toISOString()
  }

  await db.set key, updated
  return updated