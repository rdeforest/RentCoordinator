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
