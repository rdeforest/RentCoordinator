# Bug 35 — money held as floating-point dollars.
#
# The failure is not abstract: an hourly credit on fractional hours produces
# an amount no payment method can settle, so a fully-paid month reads PARTIAL
# for ever over a fraction of a cent.

{ describe, it }        = require 'node:test'
assert                  = require 'node:assert/strict'
money                   = require '../../lib/money.coffee'
{ computeAllPeriods }   = require '../../lib/services/period.coffee'

NOW = new Date '2026-06-11T12:00:00Z'

work    = (ym, hours)  -> { id: "w-#{ym}", occurred_at: "#{ym}-05T00:00:00Z", effective_for: ym, actor: 'tenant', actor_user: 'lynz57@hotmail.com', action: 'work-reported', payload: { hours } }
payment = (ym, amount) -> { id: "p-#{ym}", occurred_at: "#{ym}-20T00:00:00Z", effective_for: ym, actor: 'tenant', actor_user: 'lynz57@hotmail.com', action: 'payment-made',  payload: { amount } }


describe 'Cent arithmetic', ->
  it 'rounds to the nearest cent', ->
    assert.equal money.dollars(1433.3333333333333), 1433.33
    assert.equal money.dollars(0.005),              0.01
    assert.equal money.dollars(0),                  0

  it 'is idempotent on an amount that is already money', ->
    assert.equal money.dollars(money.dollars 166.666666), money.dollars 166.666666

  it 'subtracts without leaving residue', ->
    assert.equal money.minus(1433.3333333333333, 1433.33), 0,
      'the third of a cent that kept a paid month outstanding'
    assert.equal money.minus(0.3, 0.1), 0.2,
      '0.3 - 0.1 is 0.19999999999999998 in raw floats'

  it 'treats equal money as equal', ->
    assert.ok money.same 1433.3333333333333, 1433.33
    assert.ok not money.same 1433.33, 1433.34

  it 'handles null and undefined as zero', ->
    assert.equal money.cents(null),      0
    assert.equal money.cents(undefined), 0


describe 'A month can always be paid exactly (bug 35)', ->
  # 200 minutes is 3.333… hours; at $50/hour the credit is $166.666…
  FRACTIONAL = 200 / 60

  it 'the amount due lands on a cent', ->
    due = computeAllPeriods([work '2026-01', FRACTIONAL], NOW)['2026-01'].amount_due

    assert.equal due, money.dollars(due),
      "an amount due of #{due} cannot be charged by any payment method"

  it 'paying the stated amount settles the month', ->
    due    = computeAllPeriods([work '2026-01', FRACTIONAL], NOW)['2026-01'].amount_due
    period = computeAllPeriods([work('2026-01', FRACTIONAL), payment('2026-01', due)], NOW)['2026-01']

    assert.equal period.amount_paid - period.display_amount_due, 0
    assert.equal period.payment_status, 'PAID',
      'this read PARTIAL for ever, over a third of a cent'

  it 'every currency field is a real amount of money', ->
    period = computeAllPeriods([work '2026-01', FRACTIONAL], NOW)['2026-01']

    fields = ['discount_applied', 'total_discount', 'retroactive_credit', 'base_rent',
              'agreed_payment', 'effective_agreed_payment', 'amount_due',
              'amount_due_calculated', 'amount_paid', 'display_amount_due']

    for field in fields
      assert.equal period[field], money.dollars(period[field]),
        "#{field} is #{period[field]}, which is not a payable amount"

  it 'leaves the carried-forward values alone — they are not display money', ->
    period = computeAllPeriods([work '2026-01', FRACTIONAL], NOW)['2026-01']

    assert.equal period.hours_worked, FRACTIONAL,
      'rounding hours would silently lose carry-over'

    # cumulative_shortfall feeds the next month's retroactive credit. Rounding
    # a running balance before carrying it forward makes it drift against the
    # exact figure, and nothing displays it.
    exact = computeAllPeriods([work '2026-01', 1 / 3], NOW)['2026-01']
    assert.notEqual exact.cumulative_shortfall, money.dollars(exact.cumulative_shortfall),
      'the shortfall is carried at full precision'

  it 'does not launder a corrupt amount into a confident zero', ->
    assert.ok Number.isNaN(money.cents NaN),
      'NaN must stay NaN; `or 0` turned it into $0.00 and the month read PAID'
    assert.equal money.cents(null),      0
    assert.equal money.cents(undefined), 0
