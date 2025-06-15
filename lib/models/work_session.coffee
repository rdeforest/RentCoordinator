# lib/models/work_session.coffee

{ v1 } = await import('uuid')
db = (await import('../db/schema.coffee')).db


# Create a new work session
export createWorkSession = (worker) ->
  id = v1.generate()
  now = new Date().toISOString()

  session =
    id: id
    worker: worker
    description: ''
    status: 'active'  # active, paused, completed, cancelled
    created_at: now
    updated_at: now
    total_duration: 0  # Total accumulated time in seconds
    billable: true

  key = ['work_sessions', id]
  await db.set key, session

  # Also maintain current session reference
  currentKey = ['current_session', worker]
  await db.set currentKey, id

  # Create initial start event
  await createWorkEvent id, 'start', now

  return session


# Create a work event (start/pause/resume/stop/cancel)
export createWorkEvent = (sessionId, eventType, timestamp = null) ->
  id = v1.generate()
  timestamp ?= new Date().toISOString()

  event =
    id: id
    session_id: sessionId
    event_type: eventType  # start, pause, resume, stop, cancel
    timestamp: timestamp
    created_at: new Date().toISOString()

  key = ['work_events', sessionId, id]
  await db.set key, event

  # Update session status based on event
  await updateSessionStatus sessionId, eventType

  return event


# Update session status based on event
updateSessionStatus = (sessionId, eventType) ->
  sessionKey = ['work_sessions', sessionId]
  session = await db.get(sessionKey)

  return unless session.value

  newStatus = switch eventType
    when 'start', 'resume' then 'active'
    when 'pause' then 'paused'
    when 'stop' then 'completed'
    when 'cancel' then 'cancelled'
    else session.value.status

  updated = Object.assign {}, session.value,
    status: newStatus
    updated_at: new Date().toISOString()

  await db.set sessionKey, updated


# Update work session description
export updateSessionDescription = (sessionId, description) ->
  key = ['work_sessions', sessionId]
  session = await db.get(key)

  return null unless session.value

  updated = Object.assign {}, session.value,
    description: description
    updated_at: new Date().toISOString()

  await db.set key, updated
  return updated


# Get current session for a worker
export getCurrentSession = (worker) ->
  currentKey = ['current_session', worker]
  sessionIdResult = await db.get(currentKey)

  return null unless sessionIdResult.value

  sessionKey = ['work_sessions', sessionIdResult.value]
  session = await db.get(sessionKey)

  return session.value


# Calculate total duration for a session
export calculateSessionDuration = (sessionId) ->
  # Get all events for this session
  events = []
  prefix = ['work_events', sessionId]
  entries = db.list({ prefix })

  for await entry from entries
    events.push entry.value

  # Sort events by timestamp
  events.sort (a, b) -> new Date(a.timestamp) - new Date(b.timestamp)

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
  sessions = []
  prefix = ['work_sessions']
  entries = db.list({ prefix })

  for await entry from entries
    session = entry.value
    if not worker or session.worker is worker
      # Calculate current duration
      session.total_duration = await calculateSessionDuration(session.id)
      sessions.push session

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
  currentKey = ['current_session', worker]
  await db.set currentKey, sessionId

  sessionKey = ['work_sessions', sessionId]
  session = await db.get(sessionKey)
  return session.value


# Convert session to work log entry (for backwards compatibility)
export sessionToWorkLog = (session) ->
  # Get first and last events
  events = []
  prefix = ['work_events', session.id]
  entries = db.list({ prefix })

  for await entry from entries
    events.push entry.value

  events.sort (a, b) -> new Date(a.timestamp) - new Date(b.timestamp)

  firstEvent = events[0]
  lastEvent = events[events.length - 1]

  return {
    id: session.id
    worker: session.worker
    start_time: firstEvent?.timestamp or session.created_at
    end_time: lastEvent?.timestamp or new Date().toISOString()
    duration: Math.round(session.total_duration / 60)  # Convert to minutes
    description: session.description
    billable: session.billable
    submitted: false
    created_at: session.created_at
  }