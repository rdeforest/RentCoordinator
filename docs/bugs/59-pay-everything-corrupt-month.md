# Bug 59 — "Pay everything" can record a payment against a corrupt month

**Reported:** 2026-09-24 by architectural review
**Status:** resolved 2026-09-24

## Resolution

`lib/routes/payment.coffee` now builds the "pay everything outstanding"
allocation through a new pure function, `buildOutstandingAllocation`, which
filters `outstanding.months` down to non-corrupt months before building
`ymList`, `description`, and the frozen `allocation` array that later drives
`recordPaymentFromIntent`.

Also in `POST /payment/create-intent`: `amount` is now normalized once, at
the top, with `money.dollars amount` — every downstream comparison
(`money.same amount, expected`) and every allocation entry works from the
same rounded-to-the-cent figure Stripe will actually charge, rather than
whatever precision `req.body` happened to carry.

`lib/services/payment.coffee::createPaymentIntent` now computes
`amountCents` via `money.cents amount` instead of `Math.round amount * 100`
— one source of truth for dollars→cents instead of two call sites that
happened to agree.

Covered by `test/services/payment.coffee`, testing
`buildOutstandingAllocation` directly (it is pure — no Stripe key needed,
unlike the route itself, which requires `STRIPE_SECRET_KEY` to reach this
code at all):
- "a corrupt month is excluded from the allocation entirely" — a corrupt
  and a non-corrupt month in, only the non-corrupt one in the allocation.
- "ymList and description only name payable months".
- "with no corrupt months, every month is allocated" — the common case is
  unaffected.

Verified by reverting the filter (`payableMonths = outstanding.months`,
no `.filter`): the ymList/description test fails, showing both months
instead of one.

## Symptom

`computeOutstanding` reports a corrupt month with `outstanding: 0` rather
than dropping it (so the dashboard can flag it — see bug docs around
`money.coffee`/`period.coffee`'s corruption handling). "Pay everything
outstanding" built its Stripe allocation from every month in that list,
corrupt or not. When the webhook or client confirm later replayed that
allocation, it recorded a `payment-made` event — for $0, but still an
event — against a month nobody can currently compute the meaning of.

## Reproduction

1. Get a month into a corrupt state (e.g. an `override` event with a
   non-finite `new_value` — see the "a corrupt month is flagged, not
   quietly dropped" test in `test/services/period.coffee`).
2. `POST /payment/create-intent` with no year/month (the "pay everything"
   flow) and an amount matching `computeOutstanding().total`.
3. Inspect the intent's metadata / trigger the webhook.

Expected: the corrupt month is never part of the allocation.
Actual (before the fix): it's included with `amount: 0`, and a
`payment-made` event lands on it once the intent settles.

## Risk

Low. This only removes corrupt months from a plan that could not have
priced them correctly anyway (`outstanding` is forced to 0 for a corrupt
month specifically because nothing can be billed there). The `money.dollars`
normalization and `money.cents` substitution are equivalent to the prior
arithmetic for any already-valid amount; they add null-safety and prevent
`amount` from carrying more precision through the pipeline than the app's
money model allows anywhere else.
