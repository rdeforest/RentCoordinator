# Bug 05 — `recalculateAllRent` retroactive logic discarded

**Reported:** 2026-05-19 (discovered during review)
**Status:** resolved 2026-09-23

## Resolution

Resolved by the event model, though not in the shape this file proposed. `computeMonth` carries `cumulative_shortfall` forward and retires it with `retroactive_credit` in the later month, rather than rewriting the earlier month's stored value — an append-only log does not rewrite history. Demonstrated: January with 4 hours owes $1,400 and carries a $200 shortfall; February with 16 hours takes a $200 retroactive credit, owes $1,000, and carries nothing forward. Economically the outcome this file asked for.

## Symptom

Clicking "Recalculate All" doesn't actually apply the retroactive-credit
logic that the service computes. Months with excess hours don't retire
earlier shortfalls the way the comments in `recalculateAllRent` suggest
they should.

## Reproduction

1. Manually create a multi-month scenario:
   - Month A: 4 hours worked (shortfall of $200)
   - Month B: 16 hours worked (8 leftover after own month)
2. Click "Recalculate All".
3. Inspect Month A's `discount_applied` or `amount_due`.

Expected: Month A's shortfall reduced by $200 from Month B's excess.
Actual: Month A unchanged.

## Root cause

The route hands off the carefully-computed periods from
`recalculateAllRent` to `createOrUpdateRentPeriod`, which re-runs the
simpler `calculateRent` per-month — discarding the retroactive logic.

## Proposed fix

See [fixes/05-recalculate-persists-retroactive.md](../fixes/05-recalculate-persists-retroactive.md).
