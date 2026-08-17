# Bug 16 — Undelete is a no-op in the event fold

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

Clicking "Undelete" on a deleted rent event returns success but restores
nothing. The event stays deleted in both the computed periods and the
events list.

## Reproduction

1. Create a rent event, then delete it.
2. Click "Show Deleted", then click "Undelete" on that event.

Expected: the event comes back — it re-enters the period math and drops the
`(DELETED)` marker.
Actual: the request 200s, but the event is still gone and still flagged
deleted.

## Root cause

Undelete is implemented as "delete the delete event". The route
(`lib/routes/rent.coffee:345-364`) records a new `deleted` event whose
`target_event_id` is the id of the original `deleted` event.

But the fold never had the delete event in scope to remove.
`resolveEditsAndDeletes` (`lib/services/period.coffee:29-42`) builds `byId`
only from events whose action is *not* `edited`/`deleted` (line 31), then
processes deletes with `byId.delete e.target_event_id` (line 39). The
delete-of-a-delete targets a `deleted` event's id, which was never inserted
into `byId`, so `byId.delete(deleteEventId)` removes nothing. The originally
deleted event was already dropped when its own delete event was processed,
and it stays dropped.

The events list has the same blind spot: `GET /rent/events`
(rent.coffee:246-259) computes `deletedIds` from the target of *every*
`deleted` event, including the delete-of-the-delete — whose target is
another delete event, not the original — so the original event's id stays
in `deletedIds` and keeps rendering as deleted.

Net effect: undelete touches neither the period computation nor the events
list. (This is distinct from bug 03, which is the legacy hard-delete model's
undelete; this bug is in the event-sourced fold.)

## Proposed fix

(No docs/fixes/ file exists yet.)

Make undelete emit an event the fold actually understands instead of
stacking deletes. Add an explicit `undeleted` (or `restored`) action whose
`target_event_id` is the *original* event's id, and:

- In `resolveEditsAndDeletes`, after applying deletes, re-add any event that
  has a later `undeleted` targeting it (respecting event order, so a
  delete → undelete → delete sequence resolves to deleted).
- In `GET /rent/events`, remove ids from `deletedIds` when a later
  `undeleted` event targets them, so the events list agrees with the fold.

The route then records one `undeleted` event pointing at the original id,
not at the delete event.

## Risk

The fold logic is order-sensitive — delete/undelete/delete cycles have to
resolve deterministically, so the resolution must respect `occurred_at`
ordering, not just presence. Needs a test that exercises a full
create → delete → undelete → delete sequence and asserts the final state.
Low blast radius otherwise; the new action is additive and old events are
unaffected.
