rentModel          = require '../models/rent.coffee'
workLogModel       = require '../models/work_log.coffee'
config             = require '../config.coffee'


{ BASE_RENT, HOURLY_CREDIT, MAX_MONTHLY_HOURS } = config


calculateRent = (year, month) ->
  startISO = new Date(year, month - 1, 1).toISOString()
  endISO   = new Date(year, month, 1).toISOString()

  monthLogs = await workLogModel.getWorkLogs
    worker:       'lyndzie'
    start_after:  startISO
    start_before: endISO

  hoursWorked = monthLogs.reduce ((total, log) ->
    total + (log.duration / 60)
  ), 0

  previousMonth  = if month is 1 then 12 else month - 1
  previousYear   = if month is 1 then year - 1 else year
  previousPeriod = await rentModel.getRentPeriod previousYear, previousMonth

  hoursFromPrevious = previousPeriod?.hours_to_next or 0

  totalAvailableHours = hoursWorked + hoursFromPrevious

  hoursToApply = Math.min totalAvailableHours, MAX_MONTHLY_HOURS
  hoursToNext  = totalAvailableHours - hoursToApply

  discountApplied = hoursToApply * HOURLY_CREDIT
  baseAmountDue   = BASE_RENT - discountApplied

  events = await rentModel.getRentEventsForPeriod year, month

  manualAdjustments = 0
  totalPayments     = 0

  for event in events
    if event.type is 'adjustment' or event.type is 'manual'
      manualAdjustments += event.amount
    else if event.type is 'payment'
      totalPayments += event.amount

  amountDue = baseAmountDue + manualAdjustments

  return
    year:                  year
    month:                 month
    hours_worked:          hoursWorked
    hours_from_previous:   hoursFromPrevious
    total_available_hours: totalAvailableHours
    hours_applied:         hoursToApply
    hours_to_next:         hoursToNext
    discount_applied:      discountApplied
    manual_adjustments:    manualAdjustments
    amount_due:            amountDue
    amount_paid:           Math.abs totalPayments


getRentSummary = ->
  periods = await rentModel.getAllRentPeriods()

  totalDue      = 0
  totalPaid     = 0
  totalDiscount = 0

  for period in periods
    totalDue      += period.amount_due
    totalPaid     += period.amount_paid or 0
    totalDiscount += period.discount_applied

  return
    total_periods:          periods.length
    total_base_rent:        periods.length * BASE_RENT
    total_discount_applied: totalDiscount
    total_amount_due:       totalDue
    total_amount_paid:      totalPaid
    outstanding_balance:    totalDue - totalPaid
    periods:                periods

module.exports = {
  calculateRent
  getRentSummary
}
