# static/coffee/rent.coffee

# Current date
now = new Date()
currentYear = now.getFullYear()
currentMonth = now.getMonth() + 1

# Load rent summary and current month on page load
window.addEventListener 'load', ->
  loadRentSummary()
  loadCurrentMonth()
  loadAllPeriods()

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

    document.querySelector('.current-month').style.display = 'block'

  catch err
    console.error 'Error loading current month:', err

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

# Recalculate all periods
document.getElementById('recalculate-btn').addEventListener 'click', ->
  unless confirm 'This will recalculate all rent periods including retroactive adjustments. Continue?'
    return

  try
    response = await fetch '/rent/recalculate-all', method: 'POST'
    result = await response.json()

    if response.ok
      alert "Successfully recalculated #{result.periods_updated} periods"
      # Reload all data
      loadRentSummary()
      loadCurrentMonth()
      loadAllPeriods()
    else
      alert "Error recalculating: #{result.error}"

  catch err
    alert "Error recalculating periods: #{err.message}"

# Payment modal handling
paymentModal = document.getElementById 'payment-modal'
recordPaymentBtn = document.getElementById 'record-payment-btn'
cancelPaymentBtn = document.getElementById 'cancel-payment'
paymentForm = document.getElementById 'payment-form'

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
      # Reload data
      loadRentSummary()
      loadCurrentMonth()
      loadAllPeriods()
    else
      error = await response.json()
      alert "Error recording payment: #{error.error}"

  catch err
    alert "Error recording payment: #{err.message}"

# Helper functions
formatCurrency = (amount) ->
  new Intl.NumberFormat('en-US',
    style: 'currency'
    currency: 'USD'
  ).format amount

formatMonthYear = (year, month) ->
  date = new Date year, month - 1
  date.toLocaleDateString 'en-US',
    year: 'numeric'
    month: 'long'

getPaymentStatus = (period) ->
  due = period.amount_due
  paid = period.amount_paid or 0

  if paid >= due then 'PAID'
  else if paid > 0 then 'PARTIAL'
  else 'UNPAID'