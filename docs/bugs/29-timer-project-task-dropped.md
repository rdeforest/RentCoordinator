# Bug 29 — Timer project_id/task_id are silently dropped

**Reported:** 2026-08-15 by codebase audit
**Status:** resolved 2026-09-23 (parameters dropped)

## Resolution

Dropped, not implemented. `POST /timer/start` no longer reads `project_id` or
`task_id`, and `startTimer` takes only a worker.

Three things decided it, none of which are in the report below:

- **No caller ever sent them.** `static/coffee/timer.coffee` calls
  `/timer/start` in two places and neither includes a project or task. There is
  no project picker anywhere in the timer UI.
- **There is no data.** `projects` and `tasks` both hold zero rows, and zero
  work logs carry a `project_id`.
- **`timer_state` already has these columns and is itself dead.** Nothing in
  `lib/` reads or writes that table; the only reference left is the health
  check asserting it exists. Its `project_id`/`task_id` are where an earlier
  design kept this, and they are not a working alternative.

So this was never a broken feature — it was a feature that was not built, whose
parameter list was the only surviving evidence of the intent. Adding columns
would have meant a migration plus new UI for a capability with no data and no
demand; dropping them is a pure API-surface reduction with no callers to break.

Note the asymmetry this leaves: manual entry through `POST /work-logs` *does*
support both, and `work_logs` has the columns and the foreign keys (whose
`ON DELETE` behaviour bug 48 corrected). Only the timer path cannot. If the
timer should carry a project, that is a migration on `work_sessions` and a
picker in the UI — reachable, just not free, and worth doing when something
actually wants it.

`sessionToWorkLog` now says `project_id: null` outright rather than reading a
column that does not exist.

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
