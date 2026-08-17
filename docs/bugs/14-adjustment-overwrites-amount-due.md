# Bug 14 — Adjustment/manual rent events overwrite amount_due instead of adding

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

Adding an "adjustment" or "manual" rent event for a month replaces that
month's amount due with the event amount instead of adjusting it. A $100
late fee on a month calculated at $1,600 leaves the month owing $100, not
$1,700. Worse, once the event lands, the month reads as manually pinned,
so the dashboard displays $100 as the amount due for that month.

## Reproduction

1. Pick a month whose calculated `amount_due` is $1,600 (no work credits).
2. Add a rent event: type `adjustment`, amount `100`, any description.
3. Reload `/rent` and look at that month's row.

Expected: amount due becomes $1,700 (base + adjustment).
Actual: amount due becomes $100, and the row is now treated as an override
(`display_amount_due` also shows $100).

## Root cause

`POST /rent/events` in `lib/routes/rent.coffee:271-287` maps both
`adjustment` and `manual` to the `override` action and builds a payload of
`{ target_kind: 'period-field', target: {…, field: 'amount_due'}, new_value:
parseFloat amount }`.

`computeMonth` in `lib/services/period.coffee:92-95` applies that as an
absolute replacement:

```coffee
amount_due          = e.payload.new_value
amount_due_override = true
```

So the event's amount becomes the entire amount due, and because
`amount_due_override` flips true, `display_amount_due` (period.coffee:118)
returns that pinned value too. The legacy model in `lib/services/rent.coffee`
treated adjustments as additive (`baseAmountDue + manualAdjustments`); that
additive semantic was lost when the write path was routed through the
absolute-override event kind.

## Proposed fix

(No docs/fixes/ file exists yet.)

Give additive adjustments their own event kind — e.g. an `adjustment`
action carrying `{ field: 'amount_due', delta: amount }` — and have
`computeMonth` sum those deltas into `amount_due_calculated` before the
override loop runs, rather than folding them through the period-field
override path. Reserve `override` (and `amount_due_override`) for the case
where the landlord genuinely wants to pin an absolute value. Map only the
`manual` type (if it is meant to be an absolute pin) to `override`; map
`adjustment` to the new additive kind.

## Risk

Changing the event vocabulary means any adjustment/manual events already
recorded in production are stored as `override` events and will keep
replacing rather than adding. A migration (or a one-time audit of existing
events) is needed to reclassify them, or the fix has to keep interpreting
old `override`-from-adjustment events the old way. Touching `computeMonth`
also touches every period's math, so the integration tests around rent
calculation must be run.
