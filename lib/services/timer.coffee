{ v1 }           = require 'uuid'
{ db }           = require '../db/schema.coffee'
config           = require '../config.coffee'
workLogModel     = require '../models/work_log.coffee'
workSessionModel = require '../models/work_session.coffee'
rentService      = require './rent.coffee'


clearCurrentSession = (worker) ->
  db.prepare("DELETE FROM current_sessions WHERE worker = ?").run worker


# The manual work-log routes recalculate the tenant's rent period after every
# write. The timer path did not, so work clocked through the timer never
# reached the period (bug 31).
recalculateFor = (log) ->
  return unless config.isTenant log.worker

  date = new Date log.start_time
  await rentService.createOrUpdateRentPeriod date.getFullYear(), date.getMonth() + 1


CLOSEABLE = ['active', 'paused']


# Close a session, and when it counts as completed work turn it into a work
# log. Shared by an explicit stop and by the timeout sweep below, so a session
# that timed out is recorded exactly the way a stopped one is.
#
# The session is re-read here rather than trusted from the caller. stopTimer
# awaits twice before reaching this point, and two overlapping requests — a
# double-clicked Stop button — each arrived carrying their own stale copy and
# each wrote a work log. One hour worked, credited twice: $100 off the rent
# instead of $50.
finishSession = (worker, session, { completed, at }) ->
  current = workSessionModel.getSession session.id

  unless current?.status in CLOSEABLE
    throw new Error "Session #{session.id} is already #{current?.status ? 'gone'}"

  session = current

  await workSessionModel.createWorkEvent session.id, (if completed then 'stop' else 'cancel'), at

  duration = await workSessionModel.calculateSessionDuration session.id
  clearCurrentSession worker

  unless completed and duration >= config.MIN_WORK_LOG_DURATION
    return
      session:  session
      duration: duration
      event:    if completed then 'completed_too_short' else 'cancelled'

  workLog = await workLogModel.createWorkLog(
    await workSessionModel.sessionToWorkLog session
  )

  await recalculateFor workLog

  return
    session:  session
    work_log: workLog
    duration: duration
    event:    'completed'


# The worker's current session, after closing it if the clock has been running
# past SESSION_TIMEOUT. Every timer operation reads through here, so an
# abandoned timer stops accruing time and stops blocking the next session.
# This does write on a read path — /timer/status is polled every second — but
# a timeout that only fires when someone remembers to stop the timer is not a
# timeout.
currentSessionOf = (worker, now = new Date()) ->
  session = await workSessionModel.getCurrentSession worker
  return session unless session?.status is 'active'

  openedAt = workSessionModel.openSegmentStart session.id
  return session unless openedAt

  cutoff = new Date openedAt.getTime() + config.SESSION_TIMEOUT
  return session if cutoff > now

  await finishSession worker, session, completed: true, at: cutoff.toISOString()
  return null


startTimer = (worker, project_id = null, task_id = null) ->
  unless worker in config.WORKERS
    throw new Error "Invalid worker: #{worker}"

  currentSession = await currentSessionOf worker
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

  currentSession = await currentSessionOf worker
  if not currentSession or currentSession.status isnt 'active'
    throw new Error "No active timer for #{worker}"

  await workSessionModel.createWorkEvent currentSession.id, 'pause'

  return await workSessionModel.getCurrentSession worker


resumeTimer = (worker, sessionId = null) ->
  unless worker in config.WORKERS
    throw new Error "Invalid worker: #{worker}"

  unless sessionId
    currentSession = await currentSessionOf worker
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

  currentSession = await currentSessionOf worker
  unless currentSession
    throw new Error "No active timer for #{worker}"

  return await finishSession worker, currentSession, { completed, at: null }


updateDescription = (worker, description) ->
  currentSession = await currentSessionOf worker
  unless currentSession
    throw new Error "No active session for #{worker}"

  return await workSessionModel.updateSessionDescription currentSession.id, description


getStatus = (worker) ->
  unless worker in config.WORKERS
    throw new Error "Invalid worker: #{worker}"

  currentSession = await currentSessionOf worker

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
