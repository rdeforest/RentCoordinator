# Bug 06 — Work hours never credit rent (event model)

**Reported:** 2026-08-15 by codebase audit
**Status:** fixed 2026-08-17 (create path)

## Resolution

`workLogModel.createWorkLog` now emits a `work-reported` event
(`lib/models/work_log.coffee`). Both producers — `POST /work-logs` and the
timer's `stopTimer` — go through that single function, so both are covered
by one change. The event reuses the work_log `id` as its own id (the seed
migration's convention), giving a one-log-⟺-one-event invariant, no
double-count with already-seeded historical logs, and a stable handle for
future edit/delete reversals. Actor is derived from the `worker` field via
`config.WORKER_IDENTITY` (lyndzie → tenant, robert → landlord); only tenant
hours credit. Regression test: `test/integration/work-credit.coffee`.

**Delete** is now handled too — see **bug 08** (fixed 2026-08-17); it emits
a `deleted` event targeting the work-reported event.

**Still open:** *editing* a work log does not yet adjust the credit. Edit
needs a compensating `edited` event against the work-reported event (now
findable by shared id, following the same pattern as the delete reversal).
Because create now emits, this staleness case newly *matters* — track it as
a follow-up.

## Symptom

Nobody's logged work ever reduces the rent shown on the dashboard.
Lyndzie can log hours all month and the amount due stays at the full
$1,600 (minus whatever overrides exist). This is the live cause of the
old "Lyndzie's 48.75 hours aren't showing up" complaint (bug 04).

## Reproduction

1. Log work for lyndzie via the timer or `POST /work-logs` for the
   current month.
2. Load `/rent`.
3. Look at the month's `hours_worked` and `amount_due`.

Expected: `hours_worked` reflects the logged hours; `amount_due` drops
by `hours_applied * 50`.
Actual: `hours_worked` is 0; `amount_due` is unchanged.

## Root cause

The rent dashboard is fully event-sourced. `period.coffee::computeMonth`
credits hours only from `work-reported` events:

```
for e in monthEvents when e.actor is 'tenant'
  switch e.action
    when 'work-reported' then hours_worked += e.payload.hours   # period.coffee:71
```

But nothing in the codebase ever emits a `work-reported` event. Grepping
for the string finds only that consumer line plus two comments — no
producer. Work logging writes exclusively to the legacy `work_logs` /
`rent_periods` tables: `lib/routes/work.coffee` calls
`rentService.createOrUpdateRentPeriod`, and `lib/services/timer.coffee`
calls `workLogModel.createWorkLog`. The events table never hears about
the work, so `hours_worked` is always 0 in the view.

Bug 04's old suspects no longer apply: `getWorkLogs` now matches
`LOWER(worker) = LOWER(?)` (work_log.coffee:29), and the dashboard no
longer runs the legacy `calculateRent` path — it reads from the event
fold. The remaining defect is purely that no event is ever produced.

## Proposed fix

Emit a `work-reported` event whenever a work log is created, updated, or
deleted, so the fold in `period.coffee` sees the hours. Concretely:

- On create (`work.coffee` POST `/work-logs` and the `stopTimer` path in
  `timer.coffee`), call `eventsModel.recordEvent` with
  `actor: 'tenant'`, `action: 'work-reported'`,
  `effective_for` set to the log's month (`YYYY-MM`), and
  `payload: { hours, work_log_id, worker, ... }`. Note `computeMonth`
  reads `payload.hours` (hours, not minutes), so convert from the
  stored duration.
- On update, emit a compensating pair (reverse the old hours, report the
  new) or an `edited` event targeting the original, per the event model
  in `docs/event-model.md`.
- On delete, emit the reversal (see bug 08, which also has to be fixed
  before delete works at all).

Store the emitted event's id (or the `work_log_id`) so the update/delete
reversals can find what to compensate.

## Risk

This is the core of the rent math, so a wrong sign or a hours/minutes
mixup silently mis-bills. The legacy `rent_periods` writes are still
happening in parallel — decide whether they stay as a shadow or get
removed, or the two representations will drift. Retroactive credit
(`period.coffee:78-85`) folds forward across months, so backfilling
events for historical logs will recompute prior months; verify carryover
and shortfall against known-good figures before trusting it.
