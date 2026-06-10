# Fix 2 — Cannot delete rent period due to FK constraint

## What's broken

Deleting any rent period that has been touched by the recurring-events
scheduler fails with a SQLite FOREIGN KEY constraint error.

## Root cause

Two tables reference `rent_periods(id)` as `NOT NULL`:

- `rent_events.period_id` — handled in `deleteRentPeriod` by manual cleanup
- `recurring_event_logs.period_id` — **not** handled

The recurring-events scheduler runs on startup and daily, and it inserts a
row into `recurring_event_logs` every time it processes a rent due or
recalculation event for a month. Any month that's been around for a day or
two will have entries here, blocking deletion.

Neither FK has `ON DELETE CASCADE`, so SQLite refuses to delete the parent
row.

## The fix

Two parts:

1. **Migration** that rebuilds both child tables with `ON DELETE CASCADE`.
   SQLite doesn't support `ALTER TABLE ... MODIFY CONSTRAINT`, so we have
   to recreate the tables. The migration is in
   `migrations/2026-05-19_120000_cascade_period_deletes.coffee`.

2. **Schema update** in `lib/db/schema.coffee` so fresh installs match.
   The migration is idempotent (it checks for existing CASCADE behavior),
   but `schema.coffee` is what creates new databases.

3. **Simplify `deleteRentPeriod`** in `lib/models/rent.coffee` — the manual
   `DELETE FROM rent_events` step is no longer needed once cascades are in
   place. We'll leave it as belt-and-suspenders for now (it does no harm
   when cascades are active) but add a note.

## How to verify

1. **Pre-flight: take a backup.** `curl -X POST http://localhost:3000/api/backup`.
   Verify the backup file exists and is non-empty.
2. Run the migration: `coffee migrations/2026-05-19_120000_cascade_period_deletes.coffee`
3. Verify cascades are present:
   ```bash
   sqlite3 tenant-coordinator.db "SELECT sql FROM sqlite_master WHERE name IN ('rent_events', 'recurring_event_logs');"
   ```
   Both should now show `ON DELETE CASCADE`.
4. From the UI, delete last month's period. It should succeed.
5. Run the full integration test suite to confirm nothing else broke:
   `npm run test:integration`.

## Risk

**Medium.** Schema migrations on the production SQLite are the highest-risk
operation this app supports. The migration uses a transaction with explicit
ROLLBACK, but the standard precautions apply:

- Test against a copy of production first
- Backup, verify backup, then run
- Migration is idempotent — checks if cascade is already present and skips
  if so, so re-running is safe

## Why not just delete the orphaned `recurring_event_logs` rows manually?

That would unstick deletion today but not tomorrow — every new month
generates new log rows. The cascade is the right structural fix because
log rows are intrinsically subordinate to the period they describe.
