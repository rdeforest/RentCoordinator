#!/usr/bin/env coffee

# Script to populate rent data for April-October 2025 via API
# - Creates rent periods for each month
# - Adds rent due events (15th of each month)
# - Records Lyndzie's $950 payments for May-October
#
# Usage:
#   RENT_SESSION_COOKIE="connect.sid=..." npx coffee scripts/populate-april-october.coffee
#   or
#   RENT_API_URL="http://localhost:3000" npx coffee scripts/populate-april-october.coffee

BASE_URL        = process.env.RENT_API_URL or 'https://rent.thatsnice.org'
SESSION_COOKIE  = process.env.RENT_SESSION_COOKIE

unless SESSION_COOKIE
  console.error 'Error: RENT_SESSION_COOKIE environment variable required'
  console.error 'Export your session cookie from your browser:'
  console.error '  1. Open DevTools (F12)'
  console.error '  2. Go to Application > Cookies'
  console.error '  3. Copy the "connect.sid" cookie value'
  console.error '  4. Run: RENT_SESSION_COOKIE="connect.sid=YOUR_VALUE" npx coffee scripts/populate-april-october.coffee'
  process.exit 1

# Helper to make API requests
apiRequest = (method, path, body = null) ->
  url = "#{BASE_URL}#{path}"
  options =
    method:  method
    headers:
      'Content-Type': 'application/json'
      'Cookie':       SESSION_COOKIE

  options.body = JSON.stringify(body) if body

  response = await fetch url, options

  unless response.ok
    text = await response.text()
    throw new Error "API request failed (#{response.status}): #{text}"

  return await response.json()


do ->
  console.log "Connecting to #{BASE_URL}...\n"

  # Define the months and payment data
  months = [
    { year: 2025, month: 4,  name: 'April' }
    { year: 2025, month: 5,  name: 'May' }
    { year: 2025, month: 6,  name: 'June' }
    { year: 2025, month: 7,  name: 'July' }
    { year: 2025, month: 8,  name: 'August' }
    { year: 2025, month: 9,  name: 'September' }
    { year: 2025, month: 10, name: 'October' }
  ]

  # Months that had $950 payments (May-October)
  paidMonths = [5, 6, 7, 8, 9, 10]

  console.log 'Creating rent periods and events...\n'

  for monthData in months
    { year, month, name } = monthData

    # Create or get rent period
    try
      period = await apiRequest 'POST', "/rent/period/#{year}/#{month}"
      console.log "✓ Created rent period for #{name} #{year}"
    catch err
      console.log "⚠ Error creating period for #{name}: #{err.message}"
      continue

    # Create rent due event (due on 15th of month)
    dueDate = new Date(year, month - 1, 15).toISOString()

    try
      rentDueEvent = await apiRequest 'POST', '/rent/events',
        type:        'rent_due'
        year:        year
        month:       month
        amount:      1600
        description: "Rent due for #{name} #{year}"
        metadata:
          due_date: dueDate

      console.log "  ✓ Created rent due event ($1600, due #{name} 15)"
    catch err
      if err.message.includes 'already exists'
        console.log "  ⚠ Rent due event already exists"
      else
        console.log "  ⚠ Error creating rent due event: #{err.message}"

    # Add payment if this month had one
    if month in paidMonths
      try
        paymentDate = new Date(year, month - 1, 20).toISOString().split('T')[0]

        payment = await apiRequest 'POST', '/rent/payment',
          year:           year
          month:          month
          amount:         950
          payment_method: 'venmo'
          notes:          "Payment received on #{paymentDate}"

        console.log "  ✓ Recorded payment ($950)"
      catch err
        if err.message.includes 'already exists'
          console.log "  ⚠ Payment already exists"
        else
          console.log "  ⚠ Error recording payment: #{err.message}"

  console.log '\n✓ Population complete!\n'

  # Show summary
  console.log 'Fetching summary...'
  try
    summary = await apiRequest 'GET', '/rent/summary'
    console.log """
      Summary:
        Total periods:  #{summary.total_periods}
        Total due:      $#{summary.total_amount_due}
        Total paid:     $#{summary.total_amount_paid}
        Outstanding:    $#{summary.outstanding_balance}
    """
  catch err
    console.log "⚠ Error fetching summary: #{err.message}"

  process.exit 0
