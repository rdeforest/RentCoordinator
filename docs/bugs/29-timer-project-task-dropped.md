# Bug 29 — Timer project_id/task_id are silently dropped

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

Starting a timer with a `project_id` and/or `task_id` appears to accept
them, but the resulting work log always has both fields null. The timer
API advertises a capability it cannot deliver.

## Reproduction

1. `POST /timer/start` with `{ worker, project_id, task_id }`.
2. Stop the timer to generate a work log.
3. Inspect the log: `project_id` and `task_id` are null.

## Root cause

`startTimer(worker, project_id, task_id)` (`lib/services/timer.coffee:8`)
accepts the two IDs but passes neither onward. It calls
`createWorkSession worker` (`lib/models/work_session.coffee:5`), which
takes only `worker`, and the `work_sessions` table has no `project_id`
or `task_id` columns. Later, `sessionToWorkLog` reads
`session.project_id` / `session.task_id`
(`lib/models/work_session.coffee:153-154`), both always `undefined`,
coerced to null. The values have nowhere to live.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Pick one:

- Add `project_id` and `task_id` columns to `work_sessions`, thread the
  values through `startTimer` → `createWorkSession`, and let
  `sessionToWorkLog` read them.
- Or drop the two params from `startTimer` and the `/timer/start` route
  so the API stops advertising a capability it lacks.

The second is the smaller change and matches how timer logs are actually
used today.

## Risk

Low. Adding columns requires a migration but no data backfill (existing
sessions legitimately have no project/task). Dropping the params is a
pure API-surface reduction.
