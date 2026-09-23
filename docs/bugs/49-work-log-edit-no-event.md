# Bug 49 — Editing a work log does not move the rent credit

**Reported:** 2026-09-23 by architectural review
**Status:** resolved 2026-09-23

## Resolution

`updateWorkLog` now emits an `edited` event targeting the `work-reported`
event the log produced — they share an id, by the convention `createWorkLog`
established for exactly this.

The edit carries `new_fields` as well as `new_payload`, because two of the
things an edit can change do not live in the payload: which month the work
counts toward (`effective_for`) and whose work it was (`actor`). A log whose
date is corrected across a month boundary has to take its credit with it, and
work reassigned from the tenant to the landlord has to stop crediting rent at
all. `period.applyEdits` applies those top-level replacements, refusing `id`,
`action` and `target_event_id` — an edit changes what an event says, not which
event it is.

The row write and the event emission are in one transaction. Without that, a
value the event validator rejects left a work log behind with no
`work-reported` event, which is the invariant bug 06 established.

Covered by `test/integration/work-edit.coffee`: a corrected duration, a
corrected date that moves months, a reassignment to the landlord, and an edit
that changes only the description.

## Symptom

Correcting a work log — a mistyped duration, a wrong date — changed the entry
on the work page and left the rent dashboard showing the old credit. Nothing
reported an error.

## Reproduction

1. As lyndzie, log two hours of work. The month shows a $100 credit.
2. Edit the entry to five hours.
3. Load the rent dashboard.

Expected: a $250 credit.
Actual: still $100.

## Root cause

`lib/models/work_log.coffee::updateWorkLog` wrote the row and emitted nothing.
`createWorkLog` emits `work-reported` and `deleteWorkLog` emits a `deleted`
that retracts it, but the edit path had no counterpart, so the fold in
`period.coffee` went on seeing the original hours.

The legacy `rentService.createOrUpdateRentPeriod` calls in
`lib/routes/work.coffee` were papering over this for the old model, which
recomputed a period from the `work_logs` rows. The dashboard reads the event
fold, which does not.

Found by the 2026-09-23 architectural review, as a prerequisite for deleting
the legacy calculator: those recalc calls cannot be removed while the event
model has a gap they were covering.

## Risk

The fold now accepts top-level replacements from an `edited` event, which no
previously stored event carries — `new_fields` is absent on every historical
edit, and `Object.assign` with `undefined` is a no-op. Existing events are
unaffected.
