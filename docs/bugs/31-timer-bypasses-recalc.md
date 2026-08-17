# Bug 31 — Timer-created work logs bypass rent-period recalculation

**Reported:** 2026-08-15 by codebase audit
**Status:** active

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
