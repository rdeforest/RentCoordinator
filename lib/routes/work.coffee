workLogModel     = require '../models/work_log.coffee'
workSessionModel = require '../models/work_session.coffee'
rentService      = require '../services/rent.coffee'
config           = require '../config.coffee'


setup = (app) ->
  app.get '/work-logs', (req, res) ->
    { worker, project_id, limit } = req.query

    try
      if worker
        sessions = await workSessionModel.getAllSessions worker
      else
        allSessions = []
        for w in config.WORKERS
          workerSessions  = await workSessionModel.getAllSessions w
          allSessions     = allSessions.concat workerSessions
        sessions = allSessions

      logs = []
      for session in sessions
        if session.status in ['completed', 'cancelled']
          log = await workSessionModel.sessionToWorkLog session
          logs.push log

      traditionalLogs = await workLogModel.getWorkLogs { worker, limit: 1000 }

      allLogs    = logs.concat traditionalLogs
      uniqueLogs = []
      seen       = new Set()

      for log in allLogs
        unless seen.has log.id
          seen.add log.id
          uniqueLogs.push log

      uniqueLogs.sort (a, b) -> new Date(b.start_time) - new Date(a.start_time)

      if limit
        uniqueLogs = uniqueLogs.slice 0, parseInt limit

      res.json uniqueLogs
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

    if duration < 1
      return res.status(400).json error: 'Work duration must be at least 1 minute'

    try
      workLog = await workLogModel.createWorkLog
        worker:      worker
        start_time:  start_time
        end_time:    end_time
        duration:    duration
        description: description.trim()
        project_id:  project_id or null
        task_id:     task_id or null
        billable:    billable ? true
        submitted:   false

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
      if duration?    then updates.duration    = duration
      if description? then updates.description = description.trim()
      if billable?    then updates.billable    = billable

      updated = await workLogModel.updateWorkLog id, updates

      if existing.worker is 'lyndzie' or updated.worker is 'lyndzie'
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

      if existing.worker is 'lyndzie'
        date  = new Date existing.start_time
        year  = date.getFullYear()
        month = date.getMonth() + 1
        await rentService.createOrUpdateRentPeriod year, month

      res.json success: true, deleted: id
    catch err
      res.status(500).json error: err.message

module.exports = { setup }
