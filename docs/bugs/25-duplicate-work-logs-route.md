# Bug 25 — Duplicate GET /work-logs registration; richer handler is dead code

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

The work-log view never shows completed or cancelled timer sessions,
even though a handler exists that is supposed to merge them into the list.
That handler never runs.

## Reproduction

1. Complete or cancel a timer session (goes into `work_sessions`, not
   `work_logs`).
2. Load the work page and fetch `GET /work-logs`.

Expected (per the `lib/routes/work.coffee` handler): the response includes
the timer session rendered as a work log, de-duped against traditional
logs.
Actual: only rows from `work_logs` appear; the timer session is absent.

## Root cause

`GET /work-logs` is registered twice:

- `lib/routing.coffee:221` — a simple handler that returns
  `workLogModel.getWorkLogs` only. This is registered during
  `routing.setup`, before the route modules are wired.
- `lib/routes/work.coffee:8` — a richer handler that pulls
  `work_sessions`, converts completed/cancelled sessions to work logs,
  concatenates them with traditional logs, de-dupes by id, and sorts. This
  is registered later via `workRoutes.setup app` (`routing.coffee:236`).

Express dispatches `GET` requests to the first matching route in
registration order. The `routing.coffee` handler is registered first, so
it always wins; the `work.coffee` handler is never reached. Whatever the
richer handler was meant to provide — timer sessions surfacing in the
work-log view — silently doesn't happen.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Delete one of the two registrations. Decide which behavior is intended:

- If timer sessions should appear in the work-log list, remove the
  `routing.coffee:221` block and let the `work.coffee` handler serve the
  route.
- If the simple raw-log behavior is what's wanted, remove the handler in
  `work.coffee` (and its now-dead session-merging code).

Having both is the actual defect — the route can only have one meaning.

## Risk

Low to moderate, depending on which handler is chosen. Removing the
`routing.coffee` shadow changes the response shape clients receive (timer
sessions start appearing), so the frontend rendering should be checked
against the merged list. No schema change either way.
