# Bug 35 — Money handled as floating-point dollars throughout

**Reported:** 2026-08-15 by codebase audit
**Status:** resolved 2026-09-25

## Resolution

**2026-09-23 (partial):** every currency value left `computeMonth` rounded to
the cent, which fixed the reachable failure — a month owing
$1,433.3333333333333 that no payment could settle.

**2026-09-25:** the arithmetic now runs in integer cents.

- **Storage and the API stay in dollars.** Every stored amount in production
  was already a whole number of cents (13 payments, 18 overrides, none
  fractional), so dollars hold them exactly; no historical event was
  rewritten. `recordEvent` now refuses any money field that is not whole cents
  (payment `amount`, adjustment `delta`, override `new_value`, their edits, and
  money-valued `config-changed` fields), so that stays true. Hours are exempt.
- **`computeMonth`** converts its inputs to cents once, computes in integers,
  and converts back on return. Each credit is rounded exactly once, where
  hours become money; hours stay exact. The shortfall is carried between
  months in whole cents, and carry-over subtracts the exact retroactive hours
  rather than credit ÷ rate after rounding.
- **`computeOutstanding`** and the `/rent/summary` totals sum cents.
- `money.minus` is gone; `money.centsOf` converts ledger values without
  defaulting a missing one to 0, so a corrupt event still marks its month
  corrupt.

Verified by folding the production database (2026-09-25) with the old and new
code: every displayed amount, status and the outstanding total are identical.
The only difference is `cumulative_shortfall` in three months, which now lands
on whole cents (104.16666666666679 → 104.17); no route or page displays it.

Not changed: the browser subtracts for display only (the server re-checks any
payment amount in cents), and the legacy `rent_periods` code is untouched.

## Symptom

Payment allocation across months can leave a sub-cent floating-point
residue that trips the overage branch and records a spurious near-zero
`payment-made` event on the last month. More broadly, dollars stored as
floats risk off-by-a-cent reconciliation.

## Reproduction

N/A — latent; triggered when `remaining -= chunk` accumulates
floating-point error across several months so `remaining` lands at a tiny
positive value (e.g. `1e-9`) after the loop, and the `if remaining > 0`
overage branch fires.

## Root cause

`confirmPaymentAllocated` (`lib/services/payment.coffee:86-133`) and
`computeOutstanding` (`lib/routes/payment.coffee:14-19`) sum and subtract
dollars as floats. After allocating chunks across months,
`remaining -= chunk` can leave a residue that passes
`if remaining > 0` (`lib/services/payment.coffee:114`), recording a
near-zero overage event. Storing dollars as floats is fragile for exact
reconciliation generally.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Work in integer cents. Stripe already gives `paymentIntent.amount` in
cents (`lib/services/payment.coffee:86`); keep the arithmetic in cents
through allocation and the outstanding computation, and convert to
dollars only for display. This eliminates the residue and makes the
overage branch exact.

## Risk

Medium reach — touches the payment allocation and outstanding-calculation
paths, and event payloads currently carry dollar amounts. Keep the stored
event `amount` shape consistent (or migrate deliberately) so historical
events still read correctly.
