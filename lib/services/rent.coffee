# lib/services/rent.coffee

rentModel    = await import('../models/rent.coffee')
workLogModel = await import('../models/work_log.coffee')
config       = await import('../config.coffee')


BASE_RENT     = config.BASE_RENT or 1600
HOURLY_CREDIT = config.HOURLY_CREDIT or 50
MAX_MONTHLY_HOURS = config.MAX_MONTHLY_HOURS or 8


# Calculate rent for a specific month
export calculateRent = (year, month) ->
  # Get work logs for this month
  startDate = new Date(year, month - 1, 1)
  endDate = new Date(year, month, 0, 23, 59, 59)

  # Get all Lyndzie's work logs
  allLogs = await workLogModel.getWorkLogs({ worker: 'lyndzie' })

  # Filter to this month
  monthLogs = allLogs.filter (log) ->
    logDate = new Date(log.start_time)
    logDate >= startDate and logDate <= endDate

  # Calculate total hours worked this month
  hoursWorked = monthLogs.reduce ((total, log) ->
    total + (log.duration / 60)  # Convert minutes to hours
  ), 0

  # Get previous month's data for roll-over
  previousMonth = if month is 1 then 12 else month - 1
  previousYear = if month is 1 then year - 1 else year
  previousPeriod = await rentModel.getRentPeriod(previousYear, previousMonth)

  hoursFromPrevious = previousPeriod?.hours_to_next or 0

  # Calculate total available hours
  totalAvailableHours = hoursWorked + hoursFromPrevious

  # Apply up to MAX_MONTHLY_HOURS
  hoursToApply = Math.min(totalAvailableHours, MAX_MONTHLY_HOURS)
  hoursToNext = totalAvailableHours - hoursToApply

  # Calculate discount
  discountApplied = hoursToApply * HOURLY_CREDIT
  baseAmountDue = BASE_RENT - discountApplied

  # Get manual adjustments and payments for this period
  events = await rentModel.getRentEventsForPeriod(year, month)

  # Calculate adjustments from manual events
  manualAdjustments = 0
  totalPayments = 0

  for event in events
    if event.type is 'adjustment' or event.type is 'manual'
      # Manual adjustments affect the amount due
      manualAdjustments += event.amount
    else if event.type is 'payment'
      # Payments are tracked separately
      totalPayments += event.amount

  # Final amount due includes manual adjustments
  amountDue = baseAmountDue + manualAdjustments

  return {
    year: year
    month: month
    hours_worked: hoursWorked
    hours_from_previous: hoursFromPrevious
    total_available_hours: totalAvailableHours
    hours_applied: hoursToApply
    hours_to_next: hoursToNext
    discount_applied: discountApplied
    manual_adjustments: manualAdjustments
    amount_due: amountDue
    amount_paid: totalPayments
  }


# Recalculate all rent periods with retroactive adjustments
export recalculateAllRent = ->
  # Get all work logs for Lyndzie
  allLogs = await workLogModel.getWorkLogs({ worker: 'lyndzie' })

  # Group by month
  logsByMonth = {}
  for log in allLogs
    date = new Date(log.start_time)
    key = "#{date.getFullYear()}-#{date.getMonth() + 1}"
    logsByMonth[key] ?= []
    logsByMonth[key].push log

  # Get all existing rent periods
  allPeriods = await rentModel.getAllRentPeriods()

  # Find earliest month with work or rent
  months = Object.keys(logsByMonth).concat(allPeriods.map (p) -> "#{p.year}-#{p.month}")
  months = [...new Set(months)].sort()

  periods = []
  carryOverHours = 0
  totalShortfall = 0  # Track cumulative shortfall for retroactive adjustments

  for monthKey in months
    [year, month] = monthKey.split('-').map (n) -> parseInt(n)

    # Calculate hours worked this month
    monthLogs = logsByMonth[monthKey] or []
    hoursWorked = monthLogs.reduce ((total, log) ->
      total + (log.duration / 60)
    ), 0

    # Total available hours including carry-over
    totalAvailable = hoursWorked + carryOverHours

    # Base calculation
    baseHoursApplied = Math.min(totalAvailable, MAX_MONTHLY_HOURS)
    baseDiscount = baseHoursApplied * HOURLY_CREDIT
    baseAmountDue = BASE_RENT - baseDiscount

    # Check for retroactive adjustment opportunity
    retroactiveAdjustment = 0
    if totalShortfall > 0 and totalAvailable > MAX_MONTHLY_HOURS
      # We have both a shortfall to make up and extra hours to use
      extraHours = totalAvailable - MAX_MONTHLY_HOURS
      maxRetroactiveHours = Math.min(extraHours, totalShortfall / HOURLY_CREDIT)
      retroactiveAdjustment = maxRetroactiveHours * HOURLY_CREDIT
      totalShortfall -= retroactiveAdjustment

    # Get manual adjustments and payments for this period
    events = await rentModel.getRentEventsForPeriod(year, month)

    # Calculate adjustments from manual events
    manualAdjustments = 0
    totalPayments = 0

    for event in events
      if event.type is 'adjustment' or event.type is 'manual'
        manualAdjustments += event.amount
      else if event.type is 'payment'
        totalPayments += event.amount

    # Final amounts
    totalDiscount = baseDiscount + retroactiveAdjustment
    finalAmountDue = BASE_RENT - totalDiscount + manualAdjustments

    # Update carry-over for next month
    hoursUsed = baseHoursApplied + (retroactiveAdjustment / HOURLY_CREDIT)
    carryOverHours = totalAvailable - hoursUsed

    # Track shortfall if we couldn't apply full 8 hours
    if baseHoursApplied < MAX_MONTHLY_HOURS
      shortfallThisMonth = (MAX_MONTHLY_HOURS - baseHoursApplied) * HOURLY_CREDIT
      totalShortfall += shortfallThisMonth

    periods.push
      year: year
      month: month
      hours_worked: hoursWorked
      hours_from_previous: if periods.length > 0 then periods[periods.length - 1].hours_to_next else 0
      hours_applied: baseHoursApplied
      retroactive_hours: retroactiveAdjustment / HOURLY_CREDIT
      hours_to_next: carryOverHours
      base_discount: baseDiscount
      retroactive_adjustment: retroactiveAdjustment
      total_discount: totalDiscount
      manual_adjustments: manualAdjustments
      amount_due: finalAmountDue
      amount_paid: totalPayments
      cumulative_shortfall: totalShortfall

  return periods


# Create or update rent period
export createOrUpdateRentPeriod = (year, month) ->
  calculation = await calculateRent(year, month)

  existing = await rentModel.getRentPeriod(year, month)

  if existing
    # Update existing period, preserving payment data if not recalculated
    updated = await rentModel.updateRentPeriod year, month,
      hours_worked: calculation.hours_worked
      hours_from_previous: calculation.hours_from_previous
      hours_to_next: calculation.hours_to_next
      discount_applied: calculation.discount_applied
      amount_due: calculation.amount_due
      amount_paid: calculation.amount_paid

    return updated
  else
    # Create new period
    return await rentModel.createRentPeriod(calculation)


# Get rent summary
export getRentSummary = ->
  periods = await rentModel.getAllRentPeriods()

  totalDue = 0
  totalPaid = 0
  totalDiscount = 0

  for period in periods
    totalDue += period.amount_due
    totalPaid += period.amount_paid or 0
    totalDiscount += period.discount_applied

  return {
    total_periods: periods.length
    total_base_rent: periods.length * BASE_RENT
    total_discount_applied: totalDiscount
    total_amount_due: totalDue
    total_amount_paid: totalPaid
    outstanding_balance: totalDue - totalPaid
    periods: periods
  }