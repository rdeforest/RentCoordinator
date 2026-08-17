# Bug 40 — calculateNextDueDate month/year math is fragile

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

For a monthly recurring event with `day_of_month = 31`, the next-due date
can land in the wrong month. For yearly events, the configured
`day_of_month`/`month` are ignored entirely.

## Reproduction

N/A — latent; not hit today (rent recurs on day 1). Triggered by any
recurring event configured with `day_of_month` past the shortest month,
or any `yearly` event that expects a specific month/day.

## Root cause

`lib/services/recurring_events.coffee:26-39`.

Monthly (`:27-34`) does `nextDate.setDate(day_of_month or 1)`. In a
30-day month, `setDate(31)` rolls forward into the next month instead of
clamping to the 30th, skewing the computed next-due date.

Yearly (`:36-39`) ignores `day_of_month` and `month` completely — it just
adds one year to `fromDate`, so the due date drifts to whatever day the
computation happened to run.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Monthly: clamp `day_of_month` to the last valid day of the target month
before setting it (compute month-end, take the min). Yearly: build the
date from the configured `month`/`day_of_month`, then advance the year
relative to `fromDate` — do not derive the day from `fromDate`.

## Risk

Low / edge-case. No current config exercises either path.
