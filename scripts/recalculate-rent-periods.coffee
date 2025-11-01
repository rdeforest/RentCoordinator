#!/usr/bin/env coffee

# Recalculate all rent periods to update hours and discount fields

db          = require '../lib/db/schema.coffee'
rentService = require '../lib/services/rent.coffee'
rentModel   = require '../lib/models/rent.coffee'

do ->
  console.log 'Initializing database...'
  await db.initialize()

  console.log 'Fetching all rent periods...'
  periods = await rentModel.getAllRentPeriods()

  console.log "Found #{periods.length} periods to recalculate\n"

  for period in periods
    { year, month } = period

    console.log "Recalculating #{year}-#{String(month).padStart(2, '0')}..."

    # Calculate rent using the service
    calculation = await rentService.calculateRent year, month

    # Update the period with calculated values
    updated = await rentModel.updateRentPeriod year, month,
      hours_worked:        calculation.hours_worked
      hours_from_previous: calculation.hours_from_previous
      hours_to_next:       calculation.hours_to_next
      manual_adjustments:  calculation.manual_adjustments or 0
      discount_applied:    calculation.discount_applied or 0
      amount_due:          calculation.amount_due
      amount_paid:         Math.abs(calculation.amount_paid)

    console.log """
      ✓ Updated:
        Hours worked: #{calculation.hours_worked}
        Hours from previous: #{calculation.hours_from_previous}
        Discount applied: $#{calculation.discount_applied}
        Amount due: $#{calculation.amount_due}
        Amount paid: $#{Math.abs(calculation.amount_paid)}
    """

  console.log '\n✓ Recalculation complete!\n'

  # Show summary
  summary = await rentService.getRentSummary()
  console.log """
    Summary:
      Total periods: #{summary.total_periods}
      Total base rent: $#{summary.total_base_rent}
      Total discount: $#{summary.total_discount_applied}
      Total due: $#{summary.total_amount_due}
      Total paid: $#{summary.total_amount_paid}
      Outstanding: $#{summary.outstanding_balance}
  """

  process.exit 0
