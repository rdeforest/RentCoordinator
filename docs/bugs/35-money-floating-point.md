# Bug 35 — Money handled as floating-point dollars throughout

**Reported:** 2026-08-15 by codebase audit
**Status:** active

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
