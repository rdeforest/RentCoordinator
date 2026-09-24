# Bug 56 — An adjustment on a month with an override is accepted and ignored

**Reported:** 2026-09-24 by architectural review
**Status:** resolved 2026-09-24

## Resolution

`computeMonth` in `lib/services/period.coffee` now finds the latest
`override` targeting `amount_due` for the month (by `occurred_at`) and
treats adjustments recorded after it as applying on top of the pin:
`amount_due = override.new_value + Σ(later adjustment deltas)`. Adjustments
from before the latest override are superseded by it, matching the existing
"an override wins over an adjustment on the same month" behavior for that
case.

Updated `test/services/period.coffee`:
- "an override wins over an adjustment made before it (bug 56)" — renamed
  from the old "same month" test, now with an explicit earlier `occurred_at`
  on the adjustment so "before" is unambiguous. Same assertions as before.
- "an adjustment made after an override applies on top of the pin (bug 56)"
  — new: a $500 pin followed by a $100 late fee comes out to $600, not $500.

Documented in `docs/event-model.md` under "Override vs. adjustment ordering
(2026-09-24, bug 56)".

## Symptom

Once a month had an `override` on it, any later `adjustment` (e.g. a late
fee added after the pin) was accepted by `POST /rent/events` — 200, event
recorded — but had no effect on `amount_due` at all.

## Reproduction

1. Pin a month: `PUT /rent/period/:year/:month { amount_due: 500 }`.
2. Add a late fee: `POST /rent/events { type: 'adjustment', amount: 100, ... }`.
3. `GET /rent/period/:year/:month`.

Expected: `amount_due` is 600.
Actual: `amount_due` stayed 500 — the adjustment event exists but is
invisible to the calc.

## Root cause

`computeMonth` summed every `adjustment` on the month into
`amount_due_calculated`, then — if *any* `override` existed for the month —
replaced `amount_due` wholesale with the override's pinned value. The
replacement did not care when the override happened relative to the
adjustments; it discarded all of them, always, the moment a pin existed.
There was no way to add a late fee to an already-pinned month without either
computing a new absolute number by hand (losing the adjustment's own
identity in the event log) or having the fee silently vanish.

## Risk

Low — this only changes behavior for months that have both an override and
an adjustment recorded after it, which previously produced a wrong,
silently-ignored result. Months with adjustments before their override, or
with no override at all, are unaffected.
