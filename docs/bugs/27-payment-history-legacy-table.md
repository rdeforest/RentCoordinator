# Bug 27 — Payment-history page reads the legacy rent_events table

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

The "Payment Management" page shows no payment history (or only stale
entries), even though real Stripe/ACH payments have gone through. Its
"reassign" and "delete payment" actions appear to work but don't change any
outstanding balance.

## Reproduction

1. Make a rent payment through the Stripe/ACH flow.
2. Open the Payment Management page (`static/coffee/payments.coffee`,
   backed by `GET /v1/api/payments`).

Expected: the payment appears in the list.
Actual: the list is empty (or shows only old legacy entries); the real
payment is missing.

## Root cause

Two payment models that don't meet:

- `lib/routes/payments.coffee:11-14` reads
  `rentModel.getAllRentEvents()` and filters to `event.type is 'payment'` —
  the legacy `rent_events` table.
- Every real payment is written by `lib/services/payment.coffee` to the
  event-sourced `events` table with `action: 'payment-made'`
  (`confirmPayment` at `:57-67`, `confirmPaymentAllocated` at `:96-106`).
  Nothing writes payment rows to `rent_events` anymore.

So the history UI queries a table that real payments never land in. Worse,
its mutating actions operate on the legacy table too: `reassign`
(`:42-84`) and `delete` (`:87-108`) update/delete `rent_events` rows and
call `rentService.calculateRent`, none of which touches the real ledger.
The outstanding balance is computed from `events` (`period.coffee`
`computeOutstanding`), so "delete payment" here has no effect on what the
tenant actually owes.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Point the history UI at the same event-sourced source the balance math
uses. Read payment events from the `events` table
(`action = 'payment-made'`) and make reassign/delete emit corresponding
events (e.g. a reversal/void event) rather than mutating `rent_events`.
Alternatively, reconcile the two models so payments land in one place — but
the event model is the authoritative one, so the history UI should follow
it.

This is the same two-models split as bug 06.

## Risk

Moderate. The delete/reassign actions currently do nothing meaningful to
balances; wiring them to the event model makes them actually move money in
the ledger, so their semantics (what a reversal event means, whether an
allocated multi-month payment can be partially reassigned) need to be
defined before they're exposed. Read-only history migration is lower risk
and can land first.
