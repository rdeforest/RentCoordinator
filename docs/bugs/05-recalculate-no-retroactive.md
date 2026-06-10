# Bug 05 — `recalculateAllRent` retroactive logic discarded

**Reported:** 2026-05-19 (discovered during review)
**Status:** fix-proposed

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
