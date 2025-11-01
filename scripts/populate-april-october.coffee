#!/usr/bin/env coffee

# Script to populate rent data for April-October 2025
# - Creates rent periods for each month
# - Adds rent due events (15th of each month)
# - Records Lyndzie's $950 payments for May-October

db         = require '../lib/db/schema.coffee'
rentModel  = require '../lib/models/rent.coffee'

do ->
  console.log 'Initializing database...'
  await db.initialize()

  # Define the months and payment data
  months = [
    { year: 2025, month: 4, name: 'April' }
    { year: 2025, month: 5, name: 'May' }
    { year: 2025, month: 6, name: 'June' }
    { year: 2025, month: 7, name: 'July' }
    { year: 2025, month: 8, name: 'August' }
    { year: 2025, month: 9, name: 'September' }
    { year: 2025, month: 10, name: 'October' }
  ]

  # Months that had $950 payments (May-October)
  paidMonths = [5, 6, 7, 8, 9, 10]

  console.log '\nCreating rent periods and events...\n'

  for monthData in months
    { year, month, name } = monthData

    # Create or get rent period
    period = await rentModel.getOrCreateRentPeriod year, month
    console.log "✓ Created rent period for #{name} #{year}"

    # Create rent due event (due on 15th of month)
    dueDate = new Date(year, month - 1, 15).toISOString()

    try
      rentDueEvent = await rentModel.createRentEvent
        period_id:   period.id
        year:        year
        month:       month
        type:        'rent_due'
        amount:      1600
        description: "Rent due for #{name} #{year}"
        metadata:
          due_date: dueDate
        created_by:  'system'

      console.log "  ✓ Created rent due event ($1600, due #{name} 15)"
    catch err
      console.log "  ⚠ Rent due event may already exist: #{err.message}"

    # Add payment if this month had one
    if month in paidMonths
      try
        paymentEvent = await rentModel.createRentEvent
          period_id:   period.id
          year:        year
          month:       month
          type:        'payment'
          amount:      -950
          description: "Payment received for #{name} #{year}"
          metadata:
            payment_method: 'venmo'
            payment_date:   new Date(year, month - 1, 20).toISOString()
          created_by:  'lyndzie'

        console.log "  ✓ Recorded payment ($950)"
      catch err
        console.log "  ⚠ Payment may already exist: #{err.message}"

  console.log '\n✓ Population complete!\n'

  # Show summary
  console.log 'Summary of all rent periods:'
  periods = await rentModel.getAllRentPeriods()

  for period in periods
    events = await rentModel.getRentEventsForPeriod period.year, period.month
    totalPayments = 0

    for event in events
      if event.type is 'payment'
        totalPayments += Math.abs(event.amount)

    balance = period.amount_due - totalPayments
    console.log """
      #{period.year}-#{String(period.month).padStart(2, '0')}:
        Due: $#{period.amount_due},
        Paid: $#{totalPayments},
        Balance: $#{balance}
    """

  process.exit 0
