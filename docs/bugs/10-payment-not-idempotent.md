# Bug 10 — Payment confirmation is not idempotent (double-credit)

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

A single Stripe payment can be recorded against the ledger more than
once, crediting the tenant twice for money paid once. The month reads
PAID (or over-paid) off one real transaction.

## Reproduction

1. Complete a payment so its PaymentIntent reaches `succeeded`.
2. Trigger confirmation twice for the same intent — e.g. the client
   retries, the browser refreshes onto the confirm path, or a webhook
   (bug 09) is added on top of the existing client poll.
3. Load `/rent`.

Expected: one `payment-made` event; amount counted once.
Actual: two `payment-made` events for the same
`stripe_payment_intent_id`; amount counted twice.

## Root cause

`confirmPayment` and `confirmPaymentAllocated`
(payment.coffee:46-139) re-retrieve the PaymentIntent and, whenever its
status is `succeeded`, unconditionally call `eventsModel.recordEvent`
with `action: 'payment-made'`. The `stripe_payment_intent_id` is written
into the payload but never read back before inserting — grepping for it
finds only writes, no lookup. Nothing checks whether an event for that
intent already exists.

The fold sums every `payment-made` for the month:

```
when 'payment-made' then amount_paid += e.payload.amount   # period.coffee:72
```

So each confirmation that reaches `succeeded` adds another summand. Two
confirmations for the same intent → the amount is counted twice.

## Proposed fix

Make recording idempotent on `stripe_payment_intent_id`. Before writing,
look up whether a `payment-made` event already carries that intent id
(add a query to `lib/models/events.coffee`, e.g. scan
`payload->>'stripe_payment_intent_id'` or maintain an index/column for
it) and no-op if one exists. For `confirmPaymentAllocated`, which writes
several events under one intent id, guard the whole allocation as a unit
so a retry doesn't re-emit the set.

## Risk

The check-then-insert is a race if two confirmations run concurrently
(client retry racing a webhook); do the lookup and inserts inside a
single transaction, or add a uniqueness constraint that lets the second
writer fail cleanly. Scanning JSON payloads for the intent id is
O(events) unless indexed — fine at this project's scale, but note it.
Fixing this is a prerequisite for safely adding the webhook in bug 09.
