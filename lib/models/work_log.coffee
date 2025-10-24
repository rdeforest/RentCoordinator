{ v1 }                   = require 'uuid'
{ db }                   = require '../db/schema.coffee'
{ formatSQLParameters }  = require '../db/utils.coffee'


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

  return db.prepare("SELECT * FROM work_logs WHERE id = ?").get params[':id']


getWorkLogs = (filters = {}) ->
  query  = "SELECT * FROM work_logs WHERE 1=1"
  params = []

  if filters.worker
    query += " AND worker = ?"
    params.push filters.worker

  if filters.project_id
    query += " AND project_id = ?"
    params.push filters.project_id

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

module.exports = {
  createWorkLog
  getWorkLogs
  getWorkLogById
  updateWorkLog
}
