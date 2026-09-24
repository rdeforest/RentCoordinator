# Bug 31 — Timer-created work logs bypass rent-period recalculation

**Reported:** 2026-08-15 by codebase audit
**Status:** resolved 2026-09-23

## Resolution

`stopTimer` ran the same recalculation the manual work-log routes ran, using
`config.isTenant` (derived from `WORKER_IDENTITY`) rather than a fourth bare
`'lyndzie'` literal.

**2026-09-24 (bug 55):** that recalculation call — `rentService
.createOrUpdateRentPeriod`, writing the legacy `rent_periods` table — has
since been removed from `lib/services/timer.coffee` entirely. It wrote a
table nothing authoritative reads
(`migrations/2026-09-23_130000_disable_recurring_scheduler.coffee`), and it
ran after the work log already committed, so a throw there could 500 a stop
that had already succeeded. `createWorkLog` emits the `work-reported` event
the fold reads on its own (bug 06), so the call was also redundant. See
`docs/bugs/55-timer-legacy-rent-write.md`.

## Symptom

A Lyndzie work session completed via the timer does not update her rent
period. The same work entered through the manual work-log endpoints does.

## Reproduction

1. As lyndzie, start a timer, let it run past the minimum duration, stop
   it. A work log is created.
2. Load the rent period for that month.

Expected: the period reflects the new credited hours.
Actual: unchanged — the timer log never triggered a recalc.

## Root cause

`stopTimer` (`lib/services/timer.coffee:71-75`) writes the log via
`workLogModel.createWorkLog` directly and returns. Unlike the
`POST`/`PUT`/`DELETE /work-logs` handlers
(`lib/routes/work.coffee:96-125`), which call
`rentService.createOrUpdateRentPeriod` for lyndzie logs, the timer path
never recalculates. So the legacy rent period is never updated for
timer-sourced work.

This is a plausible contributor to bug 04 (Lyndzie's hours not appearing
in rent periods), and is compounded by bug 06 (the event model never
sees the timer log) and bug 07 (hours saved as 0).

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

After creating the log in `stopTimer`, for a lyndzie session run the same
recalc/event the route handlers use: derive year/month from the log's
start time and call `rentService.createOrUpdateRentPeriod`. Fixing this
alongside bugs 06 and 07 is worthwhile — they share the same missing
"after a work log lands, update downstream state" step.

## Risk

Low. Adds a recalc call on an existing write path. See bugs 06 and 07 for
the related gaps in the same flow.
