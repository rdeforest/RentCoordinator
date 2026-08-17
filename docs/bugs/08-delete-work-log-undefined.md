# Bug 08 — DELETE /work-logs/:id always returns 500

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

Deleting any work entry from the UI fails every time with a 500. The
entry stays in the list.

## Reproduction

1. Create a work log.
2. Delete it from the work UI (`DELETE /work-logs/:id`).

Expected: 200 with `{ success: true, deleted: <id> }` and the log gone.
Actual: 500, log still present.

## Root cause

The route calls a model function that does not exist:

```
await workLogModel.deleteWorkLog id   # work.coffee:119
```

`lib/models/work_log.coffee` defines and exports only `createWorkLog`,
`getWorkLogs`, `getWorkLogById`, and `updateWorkLog` (work_log.coffee:83-88).
There is no `deleteWorkLog`. At runtime `workLogModel.deleteWorkLog` is
`undefined`, so calling it throws `TypeError: ... is not a function`,
which the route's `catch` turns into HTTP 500 (work.coffee:128-129).

## Proposed fix

Add and export the missing function in `lib/models/work_log.coffee`:

```coffee
deleteWorkLog = (id) ->
  db.prepare("DELETE FROM work_logs WHERE id = ?").run id
```

and add `deleteWorkLog` to the `module.exports` block.

Because the rent dashboard is event-sourced (see bug 06), deleting the
row alone won't back out any rent credit once work-reported events exist.
When bug 06 is implemented, this delete path should also emit the
compensating `work-reported` reversal so the removed hours stop
crediting.

## Risk

Low on its own — it's a missing function. The `run` call is fine even
when no row matches (0 changes), and the route already 404s earlier if
`getWorkLogById` returns nothing (work.coffee:116-117). The real hazard
is coupling: hard-deleting the `work_logs` row without reversing the
corresponding rent event (once events exist) would leave the ledger
crediting hours for work that no longer exists.
