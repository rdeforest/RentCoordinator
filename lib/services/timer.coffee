# lib/services/timer.coffee

{ v1 }           = require 'uuid'
{ db }           = require '../db/schema.coffee'
config           = require '../config.coffee'
workLogModel     = require '../models/work_log.coffee'
workSessionModel = require '../models/work_session.coffee'


startTimer = (worker, project_id = null, task_id = null) ->
  # Validate worker
  if worker not in config.WORKERS
    throw new Error "Invalid worker: #{worker}"

  # Check if there's already an active session
  currentSession = await workSessionModel.getCurrentSession(worker)
  if currentSession?.status is 'active'
    throw new Error "Timer already running for #{worker}"

  # Pause any other active sessions (safety check)
  await workSessionModel.pauseActiveSessions(worker)

  # Create new session
  session = await workSessionModel.createWorkSession(worker)

  return {
    session...
    event: 'started'
  }


pauseTimer = (worker) ->
  # Validate worker
  if worker not in config.WORKERS
    throw new Error "Invalid worker: #{worker}"

  # Get current session
  currentSession = await workSessionModel.getCurrentSession(worker)
  if not currentSession or currentSession.status isnt 'active'
    throw new Error "No active timer for #{worker}"

  # Create pause event
  await workSessionModel.createWorkEvent(currentSession.id, 'pause')

  # Return updated session
  return await workSessionModel.getCurrentSession(worker)


resumeTimer = (worker, sessionId = null) ->
  # Validate worker
  if worker not in config.WORKERS
    throw new Error "Invalid worker: #{worker}"

  # If no sessionId provided, resume the current session
  if not sessionId
    currentSession = await workSessionModel.getCurrentSession(worker)
    if not currentSession
      throw new Error "No session to resume"
    sessionId = currentSession.id

  # Resume the session
  session = await workSessionModel.resumeSession(sessionId, worker)

  return {
    session...
    event: 'resumed'
  }


stopTimer = (worker, completed = true) ->
  # Validate worker
  if worker not in config.WORKERS
    throw new Error "Invalid worker: #{worker}"

  # Get current session
  currentSession = await workSessionModel.getCurrentSession(worker)
  if not currentSession
    throw new Error "No active timer for #{worker}"

  # Create stop or cancel event
  eventType = if completed then 'stop' else 'cancel'
  await workSessionModel.createWorkEvent(currentSession.id, eventType)

  # Calculate final duration
  duration = await workSessionModel.calculateSessionDuration(currentSession.id)

  # Only create work log if completed and has meaningful duration
  if completed and duration >= config.MIN_WORK_LOG_DURATION
    workLog = await workLogModel.createWorkLog(
      await workSessionModel.sessionToWorkLog(currentSession)
    )

    # Clear current session reference
    db.prepare("DELETE FROM current_sessions WHERE worker = ?").run(worker)

    return {
      session: currentSession
      work_log: workLog
      duration: duration
      event: 'completed'
    }
  else
    # Clear current session reference
    db.prepare("DELETE FROM current_sessions WHERE worker = ?").run(worker)

    return {
      session: currentSession
      duration: duration
      event: if completed then 'completed_too_short' else 'cancelled'
    }


updateDescription = (worker, description) ->
  # Get current session
  currentSession = await workSessionModel.getCurrentSession(worker)
  if not currentSession
    throw new Error "No active session for #{worker}"

  # Update description
  return await workSessionModel.updateSessionDescription(currentSession.id, description)


getStatus = (worker) ->
  if worker not in config.WORKERS
    throw new Error "Invalid worker: #{worker}"

  # Get current session
  currentSession = await workSessionModel.getCurrentSession(worker)

  if not currentSession
    return {
      worker: worker
      status: 'stopped'
      current_session: null
      elapsed: 0
    }

  # Calculate current duration
  duration = await workSessionModel.calculateSessionDuration(currentSession.id)

  return {
    worker: worker
    status: currentSession.status
    current_session: currentSession
    elapsed: duration
    elapsed_formatted: formatDuration(duration)
  }


getAllSessions = (worker) ->
  if worker not in config.WORKERS
    throw new Error "Invalid worker: #{worker}"

  sessions = await workSessionModel.getAllSessions(worker)

  # Add formatted duration to each session
  for session in sessions
    session.duration_formatted = formatDuration(session.total_duration)

  return sessions


# Helper to format duration for display
formatDuration = (seconds) ->
  hours   = Math.floor(seconds / 3600)
  minutes = Math.floor((seconds % 3600) / 60)
  secs    = seconds % 60

  parts = []
  parts.push "#{hours}h" if hours > 0
  parts.push "#{minutes}m" if minutes > 0 or hours > 0
  parts.push "#{secs}s"

  parts.join(' ')

module.exports = {
  startTimer
  pauseTimer
  resumeTimer
  stopTimer
  updateDescription
  getStatus
  getAllSessions
}