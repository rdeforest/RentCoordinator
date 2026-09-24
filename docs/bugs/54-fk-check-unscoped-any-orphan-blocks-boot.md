# Bug 54 — Unscoped `PRAGMA foreign_key_check` blocks boot on any orphan

**Reported:** 2026-09-23 by architectural review
**Status:** resolved 2026-09-24

## Resolution

`migrations/2026-09-23_120000_fk_on_delete.coffee` now runs
`PRAGMA foreign_key_check(<table>)` once per table it actually rebuilt
(`tasks`, `work_events`, `current_sessions`, `work_logs`), instead of the
bare `PRAGMA foreign_key_check` with no argument, which checks every table
in the database.

Covered by `test/services/migrations.coffee`
(`fk_on_delete migration ignores orphans outside its own tables (bug 54)`):
builds a scratch database on the pre-migration schema (the five tables
without `ON DELETE`, plus `rent_periods`/`rent_events`), seeds an orphan
`rent_events` row pointing at a nonexistent `rent_periods` id, and asserts
the migration still completes — rebuilding `work_logs` with `ON DELETE` as
expected — without the orphan (a table this migration never touches)
aborting it.

## Symptom

The migration failed with `FK violations after rebuild: [...]` naming a row
in a table the migration had nothing to do with (in the report, a legacy
`rent_events` row). Since migrations run from `schema.initialize` at every
boot, this did not just fail once — every subsequent boot re-attempted the
same pending migration and failed the same way.

## Reproduction

1. Have a database with any pre-existing FK-orphaned row in a table this
   migration does not rebuild (e.g. a `rent_events` row whose `period_id`
   points at a deleted `rent_periods` row from before the cascade-delete
   migration existed).
2. Boot the app, or run `scripts/upgrade.sh`.
3. `schema.initialize` applies the pending `fk_on_delete` migration, which
   rebuilds `tasks`, `work_events`, `current_sessions` and `work_logs`
   successfully, then calls bare `PRAGMA foreign_key_check` — which reports
   the unrelated orphan and throws, rolling the whole migration back.
4. Boot fails. Every future boot repeats the same failure, since the
   migration never gets recorded as applied.

## Root cause

`PRAGMA foreign_key_check` with no argument checks every table in the
database, not just the ones a given migration is responsible for. This
migration's own rebuild logic is correctly scoped to five tables; the
verification step after it was not.

## Risk

None identified. The migration's job was always to fix these five tables'
`ON DELETE` behavior — verifying only those five is what "did this migration
do its job correctly" actually means. A real orphan in `rent_events` (or any
other table) is a genuine, separate problem, but not one this migration was
ever positioned to detect reliably (it would just as easily miss one in a
table it doesn't touch when there happens to be nothing else wrong), and
it's the kind of thing bug 26/27's structural cleanup is the right place to
address.
