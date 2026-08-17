# Bug 09 — ACH payments are never recorded (no webhook)

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

The tenant completes a bank payment, the bank account is debited, but
the rent ledger still shows the month UNPAID. No `payment-made` event is
ever written.

## Reproduction

1. Pay rent through the Stripe ACH flow on `/payment`.
2. Wait for the client's status polling to finish and redirect.
3. Load `/rent`.

Expected: the month reflects the payment (PAID or PARTIAL).
Actual: still UNPAID; no `payment-made` event exists for the month.

## Root cause

Payments use ACH:
`payment_method_types: ['us_bank_account']` (payment.coffee:28). ACH
debits do not settle synchronously — at confirm time the PaymentIntent
returns status `processing` and settles 4–5 business days later.

The only code that records a `payment-made` event is
`confirmPayment` / `confirmPaymentAllocated`, and both bail unless the
status is already `succeeded`:

```
unless paymentIntent.status is 'succeeded'
  throw new Error "Payment not successful: #{paymentIntent.status}"   # payment.coffee:50, 83
```

The client (`static/coffee/payment.coffee:233-252`) polls
`/payment/status/:id` roughly 30 times at 2s intervals (~60s), then —
still seeing `processing` — shows "Payment is processing, check back
later" and redirects to `/rent`. By the time the ACH actually settles
days later, nothing is watching.

There is no Stripe webhook anywhere in the codebase: grepping for
`webhook`, `constructEvent`, and `payment_intent.succeeded` returns
nothing. So the transition to `succeeded` is never observed and no event
is ever recorded. The bank is debited; the ledger stays UNPAID
indefinitely.

## Proposed fix

Add a Stripe webhook endpoint (e.g. `POST /payment/webhook`) that:

- verifies the signature with `stripe.webhooks.constructEvent` and the
  endpoint signing secret,
- handles `payment_intent.succeeded`, and
- records the `payment-made` event(s) server-side — reusing the same
  event-writing logic as `confirmPaymentAllocated`, keyed off the
  PaymentIntent's stored month/allocation metadata.

Treat the client-side poll as best-effort UI only; the webhook is the
authoritative record of settlement.

## Risk

Webhooks arrive at-least-once and can be replayed, so recording on the
webhook makes idempotency mandatory — see bug 10; without it the same
settled payment can be credited more than once. The webhook route must
bypass session auth (Stripe won't send a cookie) but must instead verify
the Stripe signature, or it becomes an unauthenticated way to write
payment events. The endpoint needs the raw request body for signature
verification, so it can't sit behind a JSON body parser that has already
consumed the stream.
