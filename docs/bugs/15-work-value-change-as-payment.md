# Bug 15 — work_value_change events silently recorded as payments

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

Submitting a "Work Value Change" rent event records a payment for the same
amount. The month then shows that amount as paid even though no money
changed hands.

## Reproduction

1. Open the Add Rent Event modal on `/rent`.
2. Choose type "Work Value Change", amount `200`, any description.
3. Submit, then look at that month's amount paid.

Expected: some work-value adjustment (or a rejection — the type isn't
really wired up).
Actual: $200 is added to the month's amount paid, as if a $200 payment was
made.

## Root cause

The type dropdown in `static/rent.html` offers `work_value_change` (the
client even formats it, `static/coffee/rent.coffee:701`), but the server's
type→action map in `lib/routes/rent.coffee:271-275` only handles three of
the four:

```coffee
action = switch type
  when 'payment'    then 'payment-made'
  when 'adjustment' then 'override'
  when 'manual'     then 'override'
  else 'payment-made'   # safest fallback
```

`work_value_change` hits the `else` and becomes `payment-made`. The payload
branch (rent.coffee:277-287) then builds a payment payload, and
`computeMonth` (period.coffee:72) sums it into `amount_paid`. The
"safest fallback" is the opposite of safe: it fabricates a payment.

## Proposed fix

(No docs/fixes/ file exists yet.)

Stop defaulting unknown types to a payment. Reject any type not explicitly
handled with a 400 (`error: "Unknown event type: #{type}"`). Then decide
what `work_value_change` should actually do — either give it a real mapping
(likely the additive-adjustment kind from bug 14, applied to the work-value
side) or remove the option from `static/rent.html` and the client formatter
until it's implemented. Leaving a selectable type that silently misfiles is
worse than not offering it.

## Risk

Low for the rejection itself. The main risk is data already written: any
`work_value_change` submitted before the fix is sitting in the events table
as a `payment-made` and is inflating amount-paid totals. Those need to be
found and corrected separately — the fix stops new ones but doesn't undo
old ones.
