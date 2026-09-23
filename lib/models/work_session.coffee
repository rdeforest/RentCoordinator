{ v1 }  = require 'uuid'
{ db }  = require '../db/schema.coffee'
config  = require '../config.coffee'


createWorkSession = (worker) ->
  id  = v1()
  now = new Date().toISOString()

  db.prepare("""
    INSERT INTO work_sessions (id, worker, description, status, total_duration, billable, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  """).run id, worker, '', 'active', 0, 1, now, now

  db.prepare("""
    INSERT OR REPLACE INTO current_sessions (worker, session_id)
    VALUES (?, ?)
  """).run worker, id

  await createWorkEvent id, 'start', now

  return db.prepare("SELECT * FROM work_sessions WHERE id = ?").get id


createWorkEvent = (sessionId, eventType, timestamp = null) ->
  id        = v1()
  timestamp ?= new Date().toISOString()

  db.prepare("""
    INSERT INTO work_events (id, session_id, event_type, timestamp, created_at)
    VALUES (?, ?, ?, ?, ?)
  """).run id, sessionId, eventType, timestamp, new Date().toISOString()

  await updateSessionStatus sessionId, eventType

  return db.prepare("SELECT * FROM work_events WHERE id = ?").get id


updateSessionStatus = (sessionId, eventType) ->
  newStatus = switch eventType
    when 'start', 'resume' then 'active'
    when 'pause'           then 'paused'
    when 'stop'            then 'completed'
    when 'cancel'          then 'cancelled'
    else null

  return unless newStatus

  db.prepare("""
    UPDATE work_sessions
    SET status = ?, updated_at = ?
    WHERE id = ?
  """).run newStatus, new Date().toISOString(), sessionId


updateSessionDescription = (sessionId, description) ->
  db.prepare("""
    UPDATE work_sessions
    SET description = ?, updated_at = ?
    WHERE id = ?
  """).run description, new Date().toISOString(), sessionId

  return db.prepare("SELECT * FROM work_sessions WHERE id = ?").get sessionId


getCurrentSession = (worker) ->
  result = db.prepare("""
    SELECT s.* FROM work_sessions s
    JOIN current_sessions cs ON cs.session_id = s.id
    WHERE cs.worker = ?
  """).get worker

  return result or null


sessionEvents = (sessionId) ->
  db.prepare("""
    SELECT * FROM work_events
    WHERE session_id = ?
    ORDER BY timestamp ASC
  """).all sessionId


# When the last event left the clock running, the instant it started. Null
# for a session that is paused, stopped or cancelled.
openSegmentStart = (sessionId) ->
  openedAt = null

  for event in sessionEvents sessionId
    switch event.event_type
      when 'start', 'resume'         then openedAt = new Date event.timestamp
      when 'pause', 'stop', 'cancel'  then openedAt = null

  openedAt


calculateSessionDuration = (sessionId, now = new Date()) ->
  totalDuration = 0
  lastStartTime = null

  for event in sessionEvents sessionId
    switch event.event_type
      when 'start', 'resume'
        lastStartTime = new Date event.timestamp
      when 'pause', 'stop', 'cancel'
        if lastStartTime
          duration       = (new Date(event.timestamp) - lastStartTime) / 1000
          totalDuration += duration
          lastStartTime  = null

  # A timer nobody stopped — browser closed, laptop slept — would otherwise
  # accrue wall-clock time without bound. The open segment is capped at
  # SESSION_TIMEOUT; timerService closes such a session at the cap.
  if lastStartTime
    elapsed        = (now - lastStartTime) / 1000
    totalDuration += Math.min elapsed, config.SESSION_TIMEOUT / 1000

  return Math.round totalDuration


getAllSessions = (worker = null) ->
  query = if worker
    db.prepare "SELECT * FROM work_sessions WHERE worker = ?"
  else
    db.prepare "SELECT * FROM work_sessions"

  sessions = if worker then query.all worker else query.all()

  for session in sessions
    session.total_duration = await calculateSessionDuration session.id

  return sessions


pauseActiveSessions = (worker) ->
  sessions = await getAllSessions worker

  for session in sessions
    if session.status is 'active'
      await createWorkEvent session.id, 'pause'


resumeSession = (sessionId, worker) ->
  session = db.prepare("SELECT * FROM work_sessions WHERE id = ?").get sessionId

  unless session
    throw new Error "Session not found: #{sessionId}"

  unless session.worker is worker
    throw new Error "Session #{sessionId} does not belong to #{worker}"

  unless session.status is 'paused'
    throw new Error "Cannot resume a #{session.status} session"

  await pauseActiveSessions worker

  await createWorkEvent sessionId, 'resume'

  db.prepare("""
    INSERT OR REPLACE INTO current_sessions (worker, session_id)
    VALUES (?, ?)
  """).run worker, sessionId

  return db.prepare("SELECT * FROM work_sessions WHERE id = ?").get sessionId


sessionToWorkLog = (session) ->
  events     = sessionEvents session.id
  firstEvent = events[0]
  lastEvent  = events[events.length - 1]

  # Not session.total_duration: that column is written as 0 at INSERT and
  # never maintained. Duration lives in the work_events timeline, and
  # calculateSessionDuration is the one place that reads it.
  seconds = calculateSessionDuration session.id

  return
    worker:      session.worker
    start_time:  firstEvent?.timestamp or session.created_at
    end_time:    lastEvent?.timestamp or new Date().toISOString()
    duration:    Math.round seconds / 60
    description: session.description
    project_id:  session.project_id or null
    task_id:     session.task_id or null
    billable:    session.billable

module.exports = {
  createWorkSession
  createWorkEvent
  updateSessionDescription
  getCurrentSession
  openSegmentStart
  calculateSessionDuration
  getAllSessions
  pauseActiveSessions
  resumeSession
  sessionToWorkLog
}
