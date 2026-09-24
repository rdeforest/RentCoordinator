# Bug 51 — Payments entered by the landlord never count

**Reported:** 2026-09-24 by architectural review
**Status:** resolved 2026-09-24

## Resolution

`computeMonth` in `lib/services/period.coffee` now sums `payment-made`
regardless of `actor`. The tenant-only filter stays on `work-reported` —
only the tenant's hours earn rent credit.

Covered by `test/services/period.coffee` ("a landlord-recorded payment still
counts toward amount_paid (bug 51)") and
`test/integration/rent-landlord-payment.coffee` (as robert@defore.st, POST
`/rent/events` type `payment` → GET `/rent/period` shows it in
`amount_paid`).

Updated `docs/event-model.md`: `payment-made`'s actor column now reads
`either`, with a note that `actor` is provenance, not a fold filter, except
for `work-reported`.

## Symptom

A payment the landlord recorded by hand through the "Rent Events" table
(`POST /rent/events`, type `payment`) never showed up as paid on the
dashboard, even though the event was created successfully and visible in
the events list.

## Reproduction

1. As robert@defore.st, `POST /rent/events` with
   `{ type: 'payment', year, month, amount, description }`.
2. `GET /rent/period/:year/:month`.

Expected: `amount_paid` includes the recorded amount.
Actual: `amount_paid` is unchanged — the event is invisible to the calc.

## Root cause

`POST /rent/events` (`lib/routes/rent.coffee`) stamps
`actorFromRequest req, 'landlord'` on every event it creates, including
payments. `POST /rent/payment` — the other path that records a payment —
defaults `actor` to `'tenant'`. `computeMonth` summed `payment-made` only
`when e.actor is 'tenant'`, so the two UI paths for recording a payment
disagreed about whether the result counted: the same action, `payment-made`,
was trusted from one endpoint and silently dropped from the other.

`actor` records who performed the action (provenance, useful for the audit
trail and for `work-reported`, where only the tenant's own hours should earn
credit). It was never meant to gate which payments are real money.

## Risk

None identified — this only adds previously-dropped landlord-recorded
payments into the sum; it does not change how tenant-recorded payments are
handled.
