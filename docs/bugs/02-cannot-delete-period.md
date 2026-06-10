# Bug 02 — Cannot delete rent period (FK constraint)

**Reported:** 2026-05-19 (long-standing)
**Status:** fix-proposed

## Symptom

Attempting to delete last month's rent period via the UI returns a 500
error mentioning a FOREIGN KEY constraint failure.

## Reproduction

1. Let the server run long enough for the recurring-events scheduler to
   process at least one month (this happens on startup and daily).
2. Hit `DELETE /rent/period/:year/:month` on any month that's been
   processed, or click the Delete button on that row.

Expected: period and associated events removed.
Actual: 500 error, FK constraint failure.

## Root cause

Two tables reference `rent_periods(id)` as `NOT NULL`:

- `rent_events.period_id` — handled in `deleteRentPeriod` by manual cleanup
- `recurring_event_logs.period_id` — **not** handled

Neither FK has `ON DELETE CASCADE`. The recurring-events scheduler
inserts a row into `recurring_event_logs` every time it processes a
month, so any month that's been around for a day or two will have
blocking rows here.

## Proposed fix

See [fixes/02-cascade-delete-migration.md](../fixes/02-cascade-delete-migration.md)
and [fixes/02b-schema-patch.md](../fixes/02b-schema-patch.md).
