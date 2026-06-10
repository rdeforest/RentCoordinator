# Bug 03 — Soft-delete UI wired to hard-delete model

**Reported:** 2026-05-19 (latent, discovered during review)
**Status:** fix-proposed

## Symptom

- The rent events UI has a "Show Deleted" toggle, but toggling it never
  reveals any deleted events.
- Deleted events disappear immediately and cannot be restored.
- If a deleted event were somehow shown, clicking "Undelete" would 500.

## Reproduction

1. Create a rent event.
2. Delete it from the Events table.
3. Click "Show Deleted".

Expected: deleted event reappears with an Undelete button.
Actual: nothing changes; the event is gone.

## Root cause

The UI and routes assume a soft-delete model:
- "Show Deleted" toggle
- `(DELETED)` marker on events
- Undelete button on deleted events
- `POST /rent/events/:id/undelete` route
- `?includeDeleted=true` query parameter

But the model and schema implement hard delete:
- `deleteRentEvent` does `DELETE FROM rent_events`
- No `deleted` column on `rent_events`
- `rentModel.undeleteRentEvent` is not defined (the route calls a
  nonexistent function)
- `getAllRentEvents(includeDeleted)` accepts the parameter and ignores it

The audit log preserves deletion records, but the application UI cannot
restore from the audit log.

## Proposed fix

Implement soft delete to match the UI that was already built. See
[fixes/03-soft-delete-events.md](../fixes/03-soft-delete-events.md).
