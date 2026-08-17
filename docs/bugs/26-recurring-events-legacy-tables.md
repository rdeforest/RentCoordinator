# Bug 26 — Recurring-events scheduler writes the legacy tables (invisible to dashboard)

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

The recurring-events scheduler runs daily and reports success, but its
monthly rent-due and recalculation work never shows up anywhere users
look. The dashboard and period math don't reflect it.

## Reproduction

1. Enable a `rent_due` or `recalculation` recurring event.
2. Let the daily scheduler fire (or call `triggerManualProcessing`).
3. Load the rent dashboard for the affected month.

Expected: the automated rent-due entry / recalculation is reflected in the
period.
Actual: nothing changes on the dashboard; the effect is only in tables the
dashboard no longer reads.

## Root cause

The dashboard and period math are now driven entirely by the
event-sourced `events` table (`lib/services/period.coffee`,
`period_viewer.coffee`). But the recurring-events scheduler still targets
the legacy path:

- `processRentDueEvent` creates a row via `rentModel.createRentEvent`
  (`lib/services/recurring_events.coffee:133`) — the legacy `rent_events`
  table.
- `processGenericEvent` does the same (`:172`).
- `processRecalculationEvent` calls `rentService.recalculateAllRent()`
  (`:155`) — the legacy calculation.

None of these emit `events`-table events, so the source of truth for the
dashboard never sees them. The scheduler's output is written to tables
nothing reads.

Separately, `processGenericEvent` (`:160-184`) has no duplicate guard. The
`rent_due` path checks `rentDueExists` first (`:111-119`) and skips if a
matching event is already present, but the generic path always inserts. A
double-fire of the scheduler duplicates generic events.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Decide whether this subsystem is still wanted:

- If yes: port the processors to emit `events`-table events (via the same
  `eventsModel.recordEvent` path the rest of the event model uses) so the
  dashboard sees them, and add an idempotency guard to
  `processGenericEvent` matching the `rentDueExists` check.
- If no: remove the scheduler and its processors so they stop writing to a
  table nothing reads.

This is the same structural theme as bug 06 — two parallel rent models,
one live and one legacy, with writes still going to the dead one.

## Risk

Moderate. Porting to the event model changes what the automated jobs
produce and needs to be validated against `computeMonth`/`computeOutstanding`
so a monthly rent-due event isn't double-counted alongside whatever the
event model already derives. Removal is lower risk but should confirm no
other consumer reads the rows these jobs write.
