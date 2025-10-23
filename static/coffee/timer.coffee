currentWorker      = null
currentSession     = null
serverInterval     = null
sessions           = []
sortColumn         = 'stopped'
sortDirection      = 'desc'
descriptionTimeout = null

workerButtons        = document.querySelectorAll '.worker-btn'
currentWorkerSection = document.querySelector '.current-worker'
currentWorkerName    = document.getElementById 'current-worker-name'
activeSection        = document.getElementById 'active-session'
startSection         = document.getElementById 'start-work'
sessionsSection      = document.getElementById 'work-sessions'
startButton          = document.getElementById 'start-timer'
pauseButton          = document.getElementById 'pause-btn'
resumeButton         = document.getElementById 'resume-btn'
doneButton           = document.getElementById 'done-btn'
cancelButton         = document.getElementById 'cancel-btn'
startNewButton       = document.getElementById 'start-new-btn'
activeTimer          = document.getElementById 'active-timer'
sessionStatus        = document.getElementById 'session-status'
activeDescription    = document.getElementById 'active-description'
sessionsTable        = document.getElementById 'sessions-tbody'

workerButtons.forEach (btn) ->
  btn.addEventListener 'click', ->
    currentWorker = btn.dataset.worker

    workerButtons.forEach (b) -> b.classList.remove 'active'
    btn.classList.add 'active'

    currentWorkerName.textContent           = currentWorker.charAt(0).toUpperCase() + currentWorker.slice 1
    currentWorkerSection.style.display      = 'block'

    loadWorkerState()

startButton.addEventListener 'click', ->
  try
    response = await fetch '/timer/start',
      method  : 'POST'
      headers : 'Content-Type': 'application/json'
      body    : JSON.stringify worker: currentWorker

    if response.ok
      loadWorkerState()
    else
      error = await response.json()
      alert error.error
  catch err
    alert "Error starting timer: #{err.message}"

pauseButton.addEventListener 'click', ->
  try
    response = await fetch '/timer/pause',
      method  : 'POST'
      headers : 'Content-Type': 'application/json'
      body    : JSON.stringify worker: currentWorker

    if response.ok
      loadWorkerState()
    else
      error = await response.json()
      alert error.error
  catch err
    alert "Error pausing timer: #{err.message}"


resumeButton.addEventListener 'click', ->
  try
    response = await fetch '/timer/resume',
      method  : 'POST'
      headers : 'Content-Type': 'application/json'
      body    : JSON.stringify
        worker     : currentWorker
        session_id : currentSession?.id

    if response.ok
      loadWorkerState()
    else
      error = await response.json()
      alert error.error
  catch err
    alert "Error resuming timer: #{err.message}"

doneButton.addEventListener 'click', ->
  try
    response = await fetch '/timer/stop',
      method  : 'POST'
      headers : 'Content-Type': 'application/json'
      body    : JSON.stringify
        worker    : currentWorker
        completed : true

    if response.ok
      result = await response.json()
      alert "Work session was less than 1 minute and won't be saved" if result.event is 'completed_too_short'
      currentSession = null
      hideActiveSession()
      loadSessions()
    else
      error = await response.json()
      alert error.error
  catch err
    alert "Error stopping timer: #{err.message}"


cancelButton.addEventListener 'click', ->
  if confirm "Cancel this work session? It will be marked as cancelled."
    try
      response = await fetch '/timer/stop',
        method  : 'POST'
        headers : 'Content-Type': 'application/json'
        body    : JSON.stringify
          worker    : currentWorker
          completed : false

      if response.ok
        currentSession = null
        hideActiveSession()
        loadSessions()
      else
        error = await response.json()
        alert error.error
    catch err
      alert "Error cancelling timer: #{err.message}"

# Start new work (pauses current if any)
startNewButton.addEventListener 'click', ->
  # First pause current work if active
  if currentSession?.status is 'active'
    try
      await fetch '/timer/pause',
        method: 'POST'
        headers: 'Content-Type': 'application/json'
        body: JSON.stringify worker: currentWorker
    catch err
      console.error "Error pausing current work:", err

  # Now start new work
  try
    response = await fetch '/timer/start',
      method: 'POST'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify worker: currentWorker

    if response.ok
      # Reload state from server to get fresh data
      loadWorkerState()
    else
      error = await response.json()
      alert error.error
  catch err
    alert "Error starting new timer: #{err.message}"

activeDescription.addEventListener 'input', ->
  clearTimeout descriptionTimeout if descriptionTimeout

  descriptionTimeout = setTimeout saveDescription, 1000


saveDescription = ->
  return unless currentSession

  try
    response = await fetch '/timer/description',
      method  : 'PUT'
      headers : 'Content-Type': 'application/json'
      body    : JSON.stringify
        worker      : currentWorker
        description : activeDescription.value

    currentSession = await response.json() if response.ok
  catch err
    console.error "Error saving description:", err

loadWorkerState = ->
  return unless currentWorker

  try
    response = await fetch "/timer/status?worker=#{currentWorker}"
    status   = await response.json()

    if status.current_session
      currentSession                = status.current_session
      currentSession.total_duration = status.elapsed or 0
      showActiveSession()
      startUpdateTimer()
    else
      currentSession = null
      hideActiveSession()

    loadSessions()

  catch err
    console.error "Error loading worker state:", err

# Load sessions
loadSessions = ->
  return unless currentWorker

  try
    response = await fetch "/timer/sessions?worker=#{currentWorker}"
    sessions = await response.json()

    displaySessions()
    sessionsSection.style.display = 'block'

  catch err
    console.error "Error loading sessions:", err

# Display sessions
displaySessions = ->
  return unless sessions

  # Sort sessions
  sortedSessions = [...sessions].sort (a, b) ->
    # Current session always on top
    return -1 if currentSession?.id is a.id
    return 1 if currentSession?.id is b.id

    # Then by sort column
    aVal = getSessionSortValue a, sortColumn
    bVal = getSessionSortValue b, sortColumn

    if sortDirection is 'asc'
      if aVal < bVal then -1 else if aVal > bVal then 1 else 0
    else
      if aVal > bVal then -1 else if aVal < bVal then 1 else 0

  # Build table HTML
  if sortedSessions.length is 0
    sessionsTable.innerHTML = '<tr><td colspan="6" style="text-align: center;">No work sessions yet</td></tr>'
    return

  sessionsTable.innerHTML = sortedSessions.map((session) ->
    isCurrent = currentSession?.id is session.id
    rowClass = if isCurrent then 'session-row current' else 'session-row'

    # Format times
    startTime = new Date(session.created_at)
    startStr = formatDateTime(startTime)

    # Stopped time (last event or current time if active)
    stopStr = if session.status in ['completed', 'cancelled']
      formatDateTime(new Date(session.updated_at))
    else if session.status is 'paused'
      "Paused"
    else
      "Running"

    # Duration
    durationStr = session.duration_formatted or formatDuration(session.total_duration)

    # Actions
    actions = []
    if session.status is 'paused' and not isCurrent
      actions.push """<button class="btn btn-primary btn-sm" onclick="resumeSession('#{session.id}')">Resume</button>"""

    """
      <tr class="#{rowClass}">
        <td><span class="status-badge #{session.status}">#{session.status}</span></td>
        <td>#{escapeHtml(session.description or '(no description)')}</td>
        <td>#{startStr}</td>
        <td>#{stopStr}</td>
        <td>#{durationStr}</td>
        <td class="session-actions">#{actions.join ' '}</td>
      </tr>
    """
  ).join ''

getSessionSortValue = (session, column) ->
  switch column
    when 'status'      then session.status
    when 'description' then session.description or ''
    when 'started'     then session.created_at
    when 'stopped'
      if session.status in ['completed', 'cancelled']
        session.updated_at
      else
        '9999-12-31'
    when 'duration' then session.total_duration
    else session.updated_at

# Resume a different session
window.resumeSession = (sessionId) ->
  try
    response = await fetch '/timer/resume',
      method: 'POST'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify
        worker: currentWorker
        session_id: sessionId

    if response.ok
      # Reload state from server to get fresh data
      loadWorkerState()
    else
      error = await response.json()
      alert error.error
  catch err
    alert "Error resuming session: #{err.message}"

# Show active session UI
showActiveSession = ->
  return unless currentSession

  activeSection.style.display = 'block'
  startSection.style.display = 'none'

  # Don't overwrite description if user is typing
  if document.activeElement isnt activeDescription
    activeDescription.value = currentSession.description or ''

  updateActiveSession()

# Hide active session UI
hideActiveSession = ->
  activeSection.style.display = 'none'
  startSection.style.display = 'block'
  stopUpdateTimer()

updateActiveSession = ->
  return unless currentSession

  sessionStatus.textContent = currentSession.status
  sessionStatus.className   = "session-status #{currentSession.status}"

  if currentSession.status is 'active'
    pauseButton .style.display = 'inline-block'
    resumeButton.style.display = 'none'
  else
    pauseButton .style.display = 'none'
    resumeButton.style.display = 'inline-block'

  updateTimerDisplay()


updateTimerDisplay = ->
  return unless currentSession
  activeTimer.textContent = formatDuration currentSession.total_duration or 0


startUpdateTimer = ->
  stopUpdateTimer()
  updateTimerDisplay()
  serverInterval = setInterval loadWorkerState, 5000


stopUpdateTimer = ->
  clearInterval serverInterval if serverInterval
  serverInterval = null

formatDuration = (seconds) ->
  hours   = Math.floor seconds / 3600
  minutes = Math.floor (seconds % 3600) / 60
  secs    = seconds % 60

  "#{hours}:#{String(minutes).padStart(2, '0')}:#{String(secs).padStart(2, '0')}"

formatDateTime = (date) ->
  date.toLocaleString [],
    month  : 'short'
    day    : 'numeric'
    hour   : '2-digit'
    minute : '2-digit'

escapeHtml = (text) ->
  div = document.createElement 'div'
  div.textContent = text
  div.innerHTML

# Sorting
document.querySelectorAll('.sortable').forEach (th) ->
  th.addEventListener 'click', ->
    column = th.dataset.sort

    # Update sort direction
    if column is sortColumn
      sortDirection = if sortDirection is 'asc' then 'desc' else 'asc'
    else
      sortColumn = column
      sortDirection = 'desc'

    # Update UI
    document.querySelectorAll('.sortable').forEach (h) ->
      h.classList.remove 'asc', 'desc'
    th.classList.add sortDirection

    # Re-display
    displaySessions()

window.addEventListener 'load', ->
  lastWorker = localStorage.getItem 'lastWorker'
  if lastWorker
    workerBtn = document.querySelector "[data-worker=\"#{lastWorker}\"]"
    workerBtn?.click()


window.addEventListener 'beforeunload', ->
  localStorage.setItem 'lastWorker', currentWorker if currentWorker