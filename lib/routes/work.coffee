# lib/routes/work.coffee

workLogModel = await import('../models/work_log.coffee')
rentService  = await import('../services/rent.coffee')


export setup = (app) ->

  # Create manual work entry
  app.post '/work-logs', (req, res) ->
    { worker, start_time, end_time, duration, description, billable, project_id, task_id } = req.body

    # Validate required fields
    if not worker or not start_time or not end_time or not description
      return res.status(400).json error: 'Worker, start time, end time, and description required'

    # Calculate duration if not provided
    if not duration
      startDate = new Date(start_time)
      endDate = new Date(end_time)
      duration = Math.round((endDate - startDate) / 1000 / 60)  # minutes

    # Validate duration
    if duration < 1
      return res.status(400).json error: 'Work duration must be at least 1 minute'

    try
      workLog = await workLogModel.createWorkLog
        worker: worker
        start_time: start_time
        end_time: end_time
        duration: duration
        description: description.trim()
        project_id: project_id or null
        task_id: task_id or null
        billable: billable ? true
        submitted: false

      res.json workLog
    catch err
      res.status(500).json error: err.message


  # Update work log
  app.put '/work-logs/:id', (req, res) ->
    id = req.params.id
    { worker, start_time, end_time, duration, description, billable } = req.body

    try
      # Get existing log
      existing = await workLogModel.getWorkLogById(id)
      if not existing
        return res.status(404).json error: 'Work log not found'

      # Build updates
      updates = {}
      if worker? then updates.worker = worker
      if start_time? then updates.start_time = start_time
      if end_time? then updates.end_time = end_time
      if duration? then updates.duration = duration
      if description? then updates.description = description.trim()
      if billable? then updates.billable = billable

      # Update the log
      updated = await workLogModel.updateWorkLog(id, updates)

      # If this affects Lyndzie's hours, we might need to recalculate rent
      if existing.worker is 'lyndzie' or updated.worker is 'lyndzie'
        # Get the month(s) affected
        months = new Set()

        for timestamp in [existing.start_time, updated.start_time]
          date = new Date(timestamp)
          months.add "#{date.getFullYear()}-#{date.getMonth() + 1}"

        # Recalculate those months
        for monthKey from months
          [year, month] = monthKey.split('-').map (n) -> parseInt(n)
          await rentService.createOrUpdateRentPeriod(year, month)

      res.json updated
    catch err
      res.status(500).json error: err.message


  # Delete work log
  app.delete '/work-logs/:id', (req, res) ->
    id = req.params.id

    try
      # Get existing log before deletion
      existing = await workLogModel.getWorkLogById(id)
      if not existing
        return res.status(404).json error: 'Work log not found'

      # Delete the log
      await workLogModel.deleteWorkLog(id)

      # If this was Lyndzie's work, recalculate rent for that month
      if existing.worker is 'lyndzie'
        date = new Date(existing.start_time)
        year = date.getFullYear()
        month = date.getMonth() + 1
        await rentService.createOrUpdateRentPeriod(year, month)

      res.json { success: true, deleted: id }
    catch err
      res.status(500).json error: err.message