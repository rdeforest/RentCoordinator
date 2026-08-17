# Bug 28 — Recurring-event processing logs hardcode status=success

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

The recurring-event processing log always reports every run as a success.
A run that actually threw an exception and was logged as an error shows up
as "success" with no message and no error details. Failures are invisible
in the logs API.

## Reproduction

1. Cause `processRecurringEvent` to throw (e.g. a malformed event template).
   The catch block at `lib/services/recurring_events.coffee:94-101` writes
   a processing log with `status: 'error'` and an `error_details` message.
2. Read the logs back via `getProcessingLogs`.

Expected: the run shows `status: 'error'` with the message.
Actual: it shows `status: 'success'`, `message: null`,
`error_details: null`.

## Root cause

The `recurring_event_logs` schema only stores `id`,
`recurring_event_id`, `period_id`, `amount`, `processed_at` — see the
`XXX` comment at `lib/models/recurring_events.coffee:189`.

- `createProcessingLog` (`:182-217`) accepts `status`, `message`,
  `error_details`, and `events_created`, but the INSERT (`:192-203`) writes
  none of them — they're dropped on write. The returned object echoes them
  back in memory, but nothing is persisted.
- `getProcessingLogs` (`:219-242`) then hardcodes on read: `status =
  'success'`, `message = null`, `error_details = null`, `events_created =
  []` (`:234-240`).

So regardless of what actually happened, a stored log reads back as a
successful run with no detail. The error path in the service does its job;
the persistence layer discards it.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Persist the outcome. Either extend the `recurring_event_logs` schema with
`status`, `message`, `error_details`, and `events_created` columns and
write/read them, or store the extra fields as a single JSON blob column.
Then have `getProcessingLogs` return the stored values instead of the
hardcoded constants. The migration is straightforward — see
`migrations/README.md` for the manual migration pattern.

## Risk

Low. Additive schema change; existing rows would report a null/unknown
status until backfilled, which is more honest than the current false
"success". No behavior downstream depends on the hardcoded values beyond
the logs API display.
