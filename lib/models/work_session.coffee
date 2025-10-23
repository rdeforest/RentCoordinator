{ v1 } = require 'uuid'
{ db } = require '../db/schema.coffee'


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


calculateSessionDuration = (sessionId) ->
  events = db.prepare("""
    SELECT * FROM work_events
    WHERE session_id = ?
    ORDER BY timestamp ASC
  """).all sessionId

  totalDuration = 0
  lastStartTime = null

  for event in events
    switch event.event_type
      when 'start', 'resume'
        lastStartTime = new Date event.timestamp
      when 'pause', 'stop', 'cancel'
        if lastStartTime
          duration       = (new Date(event.timestamp) - lastStartTime) / 1000
          totalDuration += duration
          lastStartTime  = null

  if lastStartTime
    duration       = (new Date() - lastStartTime) / 1000
    totalDuration += duration

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
  await pauseActiveSessions worker

  await createWorkEvent sessionId, 'resume'

  db.prepare("""
    INSERT OR REPLACE INTO current_sessions (worker, session_id)
    VALUES (?, ?)
  """).run worker, sessionId

  return db.prepare("SELECT * FROM work_sessions WHERE id = ?").get sessionId


sessionToWorkLog = (session) ->
  events = db.prepare("""
    SELECT * FROM work_events
    WHERE session_id = ?
    ORDER BY timestamp ASC
  """).all session.id

  firstEvent = events[0]
  lastEvent  = events[events.length - 1]

  return
    id:          session.id
    worker:      session.worker
    start_time:  firstEvent?.timestamp or session.created_at
    end_time:    lastEvent?.timestamp or new Date().toISOString()
    duration:    Math.round session.total_duration / 60
    description: session.description
    project_id:  session.project_id or null
    task_id:     session.task_id or null
    billable:    session.billable
    submitted:   false
    created_at:  session.created_at

module.exports = {
  createWorkSession
  createWorkEvent
  updateSessionDescription
  getCurrentSession
  calculateSessionDuration
  getAllSessions
  pauseActiveSessions
  resumeSession
  sessionToWorkLog
}
