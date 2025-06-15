# static/js/timer.coffee

# Timer state
currentWorker = null
timerInterval = null
timerStartTime = null

# DOM elements
workerButtons = document.querySelectorAll('.worker-btn')
currentWorkerSection = document.querySelector('.current-worker')
currentWorkerName = document.getElementById('current-worker-name')
timerSection = document.querySelector('.timer-section')
workLogsSection = document.querySelector('.work-logs')
timerStatus = document.getElementById('timer-status')
timerElapsed = document.getElementById('timer-elapsed')
startButton = document.getElementById('start-timer')
stopButton = document.getElementById('stop-timer')
stopForm = document.getElementById('stop-form')
workDescription = document.getElementById('work-description')
submitWorkButton = document.getElementById('submit-work')
cancelStopButton = document.getElementById('cancel-stop')
workLogsList = document.getElementById('work-logs-list')

# Worker selection
workerButtons.forEach (btn) ->
  btn.addEventListener 'click', ->
    currentWorker = btn.dataset.worker

    # Update UI
    workerButtons.forEach (b) -> b.classList.remove('active')
    btn.classList.add('active')

    currentWorkerName.textContent = currentWorker.charAt(0).toUpperCase() + currentWorker.slice(1)
    currentWorkerSection.style.display = 'block'
    timerSection.style.display = 'block'
    workLogsSection.style.display = 'block'

    # Check timer status
    checkTimerStatus()

    # Load work logs
    loadWorkLogs()

# Start timer
startButton.addEventListener 'click', ->
  try
    response = await fetch '/timer/start',
      method: 'POST'
      headers: { 'Content-Type': 'application/json' }
      body: JSON.stringify({ worker: currentWorker })

    if not response.ok
      error = await response.json()
      alert(error.error or 'Failed to start timer')
      return

    data = await response.json()
    timerStartTime = new Date(data.start_time)

    # Update UI
    timerStatus.textContent = 'Active'
    startButton.style.display = 'none'
    stopButton.style.display = 'inline-block'

    # Start updating elapsed time
    startTimerDisplay()

  catch err
    alert('Error starting timer: ' + err.message)

# Stop timer button
stopButton.addEventListener 'click', ->
  stopForm.style.display = 'block'
  workDescription.focus()

# Submit work log
submitWorkButton.addEventListener 'click', ->
  description = workDescription.value.trim()

  if not description
    alert('Please describe the work completed')
    return

  try
    response = await fetch '/timer/stop',
      method: 'POST'
      headers: { 'Content-Type': 'application/json' }
      body: JSON.stringify
        worker: currentWorker
        description: description

    if not response.ok
      error = await response.json()
      alert(error.error or 'Failed to stop timer')
      return

    # Reset UI
    stopTimerDisplay()
    workDescription.value = ''
    stopForm.style.display = 'none'

    # Reload work logs
    loadWorkLogs()

  catch err
    alert('Error stopping timer: ' + err.message)

# Cancel stop
cancelStopButton.addEventListener 'click', ->
  stopForm.style.display = 'none'
  workDescription.value = ''

# Check timer status
checkTimerStatus = ->
  return unless currentWorker

  try
    response = await fetch("/timer/status?worker=#{currentWorker}")
    data = await response.json()

    if data.status is 'active'
      timerStartTime = new Date(data.start_time)
      timerStatus.textContent = 'Active'
      startButton.style.display = 'none'
      stopButton.style.display = 'inline-block'
      startTimerDisplay()
    else
      timerStatus.textContent = 'Stopped'
      timerElapsed.textContent = '0:00:00'
      startButton.style.display = 'inline-block'
      stopButton.style.display = 'none'
  catch err
    console.error 'Error checking timer status:', err

# Timer display update
startTimerDisplay = ->
  # Clear any existing interval
  clearInterval(timerInterval) if timerInterval

  # Update immediately
  updateTimerDisplay()

  # Then update every second
  timerInterval = setInterval(updateTimerDisplay, 1000)

stopTimerDisplay = ->
  if timerInterval
    clearInterval(timerInterval)
    timerInterval = null

  timerStatus.textContent = 'Stopped'
  timerElapsed.textContent = '0:00:00'
  startButton.style.display = 'inline-block'
  stopButton.style.display = 'none'

updateTimerDisplay = ->
  return unless timerStartTime

  now = new Date()
  elapsed = Math.floor((now - timerStartTime) / 1000)

  hours = Math.floor(elapsed / 3600)
  minutes = Math.floor((elapsed % 3600) / 60)
  seconds = elapsed % 60

  timerElapsed.textContent = "#{hours}:#{String(minutes).padStart(2, '0')}:#{String(seconds).padStart(2, '0')}"

# Load work logs
loadWorkLogs = ->
  return unless currentWorker

  try
    response = await fetch("/work-logs?worker=#{currentWorker}&limit=10")
    logs = await response.json()

    if logs.length is 0
      workLogsList.innerHTML = '<p>No work logs yet.</p>'
      return

    workLogsList.innerHTML = logs.map((log) ->
      startTime = new Date(log.start_time)
      date = startTime.toLocaleDateString()
      time = startTime.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })

      """
        <div class="work-log-item">
          <div class="work-log-header">
            <span class="work-log-worker">#{log.worker}</span>
            <span class="work-log-time">#{date} at #{time}</span>
          </div>
          <div>
            <span class="work-log-duration">#{log.duration} min</span>
          </div>
          <div class="work-log-description">#{escapeHtml(log.description)}</div>
        </div>
      """
    ).join('')

  catch err
    console.error 'Error loading work logs:', err
    workLogsList.innerHTML = '<p>Error loading work logs.</p>'

# Helper to escape HTML
escapeHtml = (text) ->
  div = document.createElement('div')
  div.textContent = text
  div.innerHTML

# Check for active timer on page load
window.addEventListener 'load', ->
  # Auto-select worker if returning to page
  lastWorker = localStorage.getItem('lastWorker')
  if lastWorker
    workerBtn = document.querySelector("[data-worker=\"#{lastWorker}\"]")
    workerBtn?.click()

# Save selected worker
window.addEventListener 'beforeunload', ->
  if currentWorker
    localStorage.setItem('lastWorker', currentWorker)