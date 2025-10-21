# static/coffee/rent.coffee

# State
now = new Date()
currentYear = now.getFullYear()
currentMonth = now.getMonth() + 1
currentFilters = {}
allEvents = []
eventToDelete = null
showingDeleted = false

# DOM elements
eventModal = document.getElementById 'event-modal'
eventForm = document.getElementById 'event-form'
addEventBtn = document.getElementById 'add-event-btn'
cancelEventBtn = document.getElementById 'cancel-event'
eventSubmitBtn = document.getElementById 'event-submit'
eventModalTitle = document.getElementById 'event-modal-title'

confirmDeleteModal = document.getElementById 'confirm-delete-modal'
confirmDeleteBtn = document.getElementById 'confirm-delete-btn'
cancelDeleteBtn = document.getElementById 'cancel-delete-btn'
deleteEventDetails = document.getElementById 'delete-event-details'

toggleFiltersBtn = document.getElementById 'toggle-filters-btn'
toggleDeletedBtn = document.getElementById 'toggle-deleted-btn'
eventFilters = document.getElementById 'event-filters'
applyFiltersBtn = document.getElementById 'apply-filters-btn'
clearFiltersBtn = document.getElementById 'clear-filters-btn'

eventsTable = document.getElementById 'events-tbody'

paymentModal = document.getElementById 'payment-modal'
recordPaymentBtn = document.getElementById 'record-payment-btn'
cancelPaymentBtn = document.getElementById 'cancel-payment'
paymentForm = document.getElementById 'payment-form'

# Load data on page load
window.addEventListener 'load', ->
  loadRentSummary()
  loadCurrentMonth()
  loadAllPeriods()
  loadEvents()
  populateFilterYears()

# Load rent summary
loadRentSummary = ->
  try
    response = await fetch '/rent/summary'
    summary = await response.json()

    document.getElementById('outstanding-balance').textContent =
      formatCurrency summary.outstanding_balance
    document.getElementById('total-credits').textContent =
      formatCurrency summary.total_discount_applied
    document.getElementById('total-paid').textContent =
      formatCurrency summary.total_amount_paid
    document.getElementById('months-tracked').textContent =
      summary.total_periods

  catch err
    console.error 'Error loading rent summary:', err
    showError 'Failed to load rent summary'

# Load current month details
loadCurrentMonth = ->
  try
    response = await fetch "/rent/period/#{currentYear}/#{currentMonth}"
    period = await response.json()

    document.getElementById('current-month-title').textContent =
      formatMonthYear currentYear, currentMonth

    document.getElementById('hours-worked').textContent =
      period.hours_worked.toFixed 2
    document.getElementById('hours-previous').textContent =
      (period.hours_from_previous or 0).toFixed 2
    document.getElementById('hours-applied').textContent =
      Math.min(period.hours_worked + (period.hours_from_previous or 0), 8).toFixed 2
    document.getElementById('credit-applied').textContent =
      formatCurrency period.discount_applied
    document.getElementById('amount-due').textContent =
      formatCurrency period.amount_due
    document.getElementById('amount-paid').textContent =
      formatCurrency period.amount_paid or 0
    outstanding = period.amount_due - (period.amount_paid or 0)
    document.getElementById('outstanding-balance-current').textContent =
      formatCurrency outstanding

    # Show "Pay Rent Online" button if there's an outstanding balance
    payOnlineBtn = document.getElementById('pay-rent-online-btn')
    if outstanding > 0
      payOnlineBtn.style.display = 'inline-block'
      payOnlineBtn.onclick = ->
        window.location.href = "/payment?year=#{currentYear}&month=#{currentMonth}"
    else
      payOnlineBtn.style.display = 'none'

    document.querySelector('.current-month').style.display = 'block'

  catch err
    console.error 'Error loading current month:', err
    showError 'Failed to load current month data'

# Load all periods
loadAllPeriods = ->
  try
    response = await fetch '/rent/periods'
    periods = await response.json()

    tbody = document.getElementById 'periods-table'

    if periods.length is 0
      tbody.innerHTML = '<tr><td colspan="6" style="text-align: center;">No rent periods found</td></tr>'
      return

    tbody.innerHTML = periods.map((period) ->
      status = getPaymentStatus period
      statusClass = status.toLowerCase()

      """
        <tr>
          <td>#{formatMonthYear period.year, period.month}</td>
          <td>#{period.hours_worked.toFixed 2}</td>
          <td>#{formatCurrency period.discount_applied}</td>
          <td>#{formatCurrency period.amount_due}</td>
          <td>#{formatCurrency period.amount_paid or 0}</td>
          <td class="#{statusClass}">#{status}</td>
        </tr>
      """
    ).join ''

  catch err
    console.error 'Error loading periods:', err
    showError 'Failed to load rent periods'

# Load rent events
loadEvents = (filters = {}) ->
  try
    queryParams = new URLSearchParams()

    if filters.year
      queryParams.append 'year', filters.year
    if filters.month
      queryParams.append 'month', filters.month
    if showingDeleted
      queryParams.append 'includeDeleted', 'true'

    url = '/rent/events'
    if queryParams.toString()
      url += '?' + queryParams.toString()

    response = await fetch url
    events = await response.json()

    # Filter out malformed events first
    events = events.filter (event) ->
      event.type? and event.date? and event.year? and event.month? and
      event.amount? and event.description? and event.id?

    # Apply client-side filters
    if filters.type
      events = events.filter (event) -> event.type is filters.type

    allEvents = events
    renderEventsTable events

  catch err
    console.error 'Error loading events:', err
    showError 'Failed to load rent events'

# Render events table
renderEventsTable = (events) ->
  tbody = eventsTable

  if events.length is 0
    tbody.innerHTML = '<tr><td colspan="6" style="text-align: center;">No events found</td></tr>'
    return

  # Filter out malformed events and render valid ones
  validEvents = events.filter (event) ->
    # Check that all required fields are present
    event.type? and event.date? and event.year? and event.month? and
    event.amount? and event.description? and event.id?

  if validEvents.length is 0
    tbody.innerHTML = '<tr><td colspan="6" style="text-align: center;">No valid events found</td></tr>'
    return

  tbody.innerHTML = validEvents.map((event) ->
    dateStr = formatDate event.date
    periodStr = formatMonthYear event.year, event.month
    amountStr = formatCurrency event.amount
    typeClass = event.type.replace('_', '-')
    isDeleted = event.deleted

    rowClass = if isDeleted then 'deleted-row' else ''
    actions = if isDeleted
      """
        <button class="btn btn-small btn-success" onclick="undeleteEvent('#{event.id}')">Undelete</button>
        <button class="btn btn-small" onclick="viewAuditLog('#{event.id}')">Audit Log</button>
      """
    else
      """
        <button class="btn btn-small" onclick="editEvent('#{event.id}')">Edit</button>
        <button class="btn btn-small btn-danger" onclick="deleteEvent('#{event.id}')">Delete</button>
      """

    """
      <tr class="#{rowClass}">
        <td>#{dateStr}</td>
        <td class="event-type #{typeClass}">#{formatEventType event.type}#{if isDeleted then ' (DELETED)' else ''}</td>
        <td>#{periodStr}</td>
        <td class="#{if event.amount >= 0 then 'positive' else 'negative'}">#{amountStr}</td>
        <td>#{escapeHtml event.description}</td>
        <td class="actions">#{actions}</td>
      </tr>
    """
  ).join ''

# Populate filter years from available data
populateFilterYears = ->
  currentYear = new Date().getFullYear()
  years = [currentYear - 2, currentYear - 1, currentYear, currentYear + 1]
  
  yearSelect = document.getElementById 'filter-year'
  yearSelect.innerHTML = '<option value="">All Years</option>' +
    years.map((year) -> "<option value=\"#{year}\">#{year}</option>").join('')

# Event Management Functions
window.editEvent = (eventId) ->
  event = allEvents.find (e) -> e.id is eventId
  
  if not event
    showError 'Event not found'
    return

  # Populate form
  document.getElementById('event-id').value = event.id
  document.getElementById('event-type').value = event.type
  document.getElementById('event-date').value = event.date.split('T')[0]
  document.getElementById('event-year').value = event.year
  document.getElementById('event-month').value = event.month
  document.getElementById('event-amount').value = event.amount
  document.getElementById('event-description').value = event.description
  document.getElementById('event-notes').value = event.notes or ''

  # Update modal
  eventModalTitle.textContent = 'Edit Rent Event'
  eventSubmitBtn.textContent = 'Update Event'
  eventModal.style.display = 'block'

window.deleteEvent = (eventId) ->
  event = allEvents.find (e) -> e.id is eventId

  if not event
    showError 'Event not found'
    return

  eventToDelete = event

  # Show event details in delete modal
  deleteEventDetails.innerHTML = """
    <p><strong>Date:</strong> #{formatDate event.date}</p>
    <p><strong>Type:</strong> #{formatEventType event.type}</p>
    <p><strong>Period:</strong> #{formatMonthYear event.year, event.month}</p>
    <p><strong>Amount:</strong> #{formatCurrency event.amount}</p>
    <p><strong>Description:</strong> #{escapeHtml event.description}</p>
  """

  confirmDeleteModal.style.display = 'block'

window.undeleteEvent = (eventId) ->
  try
    response = await fetch "/rent/events/#{eventId}/undelete",
      method: 'POST'

    if response.ok
      autoRecalculateAndReload()
    else
      error = await response.json()
      showError "Failed to undelete event: #{error.error}"

  catch err
    showError "Error undeleting event: #{err.message}"

window.viewAuditLog = (eventId) ->
  try
    response = await fetch "/rent/audit-logs?entity_type=rent_event&entity_id=#{eventId}"
    logs = await response.json()

    if logs.length is 0
      alert 'No audit log entries found for this event'
      return

    # Format audit log for display
    logContent = logs.map((log) ->
      """
      Action: #{log.action}
      User: #{log.user}
      Time: #{formatDate log.timestamp}
      ---
      """
    ).join '\n'

    alert "Audit Log for Event:\n\n#{logContent}"

  catch err
    showError "Error loading audit log: #{err.message}"

# Event Listeners

# Add/Edit Event Modal
addEventBtn.addEventListener 'click', ->
  # Clear form
  eventForm.reset()
  document.getElementById('event-id').value = ''
  
  # Set defaults
  document.getElementById('event-date').value = new Date().toISOString().split('T')[0]
  document.getElementById('event-year').value = currentYear
  document.getElementById('event-month').value = currentMonth

  # Update modal
  eventModalTitle.textContent = 'Add Rent Event'
  eventSubmitBtn.textContent = 'Add Event'
  eventModal.style.display = 'block'

cancelEventBtn.addEventListener 'click', ->
  eventModal.style.display = 'none'

# Event Form Submit
eventForm.addEventListener 'submit', (e) ->
  e.preventDefault()
  
  eventId = document.getElementById('event-id').value
  isEdit = eventId isnt ''

  data =
    type: document.getElementById('event-type').value
    date: document.getElementById('event-date').value
    year: parseInt document.getElementById('event-year').value
    month: parseInt document.getElementById('event-month').value
    amount: parseFloat document.getElementById('event-amount').value
    description: document.getElementById('event-description').value
    notes: document.getElementById('event-notes').value

  try
    if isEdit
      # Update existing event
      response = await fetch "/rent/events/#{eventId}",
        method: 'PUT'
        headers: 'Content-Type': 'application/json'
        body: JSON.stringify data
    else
      # Create new event
      response = await fetch '/rent/events',
        method: 'POST'
        headers: 'Content-Type': 'application/json'
        body: JSON.stringify data

    if response.ok
      eventModal.style.display = 'none'
      autoRecalculateAndReload()
    else
      error = await response.json()
      showError "Failed to #{if isEdit then 'update' else 'add'} event: #{error.error}"

  catch err
    showError "Error #{if isEdit then 'updating' else 'adding'} event: #{err.message}"

# Delete Confirmation
confirmDeleteBtn.addEventListener 'click', ->
  if not eventToDelete
    return

  try
    response = await fetch "/rent/events/#{eventToDelete.id}",
      method: 'DELETE'

    if response.ok
      confirmDeleteModal.style.display = 'none'
      eventToDelete = null
      autoRecalculateAndReload()
    else
      error = await response.json()
      showError "Failed to delete event: #{error.error}"

  catch err
    showError "Error deleting event: #{err.message}"

cancelDeleteBtn.addEventListener 'click', ->
  confirmDeleteModal.style.display = 'none'
  eventToDelete = null

# Filter Handling
toggleFiltersBtn.addEventListener 'click', ->
  isVisible = eventFilters.style.display isnt 'none'
  eventFilters.style.display = if isVisible then 'none' else 'block'
  toggleFiltersBtn.textContent = if isVisible then 'Filters' else 'Hide Filters'

# Toggle deleted events
toggleDeletedBtn.addEventListener 'click', ->
  showingDeleted = not showingDeleted
  toggleDeletedBtn.textContent = if showingDeleted then 'Hide Deleted' else 'Show Deleted'
  toggleDeletedBtn.className = if showingDeleted then 'btn btn-warning' else 'btn btn-secondary'
  loadEvents currentFilters

applyFiltersBtn.addEventListener 'click', ->
  filters = {}
  
  type = document.getElementById('filter-type').value
  year = document.getElementById('filter-year').value
  month = document.getElementById('filter-month').value

  if type then filters.type = type
  if year then filters.year = year
  if month then filters.month = month

  currentFilters = filters
  loadEvents filters

clearFiltersBtn.addEventListener 'click', ->
  document.getElementById('filter-type').value = ''
  document.getElementById('filter-year').value = ''
  document.getElementById('filter-month').value = ''
  
  currentFilters = {}
  loadEvents {}

# Legacy Payment Modal (keeping for compatibility)
recordPaymentBtn.addEventListener 'click', ->
  document.getElementById('payment-year').value = currentYear
  document.getElementById('payment-month').value = currentMonth
  document.getElementById('payment-amount').value = ''
  document.getElementById('payment-date').value = new Date().toISOString().split('T')[0]
  document.getElementById('payment-notes').value = ''
  paymentModal.style.display = 'block'

cancelPaymentBtn.addEventListener 'click', ->
  paymentModal.style.display = 'none'

paymentForm.addEventListener 'submit', (e) ->
  e.preventDefault()

  data =
    year: parseInt document.getElementById('payment-year').value
    month: parseInt document.getElementById('payment-month').value
    amount: parseFloat document.getElementById('payment-amount').value
    payment_date: document.getElementById('payment-date').value
    payment_method: document.getElementById('payment-method').value
    notes: document.getElementById('payment-notes').value

  try
    response = await fetch '/rent/payment',
      method: 'POST'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify data

    if response.ok
      paymentModal.style.display = 'none'
      autoRecalculateAndReload()
    else
      error = await response.json()
      showError "Failed to record payment: #{error.error}"

  catch err
    showError "Error recording payment: #{err.message}"

# Recalculate all periods
document.getElementById('recalculate-btn').addEventListener 'click', ->
  autoRecalculateAndReload()

# Helper functions
formatCurrency = (amount) ->
  new Intl.NumberFormat('en-US',
    style: 'currency'
    currency: 'USD'
  ).format amount

# Auto-recalculate and reload all data
autoRecalculateAndReload = ->
  try
    response = await fetch '/rent/recalculate-all', method: 'POST'
    if response.ok
      loadRentSummary()
      loadCurrentMonth()
      loadAllPeriods()
      loadEvents currentFilters
  catch err
    console.error 'Auto-recalculation failed:', err

formatDate = (dateStr) ->
  date = new Date dateStr
  date.toLocaleDateString 'en-US',
    year: 'numeric'
    month: 'short'
    day: 'numeric'

formatMonthYear = (year, month) ->
  date = new Date year, month - 1
  date.toLocaleDateString 'en-US',
    year: 'numeric'
    month: 'long'

formatEventType = (type) ->
  switch type
    when 'payment' then 'Payment'
    when 'adjustment' then 'Rent Adjustment'
    when 'work_value_change' then 'Work Value Change'
    when 'manual' then 'Manual Entry'
    else type

escapeHtml = (text) ->
  div = document.createElement 'div'
  div.textContent = text
  return div.innerHTML

getPaymentStatus = (period) ->
  due = period.amount_due
  paid = period.amount_paid or 0

  if paid >= due then 'PAID'
  else if paid > 0 then 'PARTIAL'
  else 'UNPAID'

showSuccess = (message) ->
  # Simple alert for now - could be enhanced with toast notifications
  alert message

showError = (message) ->
  # Simple alert for now - could be enhanced with toast notifications  
  alert message