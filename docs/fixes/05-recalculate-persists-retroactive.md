# Fix 5 — `recalculateAllRent` retroactive logic discarded by the route

## What's broken

`recalculateAllRent` in `lib/services/rent.coffee` computes a careful
retroactive-credit model with `retroactive_adjustment` and
`cumulative_shortfall`, accounting for months where excess hours can
catch up on past shortfalls.

The route immediately throws that work away:

```coffee
app.post '/rent/recalculate-all', (req, res) ->
  periods = await rentService.recalculateAllRent()
  for period in periods
    await rentService.createOrUpdateRentPeriod period.year, period.month
    # ↑ re-runs calculateRent from scratch with NO retroactive logic
  ...
```

`createOrUpdateRentPeriod` calls the simpler `calculateRent`, which has
no concept of retroactive credit. So the carefully-computed periods
returned by `recalculateAllRent` are discarded.

## The fix

Move the persistence into `recalculateAllRent` itself, or change the
route to persist the returned periods directly without re-calculating.

### Option A (preferred): persist within the service

In `lib/services/rent.coffee`, add at the end of `recalculateAllRent`,
just before `return periods`:

```coffee
  # Persist each computed period, respecting manual overrides
  for period in periods
    existing = await rentModel.getRentPeriod period.year, period.month

    updates =
      hours_worked:        period.hours_worked
      hours_from_previous: period.hours_from_previous
      hours_to_next:       period.hours_to_next
      discount_applied:    period.total_discount
      manual_adjustments:  period.manual_adjustments

    unless existing?.amount_due_manual
      updates.amount_due = period.amount_due

    unless existing?.amount_paid_manual
      updates.amount_paid = Math.abs period.amount_paid

    if existing
      await rentModel.updateRentPeriod period.year, period.month, updates
    else
      await rentModel.createRentPeriod Object.assign {}, period, updates

  return periods
```

Then simplify the route:

```coffee
app.post '/rent/recalculate-all', (req, res) ->
  try
    periods = await rentService.recalculateAllRent()
    res.json
      message:         'Recalculation complete'
      periods_updated: periods.length
      periods:         periods
  catch err
    logger.error 'rent.recalculateAll', err, {}, req.id
    res.status(500).json error: err.message
```

The route no longer needs to know about persistence.

## How to verify

1. Create a multi-month scenario by hand. The clearest test:
   - Month A: 4 hours worked → shortfall of (8-4)×$50 = $200
   - Month B: 16 hours worked → 8 applied to month B, 8 leftover

   With current (buggy) behavior, the 8 leftover hours don't retire
   month A's shortfall.

   With the fix, month A's shortfall should drop by min(8×50, 200) = $200.

2. Add a unit test for this scenario in `test/services/rent.coffee`.

## Risk

**Medium-low.** This changes how rent is calculated, so any prior
"recalculate all" run that quietly produced wrong numbers will now
produce different numbers. That's the intent, but be ready for the
period values to shift.

Mitigation: dump the current state before applying, and diff after:

```bash
sqlite3 -header -csv tenant-coordinator.db \
  "SELECT year, month, hours_worked, discount_applied, amount_due FROM rent_periods ORDER BY year, month" \
  > /tmp/rent_before.csv

:# ...apply fix, restart, hit Recalculate All...

sqlite3 -header -csv tenant-coordinator.db \
  "SELECT year, month, hours_worked, discount_applied, amount_due FROM rent_periods ORDER BY year, month" \
  > /tmp/rent_after.csv

diff /tmp/rent_before.csv /tmp/rent_after.csv
```

Any unexpected changes are worth understanding before showing the new
totals to anyone.
