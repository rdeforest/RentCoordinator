# Bug 48 — projects/tasks/sessions FKs lack ON DELETE (same class as bug 02)

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

Deleting a project that has any task or work_log, or a work_session
referenced by a work_event or current_session, raises a FK constraint
error. Same footgun as bug 02, on a different set of tables.

## Reproduction

N/A — latent; triggered if/when a delete path is added for projects or
work_sessions. `PRAGMA foreign_keys = ON` is set at
`lib/db/schema.coffee:6`, so the constraint is enforced.

## Root cause

`lib/db/schema.coffee` defines these foreign keys with no `ON DELETE`
action:

- `tasks.project_id` → `projects(id)` (`:21`)
- `work_events.session_id` → `work_sessions(id)` (`:43`)
- `current_sessions.session_id` → `work_sessions(id)` (`:53`)
- `work_logs.project_id` → `projects(id)` (`:63`)
- `work_logs.task_id` → `tasks(id)` (`:64`)

With foreign keys enforced, deleting a referenced parent errors out. The
2026-05-19 cascade migration fixed exactly this class of problem for the
`rent_periods` children (bug 02), but these tables were not touched, so
the same 500 waits behind any future delete path.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Decide the intended semantics per FK — `ON DELETE CASCADE` for true
children (work_events, current_sessions), `ON DELETE SET NULL` for loose
references (work_logs.project_id/task_id) — and add them via migration,
or confirm these entities are delete-never and document that. Cross-
reference bug 02, which set the precedent.

## Risk

Medium (latent). No delete path exists today; the day one is added it
500s until the FKs are corrected.
