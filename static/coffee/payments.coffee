# Payment Management
#
# Provides interface to view all payments and reassign them to different rent periods

payments        = []
selectedPayment = null

MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
]


# Load all payments from API
loadPayments = ->
  try
    showLoading true

    response = await fetch '/v1/api/payments'

    unless response.ok
      throw new Error "Failed to load payments: #{response.statusText}"

    payments = await response.json()

    renderPayments()
    showLoading false

  catch err
    showError err.message


# Render payments table
renderPayments = ->
  tbody       = document.getElementById 'payments-tbody'
  container   = document.getElementById 'payments-container'
  totalAmount = 0

  tbody.innerHTML = ''

  if payments.length is 0
    tbody.innerHTML = '<tr><td colspan="6" class="no-data">No payments recorded</td></tr>'
  else
    for payment in payments
      totalAmount += payment.amount

      row = document.createElement 'tr'

      # Payment date
      paymentDate = new Date payment.payment_date
      dateCell    = document.createElement 'td'
      dateCell.textContent = paymentDate.toLocaleDateString()
      row.appendChild dateCell

      # Amount
      amountCell = document.createElement 'td'
      amountCell.textContent = "$#{payment.amount.toFixed(2)}"
      amountCell.classList.add 'amount'
      row.appendChild amountCell

      # Applied to period
      periodCell = document.createElement 'td'
      periodCell.textContent = "#{MONTH_NAMES[payment.month - 1]} #{payment.year}"
      row.appendChild periodCell

      # Payment method
      methodCell = document.createElement 'td'
      methodCell.textContent = payment.payment_method
      row.appendChild methodCell

      # Notes
      notesCell = document.createElement 'td'
      notesCell.textContent = payment.notes or ''
      notesCell.classList.add 'notes'
      row.appendChild notesCell

      # Actions
      actionsCell = document.createElement 'td'
      actionsCell.classList.add 'actions'

      editBtn = document.createElement 'button'
      editBtn.textContent = 'Reassign'
      editBtn.classList.add 'btn', 'btn-small'
      editBtn.addEventListener 'click', -> showEditModal payment
      actionsCell.appendChild editBtn

      deleteBtn = document.createElement 'button'
      deleteBtn.textContent = 'Delete'
      deleteBtn.classList.add 'btn', 'btn-small', 'btn-danger'
      deleteBtn.addEventListener 'click', -> showDeleteModal payment
      actionsCell.appendChild deleteBtn

      row.appendChild actionsCell
      tbody.appendChild row

  # Update summary
  document.getElementById('total-payments').textContent = payments.length
  document.getElementById('total-amount').textContent   = totalAmount.toFixed(2)

  container.style.display = 'block'


# Show edit modal
showEditModal = (payment) ->
  selectedPayment = payment

  paymentDate = new Date payment.payment_date

  document.getElementById('edit-amount').value = "$#{payment.amount.toFixed(2)}"
  document.getElementById('edit-date').value   = paymentDate.toLocaleDateString()
  document.getElementById('edit-year').value   = payment.year
  document.getElementById('edit-month').value  = payment.month
  document.getElementById('edit-notes').value  = payment.notes or ''

  document.getElementById('edit-modal').style.display = 'flex'


# Hide edit modal
hideEditModal = ->
  selectedPayment = null
  document.getElementById('edit-modal').style.display = 'none'


# Save payment reassignment
saveReassignment = ->
  return unless selectedPayment

  year  = parseInt document.getElementById('edit-year').value
  month = parseInt document.getElementById('edit-month').value

  unless year and month
    alert 'Please select both year and month'
    return

  try
    response = await fetch "/v1/api/payments/#{selectedPayment.id}/reassign",
      method:  'PUT'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify { year, month }

    unless response.ok
      data = await response.json()
      throw new Error data.error or "Failed to reassign payment"

    hideEditModal()
    await loadPayments()
    showSuccess "Payment reassigned to #{MONTH_NAMES[month - 1]} #{year}"

  catch err
    alert "Error: #{err.message}"


# Show delete modal
showDeleteModal = (payment) ->
  selectedPayment = payment

  paymentDate = new Date payment.payment_date

  document.getElementById('delete-amount').textContent = payment.amount.toFixed(2)
  document.getElementById('delete-date').textContent   = paymentDate.toLocaleDateString()

  document.getElementById('delete-modal').style.display = 'flex'


# Hide delete modal
hideDeleteModal = ->
  selectedPayment = null
  document.getElementById('delete-modal').style.display = 'none'


# Delete payment
deletePayment = ->
  return unless selectedPayment

  try
    response = await fetch "/v1/api/payments/#{selectedPayment.id}",
      method: 'DELETE'

    unless response.ok
      data = await response.json()
      throw new Error data.error or "Failed to delete payment"

    hideDeleteModal()
    await loadPayments()
    showSuccess "Payment deleted"

  catch err
    alert "Error: #{err.message}"


# UI helpers
showLoading = (show) ->
  document.getElementById('loading').style.display = if show then 'block' else 'none'


showError = (message) ->
  errorDiv = document.getElementById 'error'
  errorDiv.textContent   = message
  errorDiv.style.display = 'block'
  document.getElementById('loading').style.display = 'none'


showSuccess = (message) ->
  # Simple alert for now, could be replaced with toast notification
  alert message


# Event listeners
document.addEventListener 'DOMContentLoaded', ->
  loadPayments()

  # Refresh button
  document.getElementById('refresh-btn').addEventListener 'click', ->
    loadPayments()

  # Save reassignment button
  document.getElementById('save-reassign-btn').addEventListener 'click', ->
    saveReassignment()

  # Delete confirmation button
  document.getElementById('confirm-delete-btn').addEventListener 'click', ->
    deletePayment()

  # Modal close buttons
  closeButtons = document.querySelectorAll '.modal-close'
  for btn in closeButtons
    btn.addEventListener 'click', ->
      hideEditModal()
      hideDeleteModal()

  # Close modal when clicking outside
  document.getElementById('edit-modal').addEventListener 'click', (e) ->
    if e.target.classList.contains 'modal'
      hideEditModal()

  document.getElementById('delete-modal').addEventListener 'click', (e) ->
    if e.target.classList.contains 'modal'
      hideDeleteModal()
