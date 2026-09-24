# Bug 59 — "Pay everything outstanding" built its Stripe allocation from
# every month computeOutstanding returned, including corrupt ones (kept at
# outstanding: 0 so the dashboard can flag them, not dropped). A corrupt
# month in the allocation meant a $0 payment-made event got recorded against
# it when the webhook fired — silently, and the month stays uncomputable.
#
# lib/routes/payment.coffee's buildOutstandingAllocation is pure and does
# not touch Stripe, so it's tested directly here rather than through
# /payment/create-intent, which needs a real STRIPE_SECRET_KEY to reach the
# code under test at all.

process.env.NODE_ENV = 'test'

{ test } = require 'node:test'
assert   = require 'node:assert/strict'

{ buildOutstandingAllocation } = require '../../lib/routes/payment.coffee'


month = (year, month, outstanding, corrupt = false) ->
  { year, month, owed: outstanding, paid: 0, outstanding, corrupt }


test "a corrupt month is excluded from the allocation entirely (bug 59)", ->
  outstanding =
    total:  1600
    months: [ month(2026, 1, 1600), month(2026, 2, 0, true) ]

  { allocation, payableMonths } = buildOutstandingAllocation outstanding

  assert.equal allocation.length, 1, 'only the payable month is allocated'
  assert.equal allocation[0].month, 1
  assert.equal payableMonths.length, 1
  assert.ok not payableMonths.some((m) -> m.corrupt), 'no corrupt month reaches the allocation'


test "ymList and description only name payable months", ->
  outstanding =
    total:  1600
    months: [ month(2026, 1, 1600), month(2026, 2, 0, true) ]

  { ymList, description } = buildOutstandingAllocation outstanding

  assert.equal ymList, '2026-01'
  assert.equal description, 'Rent payment covering 2026-01'


test "with no corrupt months, every month is allocated", ->
  outstanding =
    total:  1600 + 1200
    months: [ month(2026, 1, 1600), month(2026, 2, 1200) ]

  { allocation } = buildOutstandingAllocation outstanding

  assert.equal allocation.length, 2
  assert.equal allocation.reduce(((s, a) -> s + a.amount), 0), 2800
