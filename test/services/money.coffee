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

  it 'converts ledger amounts to cents without defaulting a missing one', ->
    assert.equal money.centsOf(1433.33), 143333
    assert.ok Number.isNaN(money.centsOf undefined),
      'a payment with no amount has to surface as corrupt, not as $0'

  it 'round-trips whole cents exactly', ->
    # 29 and 57 are among the cents whose (c / 100) * 100 lands just below c,
    # so truncating instead of rounding would lose a cent on them.
    for c in [0, 1, 29, 57, 99, 143333, 95000, -2500]
      assert.equal money.centsOf(money.fromCents c), c

  it 'knows whole cents from fractions of one', ->
    assert.ok money.isWholeCents 1433.33
    assert.ok money.isWholeCents 0.3 - 0.1, 'float residue on a real amount is still that amount'
    assert.ok not money.isWholeCents 10.005
    assert.ok not money.isWholeCents 166.66666666666666
    assert.ok not money.isWholeCents NaN

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

  it 'keeps hours exact and the shortfall in whole cents', ->
    period = computeAllPeriods([work '2026-01', FRACTIONAL], NOW)['2026-01']

    assert.equal period.hours_worked, FRACTIONAL,
      'rounding hours would silently lose carry-over'

    # The shortfall is money: rounded once, where unworked hours become
    # dollars, and carried in whole cents so it cannot drift.
    short = computeAllPeriods([work '2026-01', 1 / 3], NOW)['2026-01']
    assert.equal short.cumulative_shortfall, 383.33, '(8 - 1/3) hours at $50 is $383.333…'

  it 'a shortfall recovered in full leaves exactly nothing behind', ->
    periods = computeAllPeriods [work('2026-01', 1 / 3), work('2026-02', 20)], NOW
    feb     = periods['2026-02']

    assert.equal feb.retroactive_credit, 383.33
    assert.equal feb.cumulative_shortfall, 0
    assert.ok Math.abs(feb.hours_to_next - (20 - 8 - 383.33 / 50)) < 1e-9,
      'carry-over is what remains after the exact hours the recovery used'

  it 'does not launder a corrupt amount into a confident zero', ->
    assert.ok Number.isNaN(money.cents NaN),
      'NaN must stay NaN; `or 0` turned it into $0.00 and the month read PAID'
    assert.equal money.cents(null),      0
    assert.equal money.cents(undefined), 0


describe 'The fold in cents', ->
  override = (ym, field, new_value) ->
    { id: "o-#{ym}-#{field}", occurred_at: "#{ym}-25T00:00:00Z", effective_for: ym, actor: 'landlord', actor_user: 'robert@defore.st', action: 'override', payload: { target_kind: 'period-field', target: { field }, new_value } }

  it 'marks a month corrupt when a stored amount is missing or null', ->
    for bad in [undefined, null]
      assert.equal computeAllPeriods([payment '2026-01', bad], NOW)['2026-01'].corrupt, true,
        "a payment of #{bad} must not count as $0"
      assert.equal computeAllPeriods([override '2026-01', 'amount_due', bad], NOW)['2026-01'].corrupt, true,
        "an override to #{bad} must not pin the month at $0"

  it 'credit plus shortfall is exactly a full month of credit', ->
    for hours in [0.5001, 1 / 60, 1 / 7, 200 / 60, 7.9999]
      p = computeAllPeriods([work '2026-01', hours], NOW)['2026-01']
      assert.equal money.cents(p.discount_applied) + money.cents(p.cumulative_shortfall), 8 * 5000,
        "#{hours} hours: rounding the two halves separately can make a cent"

  it 'recovers a shortfall from hours that are not thirds, to the cent', ->
    periods = computeAllPeriods [work('2026-01', 1 / 7), work('2026-02', 30)], NOW
    jan     = periods['2026-01']
    feb     = periods['2026-02']

    assert.equal jan.discount_applied, 7.14,     '1/7 hour at $50 is $7.142857…'
    assert.equal jan.cumulative_shortfall, 392.86
    assert.equal feb.retroactive_credit, 392.86, 'recovered in full'
    assert.equal feb.cumulative_shortfall, 0
