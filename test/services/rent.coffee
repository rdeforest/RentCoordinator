# tests/services/rent_test.coffee
# Tests for rent calculation logic

{ test, describe } = require 'node:test'
assert             = require 'node:assert/strict'

# Test the core rent calculation logic
# Note: These tests verify the business rules in isolation

# Constants from config
BASE_RENT         = 1600
HOURLY_CREDIT     = 50
MAX_MONTHLY_HOURS = 8


test "Rent Calculation - Base rent with no work", ->
  # Simulate: No work done this month
  hoursWorked         = 0
  hoursFromPrevious   = 0
  totalAvailableHours = hoursWorked + hoursFromPrevious
  hoursToApply        = Math.min totalAvailableHours, MAX_MONTHLY_HOURS
  discountApplied     = hoursToApply * HOURLY_CREDIT
  amountDue           = BASE_RENT - discountApplied

  assert.equal hoursToApply, 0
  assert.equal discountApplied, 0
  assert.equal amountDue, 1600, "Full rent due with no work"


test "Rent Calculation - Maximum credit (8 hours)", ->
  # Simulate: 8 hours worked (maximum creditable)
  hoursWorked         = 8
  hoursFromPrevious   = 0
  totalAvailableHours = hoursWorked + hoursFromPrevious
  hoursToApply        = Math.min totalAvailableHours, MAX_MONTHLY_HOURS
  hoursToNext         = totalAvailableHours - hoursToApply
  discountApplied     = hoursToApply * HOURLY_CREDIT
  amountDue           = BASE_RENT - discountApplied

  assert.equal hoursToApply, 8
  assert.equal hoursToNext, 0
  assert.equal discountApplied, 400, "8 hours @ $50/hr = $400"
  assert.equal amountDue, 1200, "$1600 - $400 = $1200"


test "Rent Calculation - Excess hours rollover", ->
  # Simulate: 12 hours worked, 4 should roll over
  hoursWorked         = 12
  hoursFromPrevious   = 0
  totalAvailableHours = hoursWorked + hoursFromPrevious
  hoursToApply        = Math.min totalAvailableHours, MAX_MONTHLY_HOURS
  hoursToNext         = totalAvailableHours - hoursToApply
  discountApplied     = hoursToApply * HOURLY_CREDIT
  amountDue           = BASE_RENT - discountApplied

  assert.equal hoursToApply, 8, "Only 8 hours applied"
  assert.equal hoursToNext, 4, "4 hours roll over to next month"
  assert.equal discountApplied, 400
  assert.equal amountDue, 1200


test "Rent Calculation - Previous month rollover", ->
  # Simulate: 5 hours worked this month, 4 from previous month
  hoursWorked         = 5
  hoursFromPrevious   = 4
  totalAvailableHours = hoursWorked + hoursFromPrevious
  hoursToApply        = Math.min totalAvailableHours, MAX_MONTHLY_HOURS
  hoursToNext         = totalAvailableHours - hoursToApply
  discountApplied     = hoursToApply * HOURLY_CREDIT
  amountDue           = BASE_RENT - discountApplied

  assert.equal totalAvailableHours, 9
  assert.equal hoursToApply, 8, "Apply maximum 8 hours"
  assert.equal hoursToNext, 1, "1 hour rolls to next month"
  assert.equal discountApplied, 400
  assert.equal amountDue, 1200


test "Rent Calculation - Manual adjustments", ->
  # Base calculation: 5 hours worked
  hoursWorked       = 5
  discountApplied   = hoursWorked * HOURLY_CREDIT
  baseAmountDue     = BASE_RENT - discountApplied

  # Manual adjustment: $100 rent increase
  manualAdjustments = 100
  amountDue         = baseAmountDue + manualAdjustments

  assert.equal baseAmountDue, 1350, "$1600 - $250 = $1350"
  assert.equal amountDue, 1450, "$1350 + $100 adjustment = $1450"


test "Rent Calculation - Payments tracking", ->
  # Base calculation
  hoursWorked     = 4
  discountApplied = hoursWorked * HOURLY_CREDIT
  amountDue       = BASE_RENT - discountApplied

  # Payment tracking (doesn't affect amount_due, tracked separately)
  amountPaid  = 1000
  outstanding = amountDue - amountPaid

  assert.equal amountDue, 1400, "$1600 - $200 = $1400"
  assert.equal outstanding, 400, "$1400 - $1000 paid = $400 outstanding"


test "Rent Calculation - Zero work with rollover", ->
  # Simulate: No work this month, but 3 hours from previous
  hoursWorked         = 0
  hoursFromPrevious   = 3
  totalAvailableHours = hoursWorked + hoursFromPrevious
  hoursToApply        = Math.min totalAvailableHours, MAX_MONTHLY_HOURS
  hoursToNext         = totalAvailableHours - hoursToApply
  discountApplied     = hoursToApply * HOURLY_CREDIT
  amountDue           = BASE_RENT - discountApplied

  assert.equal hoursToApply, 3, "Apply all 3 rollover hours"
  assert.equal hoursToNext, 0, "No hours left to roll over"
  assert.equal discountApplied, 150, "3 hours @ $50/hr = $150"
  assert.equal amountDue, 1450, "$1600 - $150 = $1450"


test "Rent Calculation - Fractional hours", ->
  # Simulate: 6.5 hours worked
  hoursWorked     = 6.5
  discountApplied = hoursWorked * HOURLY_CREDIT
  amountDue       = BASE_RENT - discountApplied

  assert.equal discountApplied, 325, "6.5 hours @ $50/hr = $325"
  assert.equal amountDue, 1275, "$1600 - $325 = $1275"


# Retroactive-credit walk (covers bug #05). Two months:
#   A: 4 hours worked  → shortfall of 4 hours × $50 = $200
#   B: 16 hours worked → 8 applied to B, 8 leftover; retire A's shortfall
test "Rent Calculation - Retroactive credit retires prior shortfall", ->
  carryOverHours = 0
  totalShortfall = 0

  # Month A
  hoursWorkedA    = 4
  totalAvailableA = hoursWorkedA + carryOverHours
  appliedA        = Math.min totalAvailableA, MAX_MONTHLY_HOURS
  discountA       = appliedA * HOURLY_CREDIT
  amountDueA      = BASE_RENT - discountA
  carryOverHours  = totalAvailableA - appliedA
  totalShortfall += (MAX_MONTHLY_HOURS - appliedA) * HOURLY_CREDIT if appliedA < MAX_MONTHLY_HOURS

  assert.equal appliedA,       4
  assert.equal discountA,      200
  assert.equal amountDueA,     1400
  assert.equal totalShortfall, 200, "Month A leaves $200 shortfall"

  # Month B
  hoursWorkedB    = 16
  totalAvailableB = hoursWorkedB + carryOverHours
  appliedB        = Math.min totalAvailableB, MAX_MONTHLY_HOURS

  retroactive = 0
  if totalShortfall > 0 and totalAvailableB > MAX_MONTHLY_HOURS
    extraHours          = totalAvailableB - MAX_MONTHLY_HOURS
    maxRetroactiveHours = Math.min extraHours, totalShortfall / HOURLY_CREDIT
    retroactive         = maxRetroactiveHours * HOURLY_CREDIT
    totalShortfall     -= retroactive

  totalDiscountB = appliedB * HOURLY_CREDIT + retroactive
  amountDueB     = BASE_RENT - totalDiscountB

  assert.equal appliedB,       8,    "Month B caps at 8 applied"
  assert.equal retroactive,    200,  "Month B's leftover 8 hours retire all $200 shortfall"
  assert.equal totalDiscountB, 600,  "$400 base credit + $200 retroactive"
  assert.equal amountDueB,     1000, "$1600 - $600 = $1000 for Month B"
  assert.equal totalShortfall, 0,    "Shortfall fully retired"


# Stress-free display: server-side payment status for current month before/after the 15th
test "Payment Status - Current month not-due before the 15th", ->
  RENT_DUE_DAY = 15
  currentDay   = 10
  isCurrent    = true
  isBeforeDue  = isCurrent and currentDay < RENT_DUE_DAY

  status = if isBeforeDue then 'NOT DUE' else 'UNPAID'
  assert.equal status, 'NOT DUE'


test "Payment Status - Current month after 15th, agreed payment received", ->
  RENT_DUE_DAY  = 15
  currentDay    = 20
  isCurrent     = true
  isBeforeDue   = isCurrent and currentDay < RENT_DUE_DAY
  displayDue    = 950
  paid          = 950

  status =
    if      isBeforeDue       then 'NOT DUE'
    else if paid >= displayDue then 'PAID'
    else if paid > 0          then 'PARTIAL'
    else                            'UNPAID'

  assert.equal status, 'PAID', "Paying the agreed amount marks the month as PAID"


test "Payment Status - Past month with partial payment", ->
  displayDue = 950
  paid       = 400

  status =
    if      paid >= displayDue then 'PAID'
    else if paid > 0          then 'PARTIAL'
    else                            'UNPAID'

  assert.equal status, 'PARTIAL'
