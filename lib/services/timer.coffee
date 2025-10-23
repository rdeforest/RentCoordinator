{ v1 }           = require 'uuid'
{ db }           = require '../db/schema.coffee'
config           = require '../config.coffee'
workLogModel     = require '../models/work_log.coffee'
workSessionModel = require '../models/work_session.coffee'


startTimer = (worker, project_id = null, task_id = null) ->
  unless worker in config.WORKERS
    throw new Error "Invalid worker: #{worker}"

  currentSession = await workSessionModel.getCurrentSession worker
  if currentSession?.status is 'active'
    throw new Error "Timer already running for #{worker}"

  await workSessionModel.pauseActiveSessions worker

  session = await workSessionModel.createWorkSession worker

  return {
    session...
    event: 'started'
  }


pauseTimer = (worker) ->
  unless worker in config.WORKERS
    throw new Error "Invalid worker: #{worker}"

  currentSession = await workSessionModel.getCurrentSession worker
  if not currentSession or currentSession.status isnt 'active'
    throw new Error "No active timer for #{worker}"

  await workSessionModel.createWorkEvent currentSession.id, 'pause'

  return await workSessionModel.getCurrentSession worker


resumeTimer = (worker, sessionId = null) ->
  unless worker in config.WORKERS
    throw new Error "Invalid worker: #{worker}"

  unless sessionId
    currentSession = await workSessionModel.getCurrentSession worker
    unless currentSession
      throw new Error "No session to resume"
    sessionId = currentSession.id

  session = await workSessionModel.resumeSession sessionId, worker

  return {
    session...
    event: 'resumed'
  }


stopTimer = (worker, completed = true) ->
  unless worker in config.WORKERS
    throw new Error "Invalid worker: #{worker}"

  currentSession = await workSessionModel.getCurrentSession worker
  unless currentSession
    throw new Error "No active timer for #{worker}"

  eventType = if completed then 'stop' else 'cancel'
  await workSessionModel.createWorkEvent currentSession.id, eventType

  duration = await workSessionModel.calculateSessionDuration currentSession.id

  if completed and duration >= config.MIN_WORK_LOG_DURATION
    workLog = await workLogModel.createWorkLog(
      await workSessionModel.sessionToWorkLog currentSession
    )

    db.prepare("DELETE FROM current_sessions WHERE worker = ?").run worker

    return
      session:  currentSession
      work_log: workLog
      duration: duration
      event:    'completed'
  else
    db.prepare("DELETE FROM current_sessions WHERE worker = ?").run worker

    return
      session:  currentSession
      duration: duration
      event:    if completed then 'completed_too_short' else 'cancelled'


updateDescription = (worker, description) ->
  currentSession = await workSessionModel.getCurrentSession worker
  unless currentSession
    throw new Error "No active session for #{worker}"

  return await workSessionModel.updateSessionDescription currentSession.id, description


getStatus = (worker) ->
  unless worker in config.WORKERS
    throw new Error "Invalid worker: #{worker}"

  currentSession = await workSessionModel.getCurrentSession worker

  unless currentSession
    return
      worker:          worker
      status:          'stopped'
      current_session: null
      elapsed:         0

  duration = await workSessionModel.calculateSessionDuration currentSession.id

  return
    worker:          worker
    status:          currentSession.status
    current_session: currentSession
    elapsed:         duration
    elapsed_formatted: formatDuration duration


getAllSessions = (worker) ->
  unless worker in config.WORKERS
    throw new Error "Invalid worker: #{worker}"

  sessions = await workSessionModel.getAllSessions worker

  for session in sessions
    session.duration_formatted = formatDuration session.total_duration

  return sessions


formatDuration = (seconds) ->
  hours   = Math.floor seconds / 3600
  minutes = Math.floor (seconds % 3600) / 60
  secs    = seconds % 60

  parts = []
  parts.push "#{hours}h"   if hours > 0
  parts.push "#{minutes}m" if minutes > 0 or hours > 0
  parts.push "#{secs}s"

  parts.join ' '

module.exports = {
  startTimer
  pauseTimer
  resumeTimer
  stopTimer
  updateDescription
  getStatus
  getAllSessions
}
