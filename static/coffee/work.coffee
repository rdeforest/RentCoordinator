allWorkLogs  = []
filteredLogs = []


window.addEventListener 'load', ->
  loadWorkLogs()
  document.getElementById('work-date').value = new Date().toISOString().split('T')[0]


loadWorkLogs = ->
  try
    response    = await fetch '/work-logs?limit=1000'
    allWorkLogs = await response.json()
    applyFilters()
  catch err
    console.error 'Error loading work logs:', err
    document.getElementById('work-table-body').innerHTML =
      '<tr><td colspan="5" style="text-align: center;">Error loading work logs</td></tr>'


applyFilters = ->
  workerFilter = document.getElementById('worker-filter').value
  monthFilter  = document.getElementById('month-filter').value

  filteredLogs = allWorkLogs.filter (log) ->
    return false if workerFilter and log.worker isnt workerFilter

    if monthFilter
      logDate  = new Date log.start_time
      logMonth = "#{logDate.getFullYear()}-#{String(logDate.getMonth() + 1).padStart(2, '0')}"
      return false if logMonth isnt monthFilter

    true

  updateDisplay()
  updateStats()

updateDisplay = ->
  tbody = document.getElementById 'work-table-body'

  if filteredLogs.length is 0
    tbody.innerHTML = '<tr><td colspan="5" style="text-align: center;">No work entries found</td></tr>'
    return

  tbody.innerHTML = filteredLogs.map((log) ->
    startTime = new Date log.start_time
    date      = startTime.toLocaleDateString()
    time      = startTime.toLocaleTimeString [], hour: '2-digit', minute: '2-digit'
    hours     = (log.duration / 60).toFixed 2

    """
      <tr>
        <td>#{date} #{time}</td>
        <td>#{log.worker}</td>
        <td>#{hours} hours</td>
        <td>#{escapeHtml log.description}</td>
        <td class="actions">
          <button class="btn btn-secondary" onclick="editWork('#{log.id}')">Edit</button>
          <button class="btn btn-danger" onclick="deleteWork('#{log.id}')">Delete</button>
        </td>
      </tr>
    """
  ).join ''


updateStats = ->
  totalEntries = filteredLogs.length
  totalMinutes = filteredLogs.reduce ((sum, log) -> sum + log.duration), 0
  totalHours   = totalMinutes / 60
  totalCredit  = filteredLogs
    .filter (log) -> log.billable and log.worker is 'lyndzie'
    .reduce ((sum, log) -> sum + (log.duration / 60 * 50)), 0

  document.getElementById('total-entries').textContent = totalEntries
  document.getElementById('total-hours') .textContent = totalHours.toFixed 2
  document.getElementById('total-credit').textContent = formatCurrency totalCredit

document.getElementById('worker-filter').addEventListener 'change', applyFilters
document.getElementById('month-filter') .addEventListener 'change', applyFilters
document.getElementById('clear-filters').addEventListener 'click', ->
  document.getElementById('worker-filter').value = ''
  document.getElementById('month-filter') .value = ''
  applyFilters()


workModal     = document.getElementById 'work-modal'
deleteModal   = document.getElementById 'delete-modal'
addWorkBtn    = document.getElementById 'add-work-btn'
cancelWorkBtn = document.getElementById 'cancel-work'
workForm      = document.getElementById 'work-form'


addWorkBtn.addEventListener 'click', ->
  document.getElementById('modal-title')    .textContent = 'Add Work Entry'
  document.getElementById('work-form')      .reset()
  document.getElementById('work-id')        .value = ''
  document.getElementById('work-date')      .value = new Date().toISOString().split('T')[0]
  document.getElementById('work-billable')  .checked = true
  workModal.style.display = 'block'


cancelWorkBtn.addEventListener 'click', ->
  workModal.style.display = 'none'

window.editWork = (id) ->
  log = allWorkLogs.find (l) -> l.id is id
  return unless log

  document.getElementById('modal-title')  .textContent = 'Edit Work Entry'
  document.getElementById('work-id')      .value = log.id
  document.getElementById('work-worker')  .value = log.worker

  startDate = new Date log.start_time
  document.getElementById('work-date')      .value = startDate.toISOString().split('T')[0]
  document.getElementById('work-start-time').value = startDate.toTimeString().slice 0, 5

  endDate = new Date log.end_time
  document.getElementById('work-end-time').value = endDate.toTimeString().slice 0, 5

  document.getElementById('work-description').value   = log.description
  document.getElementById('work-billable')   .checked = log.billable isnt false

  workModal.style.display = 'block'


window.deleteWork = (id) ->
  document.getElementById('delete-work-id').value = id
  deleteModal.style.display = 'block'

workForm.addEventListener 'submit', (e) ->
  e.preventDefault()

  id          = document.getElementById('work-id')         .value
  worker      = document.getElementById('work-worker')     .value
  date        = document.getElementById('work-date')       .value
  startTime   = document.getElementById('work-start-time').value
  endTime     = document.getElementById('work-end-time')  .value
  description = document.getElementById('work-description').value
  billable    = document.getElementById('work-billable')  .checked

  startDateTime = new Date "#{date}T#{startTime}"
  endDateTime   = new Date "#{date}T#{endTime}"

  endDateTime.setDate endDateTime.getDate() + 1 if endDateTime < startDateTime

  duration = Math.round (endDateTime - startDateTime) / 1000 / 60

  data =
    worker     : worker
    start_time : startDateTime.toISOString()
    end_time   : endDateTime.toISOString()
    duration   : duration
    description: description.trim()
    billable   : billable

  try
    if id
      response = await fetch "/work-logs/#{id}",
        method  : 'PUT'
        headers : 'Content-Type': 'application/json'
        body    : JSON.stringify data
    else
      response = await fetch '/work-logs',
        method  : 'POST'
        headers : 'Content-Type': 'application/json'
        body    : JSON.stringify data

    if response.ok
      workModal.style.display = 'none'
      loadWorkLogs()
    else
      error = await response.json()
      alert "Error saving work entry: #{error.error}"
  catch err
    alert "Error saving work entry: #{err.message}"

document.getElementById('confirm-delete').addEventListener 'click', ->
  id = document.getElementById('delete-work-id').value

  try
    response = await fetch "/work-logs/#{id}",
      method: 'DELETE'

    if response.ok
      deleteModal.style.display = 'none'
      loadWorkLogs()
    else
      error = await response.json()
      alert "Error deleting work entry: #{error.error}"
  catch err
    alert "Error deleting work entry: #{err.message}"

document.getElementById('cancel-delete').addEventListener 'click', ->
  deleteModal.style.display = 'none'


escapeHtml = (text) ->
  div = document.createElement 'div'
  div.textContent = text
  div.innerHTML

formatCurrency = (amount) ->
  new Intl.NumberFormat 'en-US',
    style    : 'currency'
    currency : 'USD'
  .format amount