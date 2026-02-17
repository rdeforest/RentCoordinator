#!/usr/bin/env coffee

# Script to populate rent data for November 2025 - January 2026
# - Creates rent periods for each month
# - Adds rent due events (15th of each month)
# - Records Lyndzie's payments:
#   - December 2025: $200 on Dec 10, $200 on Dec 29
#   - January 2026: $950 on Jan 20
#
# Usage:
#   RENT_SESSION_COOKIE="connect.sid=..." npx coffee scripts/populate-november-january.coffee
#   or
#   RENT_API_URL="http://localhost:3000" npx coffee scripts/populate-november-january.coffee

BASE_URL        = process.env.RENT_API_URL or 'https://rent.thatsnice.org'
SESSION_COOKIE  = process.env.RENT_SESSION_COOKIE

unless SESSION_COOKIE
  console.error 'Error: RENT_SESSION_COOKIE environment variable required'
  console.error 'Export your session cookie from your browser or /tmp/rent-cookies-final.txt:'
  console.error '  RENT_SESSION_COOKIE="$(cat /tmp/rent-cookies-final.txt)" npx coffee scripts/populate-november-january.coffee'
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

  # Define the months
  months = [
    { year: 2025, month: 11, name: 'November' }
    { year: 2025, month: 12, name: 'December' }
    { year: 2026, month: 1,  name: 'January' }
  ]

  # Payment data
  payments = [
    # December: $200 on Dec 10, $200 on Dec 29
    { year: 2025, month: 12, amount: 200, date: '2025-12-10', method: 'venmo', notes: 'First December payment' }
    { year: 2025, month: 12, amount: 200, date: '2025-12-29', method: 'venmo', notes: 'Second December payment' }
    # January: $950 on Jan 20
    { year: 2026, month: 1,  amount: 950, date: '2026-01-20', method: 'venmo', notes: 'January payment' }
  ]

  console.log 'Creating rent periods and events...\n'

  for monthData in months
    { year, month, name } = monthData

    # Create or get rent period
    try
      period = await apiRequest 'POST', "/rent/period/#{year}/#{month}"
      console.log "✓ Created rent period for #{name} #{year}"
    catch err
      if err.message.includes('already exists') or err.message.includes('404')
        console.log "⚠ Period for #{name} may already exist, continuing..."
      else
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

  console.log '\n'
  console.log 'Recording payments...\n'

  for payment in payments
    { year, month, amount, date, method, notes } = payment

    try
      result = await apiRequest 'POST', '/rent/payment',
        year:           year
        month:          month
        amount:         amount
        payment_method: method
        notes:          notes
        payment_date:   date

      monthName = months.find((m) -> m.year is year and m.month is month)?.name or "#{year}-#{month}"
      console.log "✓ Recorded payment for #{monthName}: $#{amount} on #{date}"
    catch err
      if err.message.includes 'already exists'
        console.log "⚠ Payment already exists: $#{amount} on #{date}"
      else
        console.log "⚠ Error recording payment: #{err.message}"

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

  # Show detail for the new months
  console.log '\nDetailed view of November 2025 - January 2026:'
  for monthData in months
    { year, month, name } = monthData
    try
      period = await apiRequest 'GET', "/rent/period/#{year}/#{month}"
      console.log """
        #{name} #{year}:
          Amount due:  $#{period.amount_due}
          Amount paid: $#{period.amount_paid}
          Status:      #{if period.amount_paid >= 950 then 'PAID' else 'PARTIAL'}
      """
    catch err
      console.log "⚠ Error fetching #{name} #{year}: #{err.message}"

  process.exit 0
