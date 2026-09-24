# Bug 55 — Timer stop writes a legacy table nothing reads, on the wrong side of the commit

**Reported:** 2026-09-24 by architectural review
**Status:** resolved 2026-09-24

## Resolution

Removed `recalculateFor` and its call from `lib/services/timer.coffee`.
`workLogModel.createWorkLog` already emits the `work-reported` event that
`period.coffee`'s fold reads (bug 06) — nothing further was needed for the
rent period to reflect a timer-sourced session.

Covered by `test/services/timer.coffee`:
- "a 90-minute lyndzie session shows up in computeMonth's hours_worked" —
  seeds a session's timeline directly (no real-time sleep) and asserts the
  event fold credits it, in place of the old `rent_periods`-table check.
- "stopping a session does not fail even if the legacy rent_periods table is
  gone" — drops `rent_periods` and asserts `stopTimer` still succeeds.
  Reverting the fix reproduces the exact failure mode this bug describes:
  `Error: no such table: rent_periods`, thrown from
  `rentService.createOrUpdateRentPeriod` after the work log had already
  committed.

`rentService` (`lib/services/rent.coffee`) is not dead: `lib/routes/work.coffee`
still calls `createOrUpdateRentPeriod` on `PUT`/`DELETE /work-logs` (out of
scope for this bug — those routes are not part of the timer path this bug
covers). `getRentSummary` and `recalculateAllRent` also have no remaining
callers found in `lib/` or `static/`, but removing them was out of scope
here; flagging for a follow-up cleanup.

## Symptom

None directly visible — this was found by code review, not a report. The
legacy write was silently redundant and a latent reliability risk: a stop
that had done its real job (work log + event) could still come back as a
500 if the legacy `rent_periods` write failed for any reason (a locked
table, a schema mismatch, `rent_configuration` missing a row it expects).

## Reproduction

1. Break the legacy write path (e.g. drop `rent_periods`, or induce any
   error in `rentModel`/`rentConfiguration`).
2. Complete a timer session past the minimum duration.

Expected: the stop succeeds — the work log and its event already committed.
Actual (before the fix): `stopTimer` rejects, the client sees a 500, despite
the work having already been recorded correctly.

## Root cause

`finishSession` in `lib/services/timer.coffee` called `recalculateFor`
after `workLogModel.createWorkLog`, which called
`rentService.createOrUpdateRentPeriod` — a read-modify-write against the
legacy `rent_periods` table. That table has had no authoritative reader
since the event-sourced model landed
(`migrations/2026-09-23_130000_disable_recurring_scheduler.coffee`'s
comment: "nothing authoritative reads" it). Two problems stacked:

1. **Redundant.** `createWorkLog` already emits the `work-reported` event
   the dashboard's fold reads (bug 06); the legacy write changed nothing
   any route serves.
2. **Ordered wrong.** It ran after the work log (the actually-important
   write) had committed, so any failure in the legacy path turned a
   successful stop into a 500 — the opposite of "fail before you commit
   the thing that matters."

## Risk

Low. The removed call wrote to a table with no readers; nothing in the
route responses changed. Verified by reverting the fix and confirming the
new test reproduces the exact crash this bug describes.
