workLogModel = require '../models/work_log.coffee'
rentService  = require '../services/rent.coffee'
config       = require '../config.coffee'


MIN_DURATION_MINUTES = 1

# One rule for "is this a legitimate work duration", shared by create and
# edit. PUT used to accept 0 or '' — `Number ''` is 0, and `0?` is true, so
# an empty field sailed past the presence check and zeroed the rent credit
# (bug 58), while POST already required at least a minute.
parseDuration = (raw) ->
  n = Number raw
  return n if Number.isFinite(n) and n >= MIN_DURATION_MINUTES
  null


setup = (app) ->
  app.get '/work-logs', (req, res) ->
    { worker, project_id, limit } = req.query

    try
      res.json await workLogModel.getWorkLogs
        worker:     worker
        project_id: project_id
        limit:      limit ? 50
    catch err
      res.status(500).json error: err.message

  app.post '/work-logs', (req, res) ->
    { worker, start_time, end_time, duration, description, billable, project_id, task_id } = req.body

    unless worker and start_time and end_time and description
      return res.status(400).json error: 'Worker, start time, end time, and description required'

    unless duration
      startDate = new Date start_time
      endDate   = new Date end_time
      duration  = Math.round (endDate - startDate) / 1000 / 60

    duration = parseDuration duration
    unless duration?
      return res.status(400).json error: 'Work duration must be a number of minutes, at least 1'

    try
      workLog = await workLogModel.createWorkLog
        worker:      worker
        start_time:  start_time
        end_time:    end_time
        duration:    duration
        description: description.trim()
        project_id:  project_id or null
        task_id:     task_id or null
        billable:    if billable? then (if billable then 1 else 0) else 1
        submitted:   0

      res.json workLog
    catch err
      res.status(500).json error: err.message

  app.put '/work-logs/:id', (req, res) ->
    id = req.params.id
    { worker, start_time, end_time, duration, description, billable } = req.body

    try
      existing = await workLogModel.getWorkLogById id
      unless existing
        return res.status(404).json error: 'Work log not found'

      updates = {}
      if worker?      then updates.worker      = worker
      if start_time?  then updates.start_time  = start_time
      if end_time?    then updates.end_time    = end_time
      if duration?
        parsed = parseDuration duration
        unless parsed?
          return res.status(400).json error: 'Duration must be a number of minutes, at least 1'
        updates.duration = parsed
      if description? then updates.description = description.trim()
      if billable?    then updates.billable    = if billable then 1 else 0

      updated = await workLogModel.updateWorkLog id, updates

      if config.isTenant(existing.worker) or config.isTenant(updated.worker)
        months = new Set()

        for timestamp in [existing.start_time, updated.start_time]
          date = new Date timestamp
          months.add "#{date.getFullYear()}-#{date.getMonth() + 1}"

        for monthKey from months
          [year, month] = monthKey.split('-').map (n) -> parseInt n
          await rentService.createOrUpdateRentPeriod year, month

      res.json updated
    catch err
      res.status(500).json error: err.message

  app.delete '/work-logs/:id', (req, res) ->
    id = req.params.id

    try
      existing = await workLogModel.getWorkLogById id
      unless existing
        return res.status(404).json error: 'Work log not found'

      await workLogModel.deleteWorkLog id

      if config.isTenant existing.worker
        date  = new Date existing.start_time
        year  = date.getFullYear()
        month = date.getMonth() + 1
        await rentService.createOrUpdateRentPeriod year, month

      res.json success: true, deleted: id
    catch err
      res.status(500).json error: err.message

module.exports = { setup }
