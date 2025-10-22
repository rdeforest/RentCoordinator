# lib/models/work_session.coffee

{ v1 } = await import('uuid')
db = (await import('../db/schema.coffee')).db


# Create a new work session
export createWorkSession = (worker) ->
  id = v1()
  now = new Date().toISOString()

  # Insert session
  db.prepare("""
    INSERT INTO work_sessions (id, worker, description, status, total_duration, billable, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  """).run(id, worker, '', 'active', 0, 1, now, now)

  # Set current session
  db.prepare("""
    INSERT OR REPLACE INTO current_sessions (worker, session_id)
    VALUES (?, ?)
  """).run(worker, id)

  # Create initial start event
  await createWorkEvent id, 'start', now

  # Return the session
  return db.prepare("SELECT * FROM work_sessions WHERE id = ?").get(id)


# Create a work event (start/pause/resume/stop/cancel)
export createWorkEvent = (sessionId, eventType, timestamp = null) ->
  id = v1()
  timestamp ?= new Date().toISOString()

  # Insert event
  db.prepare("""
    INSERT INTO work_events (id, session_id, event_type, timestamp, created_at)
    VALUES (?, ?, ?, ?, ?)
  """).run(id, sessionId, eventType, timestamp, new Date().toISOString())

  # Update session status based on event
  await updateSessionStatus sessionId, eventType

  return db.prepare("SELECT * FROM work_events WHERE id = ?").get(id)


# Update session status based on event
updateSessionStatus = (sessionId, eventType) ->
  newStatus = switch eventType
    when 'start', 'resume' then 'active'
    when 'pause' then 'paused'
    when 'stop' then 'completed'
    when 'cancel' then 'cancelled'
    else null

  return unless newStatus

  db.prepare("""
    UPDATE work_sessions
    SET status = ?, updated_at = ?
    WHERE id = ?
  """).run(newStatus, new Date().toISOString(), sessionId)


# Update work session description
export updateSessionDescription = (sessionId, description) ->
  db.prepare("""
    UPDATE work_sessions
    SET description = ?, updated_at = ?
    WHERE id = ?
  """).run(description, new Date().toISOString(), sessionId)

  return db.prepare("SELECT * FROM work_sessions WHERE id = ?").get(sessionId)


# Get current session for a worker
export getCurrentSession = (worker) ->
  result = db.prepare("""
    SELECT s.* FROM work_sessions s
    JOIN current_sessions cs ON cs.session_id = s.id
    WHERE cs.worker = ?
  """).get(worker)

  return result or null


# Calculate total duration for a session
export calculateSessionDuration = (sessionId) ->
  # Get all events for this session
  events = db.prepare("""
    SELECT * FROM work_events
    WHERE session_id = ?
    ORDER BY timestamp ASC
  """).all(sessionId)

  totalDuration = 0
  lastStartTime = null

  for event in events
    switch event.event_type
      when 'start', 'resume'
        lastStartTime = new Date(event.timestamp)
      when 'pause', 'stop', 'cancel'
        if lastStartTime
          duration = (new Date(event.timestamp) - lastStartTime) / 1000  # seconds
          totalDuration += duration
          lastStartTime = null

  # If still running, add time since last start
  if lastStartTime
    duration = (new Date() - lastStartTime) / 1000
    totalDuration += duration

  return Math.round(totalDuration)


# Get all sessions with calculated durations
export getAllSessions = (worker = null) ->
  query = if worker
    db.prepare("SELECT * FROM work_sessions WHERE worker = ?")
  else
    db.prepare("SELECT * FROM work_sessions")

  sessions = if worker then query.all(worker) else query.all()

  # Calculate current duration for each session
  for session in sessions
    session.total_duration = await calculateSessionDuration(session.id)

  return sessions


# Pause all active sessions for a worker
export pauseActiveSessions = (worker) ->
  sessions = await getAllSessions(worker)

  for session in sessions
    if session.status is 'active'
      await createWorkEvent session.id, 'pause'


# Resume a session (pauses others first)
export resumeSession = (sessionId, worker) ->
  # Pause any active sessions
  await pauseActiveSessions(worker)

  # Resume this session
  await createWorkEvent sessionId, 'resume'

  # Update current session reference
  db.prepare("""
    INSERT OR REPLACE INTO current_sessions (worker, session_id)
    VALUES (?, ?)
  """).run(worker, sessionId)

  return db.prepare("SELECT * FROM work_sessions WHERE id = ?").get(sessionId)


# Convert session to work log entry (for backwards compatibility)
export sessionToWorkLog = (session) ->
  # Get first and last events
  events = db.prepare("""
    SELECT * FROM work_events
    WHERE session_id = ?
    ORDER BY timestamp ASC
  """).all(session.id)

  firstEvent = events[0]
  lastEvent = events[events.length - 1]

  return {
    id: session.id
    worker: session.worker
    start_time: firstEvent?.timestamp or session.created_at
    end_time: lastEvent?.timestamp or new Date().toISOString()
    duration: Math.round(session.total_duration / 60)  # Convert to minutes
    description: session.description
    project_id: session.project_id or null
    task_id: session.task_id or null
    billable: session.billable
    submitted: false
    created_at: session.created_at
  }
