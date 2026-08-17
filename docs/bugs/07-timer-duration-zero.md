# Bug 07 — Timer-stopped work logs always save duration 0

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

Work logged through the timer (start → stop) shows up with a duration of
0 minutes. Manually entered work logs are fine; only timer-created ones
are wrong. Zero minutes means zero rent credit even once the event model
is wired up.

## Reproduction

1. Start the timer for a worker, let it run long enough to clear
   `MIN_WORK_LOG_DURATION` (60s in prod), stop it.
2. Load `/work-logs` and find the created log.

Expected: duration reflects the elapsed time.
Actual: duration is 0.

## Root cause

`stopTimer` computes the correct duration and then throws it away when
writing the log:

```
duration = await workSessionModel.calculateSessionDuration currentSession.id   # timer.coffee:68
if completed and duration >= config.MIN_WORK_LOG_DURATION
  workLog = await workLogModel.createWorkLog(
    await workSessionModel.sessionToWorkLog currentSession                      # timer.coffee:72
  )
```

The gate uses the freshly computed `duration`, but the log is built from
`sessionToWorkLog currentSession`. `currentSession` came from
`getCurrentSession`, a raw `SELECT s.*` (work_session.coffee:65), so its
`total_duration` is the literal `0` written at INSERT
(work_session.coffee:12) and never UPDATEd anywhere. `sessionToWorkLog`
then does `duration: Math.round session.total_duration / 60`
(work_session.coffee:151) = `Math.round 0 / 60` = 0.

The `total_duration` column is effectively dead — duration is only ever
recomputed on the fly by `calculateSessionDuration` from the
`work_events` rows; nothing persists it back to the session row.

## Proposed fix

Feed the already-computed duration into the log instead of reading the
stale column. Two options:

- Pass `duration` into `sessionToWorkLog` and have it use that value
  rather than `session.total_duration`, or
- Have `sessionToWorkLog` call `calculateSessionDuration session.id`
  itself and convert seconds → minutes.

Either way, drop the dependency on `session.total_duration`; that column
is never maintained. If nothing else needs it, consider removing it so
the next reader isn't misled.

## Risk

`calculateSessionDuration` returns seconds; `sessionToWorkLog` divides by
60 for minutes — keep the unit conversion in exactly one place or the
value comes out 60x off. Rounding at the seconds→minutes boundary can
push a just-over-threshold session to 0 or 1 minute; the
`MIN_WORK_LOG_DURATION` gate is in seconds, so a 60-second session
rounds to 1 minute, which is fine, but confirm the two thresholds stay
consistent.
