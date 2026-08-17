{ v1 }                   = require 'uuid'
{ db }                   = require '../db/schema.coffee'
{ formatSQLParameters }  = require '../db/utils.coffee'
config                   = require '../config.coffee'
eventsModel              = require './events.coffee'


# The 'YYYY-MM' the work falls in, in UTC — matches the seed migration so
# live and seeded work-reported events bucket into the same month.
monthKeyFromISO = (iso) ->
  d = new Date iso
  "#{d.getUTCFullYear()}-#{String(d.getUTCMonth() + 1).padStart 2, '0'}"


identityFor = (worker) ->
  config.WORKER_IDENTITY[worker] or { actor: 'tenant', user: 'unknown@unknown' }


# A work log IS a work-reported event (see docs/event-model.md). The rent
# dashboard folds events, so a log that emits no event never credits rent —
# that was bug 06. Reuse the work_log id as the event id (the seed's
# convention) so each log maps to exactly one event, and a later edit/delete
# can find that event to compensate.
emitWorkReported = (log) ->
  identity = identityFor log.worker
  eventsModel.recordEvent
    id:            log.id
    occurred_at:   log.start_time
    effective_for: monthKeyFromISO log.start_time
    actor:         identity.actor
    actor_user:    identity.user
    action:        'work-reported'
    payload:
      hours:      (log.duration or 0) / 60   # duration is stored in minutes
      started_at: log.start_time
      ended_at:   log.end_time
      project:    log.project_id or null
      task:       log.task_id    or null
      note:       log.description or null


# Retract a reported work log: a `deleted` event targeting the work-reported
# event (which shares the log's id) removes those hours from the fold in
# period.coffee. See bug 08 and docs/event-model.md.
emitWorkReversal = (log) ->
  identity = identityFor log.worker
  eventsModel.recordEvent
    occurred_at:     new Date().toISOString()
    effective_for:   monthKeyFromISO log.start_time
    actor:           identity.actor
    actor_user:      identity.user
    action:          'deleted'
    target_event_id: log.id
    payload:         { reason: 'work log deleted' }


createWorkLog = (data) ->
  params = formatSQLParameters Object.assign {}, data,
    id:         v1()
    project_id: data.project_id ? null
    task_id:    data.task_id    ? null
    billable:   data.billable   ? 1
    submitted:  0
    created_at: new Date().toISOString()

  db.prepare("""
    INSERT INTO work_logs
           ( id,  worker,  start_time,  end_time,  duration,  description,  project_id,  task_id,  billable,  submitted,  created_at)
    VALUES (:id, :worker, :start_time, :end_time, :duration, :description, :project_id, :task_id, :billable, :submitted, :created_at)
  """).run params

  log = db.prepare("SELECT * FROM work_logs WHERE id = ?").get params[':id']
  emitWorkReported log
  return log


getWorkLogs = (filters = {}) ->
  query  = "SELECT * FROM work_logs WHERE 1=1"
  params = []

  if filters.worker
    query += " AND LOWER(worker) = LOWER(?)"
    params.push filters.worker

  if filters.project_id
    query += " AND project_id = ?"
    params.push filters.project_id

  if filters.start_after
    query += " AND start_time >= ?"
    params.push filters.start_after

  if filters.start_before
    query += " AND start_time < ?"
    params.push filters.start_before

  query += " ORDER BY start_time DESC"

  if filters.limit
    query += " LIMIT ?"
    params.push parseInt filters.limit

  logs = db.prepare(query).all params...

  return logs


getWorkLogById = (id) ->
  return db.prepare("SELECT * FROM work_logs WHERE id = ?").get id


updateWorkLog = (id, updates) ->
  existing = db.prepare("SELECT * FROM work_logs WHERE id = ?").get id

  unless existing
    throw new Error "Work log not found: #{id}"

  fields = []
  values = []

  for key, value of updates
    unless key is 'id'
      fields.push "#{key} = ?"
      values.push value

  if fields.length is 0
    return existing

  query = "UPDATE work_logs SET #{fields.join ', '} WHERE id = ?"
  values.push id

  db.prepare(query).run values...

  return db.prepare("SELECT * FROM work_logs WHERE id = ?").get id


# Hard-delete a work log and retract its rent credit. If the row is already
# gone we emit nothing, so a double delete can't retract the hours twice.
deleteWorkLog = (id) ->
  log = db.prepare("SELECT * FROM work_logs WHERE id = ?").get id
  return { changes: 0 } unless log

  result = db.prepare("DELETE FROM work_logs WHERE id = ?").run id
  emitWorkReversal log
  return result

module.exports = {
  createWorkLog
  getWorkLogs
  getWorkLogById
  updateWorkLog
  deleteWorkLog
}
