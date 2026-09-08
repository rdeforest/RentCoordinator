# Bug 04 — Lyndzie's work hours not appearing in rent periods

**Reported:** 2026-01-01
**Status:** resolved 2026-08-17 (same root cause as bug 06)

> **Resolution:** the 48.75-hour symptom was bug 06 — nothing emitted a
> `work-reported` event, so the event-sourced dashboard always showed 0
> hours. The old case/timezone suspects below no longer apply. Fixed when
> `createWorkLog` began emitting `work-reported` events (see
> [06](06-work-hours-never-credit.md)).

## Symptom

Lyndzie entered 48.75 hours but they aren't showing up in the rent
periods list.

## Reproduction

(Specific to the production data — the diagnostic queries in the fix
document help identify which suspect applies.)

## Suspected root cause

Two suspects, both addressed by the proposed fix:

1. **Worker-name case sensitivity.** `getWorkLogs` does an exact-match
   filter on `worker`. The rent service requests `worker: 'lyndzie'`.
   Any work logs stored with `Lyndzie`, `LYNDZIE`, or other variants
   are silently excluded.

2. **Timezone slippage at month boundaries.** `calculateRent` does its
   date filter in JavaScript using `new Date(year, month - 1, 1)` for
   local midnight, then parses log `start_time` strings as Dates. If
   logs are stored as UTC ISO strings, evening-Pacific entries on the
   last day of a month appear to fall in the next month.

## Proposed fix

See [fixes/04-missing-work-hours.md](../fixes/04-missing-work-hours.md).
Includes diagnostic SQL queries that nail down which suspect applies
before patching.
