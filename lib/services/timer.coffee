{ v4: uuidv4 } = await import('uuid')

db         = (await import('../db/schema.coffee')).db
config     = await import('../config.coffee')
workLogModel = await import('../models/work_log.coffee')


export startTimer = (worker, project_id = null, task_id = null) ->
  # Validate worker
  if worker not in config.WORKERS
    throw new Error "Invalid worker: #{worker}"

  # Check if timer already running
  key = ['timer_state', worker]
  state = await db.get(key)

  if state.value?.status is 'active'
    throw new Error "Timer already running for #{worker}"

  # Start new timer session
  session_id = uuidv4.generate()
  start_time = new Date().toISOString()

  newState =
    worker: worker
    session_id: session_id
    start_time: start_time
    project_id: project_id
    task_id: task_id
    status: 'active'

  await db.set key, newState

  return newState


export stopTimer = (worker, description) ->
  # Validate inputs
  if worker not in config.WORKERS
    throw new Error "Invalid worker: #{worker}"

  if not description?.trim()
    throw new Error "Work description required"

  # Get current timer state
  key = ['timer_state', worker]
  state = await db.get(key)

  if state.value?.status isnt 'active'
    throw new Error "No active timer for #{worker}"

  # Calculate duration
  start_time = new Date(state.value.start_time)
  end_time   = new Date()
  duration   = Math.round((end_time - start_time) / 1000 / 60)  # minutes

  # Validate session duration
  if duration < 1
    throw new Error "Session too short (less than 1 minute)"

  if duration > config.SESSION_TIMEOUT / 1000 / 60
    throw new Error "Session exceeded maximum duration"

  # Create work log entry
  workLog = await workLogModel.createWorkLog
    worker: worker
    start_time: state.value.start_time
    end_time: end_time.toISOString()
    duration: duration
    description: description.trim()
    project_id: state.value.project_id
    task_id: state.value.task_id

  # Reset timer state
  await db.set key,
    worker: worker
    status: 'stopped'
    session_id: null
    start_time: null
    project_id: null
    task_id: null

  return workLog


export getStatus = (worker) ->
  if worker not in config.WORKERS
    throw new Error "Invalid worker: #{worker}"

  key = ['timer_state', worker]
  state = await db.get(key)

  if not state.value
    return
      worker: worker
      status: 'stopped'
      elapsed: 0

  # Calculate elapsed time if active
  if state.value.status is 'active'
    start_time = new Date(state.value.start_time)
    now = new Date()
    elapsed = Math.round((now - start_time) / 1000)  # seconds

    return {
      state.value...
      elapsed: elapsed
      elapsed_formatted: formatDuration(elapsed)
    }
  else
    return {
      state.value...
      elapsed: 0
    }


# Helper to format duration for display
formatDuration = (seconds) ->
  hours   = Math.floor(seconds / 3600)
  minutes = Math.floor((seconds % 3600) / 60)
  secs    = seconds % 60

  parts = []
  parts.push "#{hours}h" if hours > 0
  parts.push "#{minutes}m" if minutes > 0
  parts.push "#{secs}s"

  parts.join(' ')