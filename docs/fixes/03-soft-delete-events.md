# Fix 3 — Reconcile soft-delete UI with hard-delete model

## What's broken

The rent events UI shows:
- A "Show Deleted" toggle button
- A `(DELETED)` marker on deleted events
- An "Undelete" button on deleted events

The route layer has:
- `POST /rent/events/:id/undelete` calling `rentModel.undeleteRentEvent`
- `?includeDeleted=true` query parameter handling

But the model and schema have:
- No `deleted` column on `rent_events`
- `deleteRentEvent` does a hard `DELETE FROM rent_events`
- No `undeleteRentEvent` function exported (so the undelete route would 500)
- `getAllRentEvents(includeDeleted)` accepts the parameter and ignores it

Net effect: "Show Deleted" never shows anything (nothing's soft-deleted),
and clicking Undelete on anything would error.

## Two options

### Option A — Implement soft delete (recommended)

The audit log already records deletions, so technically nothing is lost.
But once a record is gone, the application can no longer show or restore
it from the UI without parsing audit-log JSON, which it isn't built to do.
Soft delete is the simpler UX that matches what the front-end already
expects.

### Option B — Remove the soft-delete UI

Less code, but the audit log becomes the only recovery mechanism, and
"recover from audit log" isn't a feature anyone wants to use under stress.

## Recommendation: Option A

The UI is already there. The audit log layer is already there. We're three
small changes away from the soft-delete the UI was clearly built for.

## The fix (Option A)

### 1. Schema: add `deleted_at` to `rent_events`

A nullable timestamp is sufficient — null means active, non-null means
deleted-at-that-time. No separate `deleted` boolean needed.

Migration `migrations/2026-05-19_130000_soft_delete_rent_events.coffee`:

```coffeescript
{ DatabaseSync } = require 'node:sqlite'

DB_PATH = process.env.DB_PATH or './tenant-coordinator.db'
db      = new DatabaseSync DB_PATH

console.log "Running migration: soft_delete_rent_events against #{DB_PATH}"

try
  # Check if column already exists (idempotent)
  columns = db.prepare('PRAGMA table_info(rent_events)').all()
  hasDeletedAt = columns.some (col) -> col.name is 'deleted_at'

  if hasDeletedAt
    console.log 'Column deleted_at already exists, skipping'
  else
    db.exec 'ALTER TABLE rent_events ADD COLUMN deleted_at DATETIME'
    db.exec 'CREATE INDEX IF NOT EXISTS idx_rent_events_deleted_at ON rent_events(deleted_at)'
    console.log 'Migration completed successfully'

catch err
  console.error 'Migration failed:', err.message
  throw err

finally
  db.close()
```

Update `lib/db/schema.coffee` to include the column for fresh installs.

### 2. Model: change delete behavior, add undelete

In `lib/models/rent.coffee`:

```coffeescript
deleteRentEvent = (id, deletedBy = 'user') ->
  existing = getRentEvent id

  unless existing
    throw new Error "Rent event not found: #{id}"

  if existing.deleted_at
    throw new Error "Rent event already deleted: #{id}"

  now = new Date().toISOString()
  db.prepare("UPDATE rent_events SET deleted_at = ? WHERE id = ?").run now, id

  await createAuditLog
    action:      'delete'
    entity_type: 'rent_event'
    entity_id:   id
    old_value:   existing
    new_value:   { deleted_at: now }
    user:        deletedBy

  return deleted: true, id: id, deleted_at: now


undeleteRentEvent = (id, undeletedBy = 'user') ->
  existing = db.prepare('SELECT * FROM rent_events WHERE id = ?').get id

  unless existing
    throw new Error "Rent event not found: #{id}"

  unless existing.deleted_at
    throw new Error "Rent event is not deleted: #{id}"

  db.prepare('UPDATE rent_events SET deleted_at = NULL WHERE id = ?').run id

  await createAuditLog
    action:      'undelete'
    entity_type: 'rent_event'
    entity_id:   id
    old_value:   { deleted_at: existing.deleted_at }
    new_value:   { deleted_at: null }
    user:        undeletedBy

  return getRentEvent id
```

And update the read paths to filter deleted unless asked:

```coffeescript
getAllRentEvents = (includeDeleted = false) ->
  whereClause = if includeDeleted then '' else 'WHERE e.deleted_at IS NULL'

  events = db.prepare("""
    SELECT e.*, p.year, p.month
    FROM rent_events e
    LEFT JOIN rent_periods p ON e.period_id = p.id
    #{whereClause}
    ORDER BY e.created_at DESC
  """).all()

  for event in events
    event.metadata = JSON.parse event.metadata if event.metadata
    event.deleted  = event.deleted_at?

  return events


getRentEventsForPeriod = (year, month, includeDeleted = false) ->
  period = getRentPeriod year, month
  return [] unless period

  whereClause = if includeDeleted
    'WHERE period_id = ?'
  else
    'WHERE period_id = ? AND deleted_at IS NULL'

  events = db.prepare("""
    SELECT * FROM rent_events
    #{whereClause}
    ORDER BY created_at DESC
  """).all period.id

  for event in events
    event.metadata = JSON.parse event.metadata if event.metadata
    event.deleted  = event.deleted_at?

  return events
```

Export `undeleteRentEvent` in the module exports.

### 3. Service: exclude deleted events from rent calculations

In `lib/services/rent.coffee`, `calculateRent` and `recalculateAllRent`
both call `rentModel.getRentEventsForPeriod year, month` without the
`includeDeleted` parameter — that's already what we want (`false` is the
default), so no change needed. **But verify** by tracing the call sites
after applying the model patch.

### 4. Route: already in place

The `POST /rent/events/:id/undelete` route in `lib/routes/rent.coffee`
already exists; it just needs the model function. Once `undeleteRentEvent`
is exported, the route should start working.

## How to verify

1. Backup first.
2. Apply migration: `coffee migrations/2026-05-19_130000_soft_delete_rent_events.coffee`
3. Update `schema.coffee`, `lib/models/rent.coffee`.
4. Restart server.
5. Create a test payment event.
6. Delete it from the UI — should show as `(DELETED)` when "Show Deleted"
   is toggled on, and disappear when toggled off.
7. Click Undelete — should restore.
8. Confirm that calculations exclude deleted events: create a $50 payment,
   note the "amount paid" total, delete the payment, recalculate, verify
   "amount paid" drops by $50.

## Risk

**Low to medium.** No data is destroyed by this change — the migration only
adds a column. All existing events get `deleted_at = NULL` by default
(i.e., not deleted), which is correct.

The risk is in the calculation code: any code path that does `DELETE FROM
rent_events` or queries without filtering on `deleted_at` should be hunted
down. After applying, grep for `rent_events` references in `lib/` and
verify each one is filter-correct:

```bash
grep -rn "rent_events" lib/
```
