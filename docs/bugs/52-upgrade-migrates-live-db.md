# Bug 52 — upgrade.sh migrates the live database, and snapshots pile up forever

**Reported:** 2026-09-23 by architectural review
**Status:** resolved 2026-09-24

## Resolution

Three parts:

1. **`scripts/upgrade.sh` now refuses to run against a live database**, the
   same way `scripts/backup-restore.sh` already refused (bug 34). The shared
   check (`service_is_running`, asked three ways: pidfile, `systemctl`,
   `lsof` on the port) moved into `scripts/lib/service.sh`, sourced by both
   scripts rather than duplicated. `upgrade.sh` can be overridden with
   `UPGRADE_ANYWAY=1`, mirroring `backup-restore.sh`'s `RESTORE_ANYWAY=1`.

2. **`docs/deployment.md`'s in-place upgrade procedure is reordered**: stop
   the service, *then* migrate, *then* start it — rather than migrate, then
   restart. `scripts/run-migrations.coffee`'s rollback restores its
   pre-migration snapshot with `copyFileSync`, which writes into the
   existing file so an open connection follows the restored content — a
   rollback while the old process is still serving would discard whatever it
   wrote *after* the snapshot was taken, not just leave the database stale.
   The refusal in part 1 is the safety net for when this step gets skipped;
   the reordered procedure is what keeps it from being needed.

3. **`scripts/run-migrations.coffee` prunes old pre-migration snapshots** on
   a successful run, keeping the newest 3 (`MAX_SNAPSHOTS_KEPT`) and removing
   the rest. Every prior successful run left its full `VACUUM INTO` copy of
   the database on disk forever; over enough deploys that's an unbounded
   number of full database copies. A failed run's snapshot — the evidence a
   rollback happened — survives the failed run itself, but is an ordinary
   snapshot to later successful runs and goes once three newer ones exist.

Covered by:
- `test/services/migrations.coffee` (`pruneSnapshots (bug 52)`) — keeps
  exactly the newest 3 of 5 snapshots for a database; leaves everything alone
  when there are 3 or fewer; does not touch a different database's snapshots
  in the same directory.
- Manual verification of the shell changes (no node test runner coverage for
  bash):
  - `scripts/upgrade.sh` against a live-looking service (a fake `PIDFILE`
    pointing at a real running process) refuses with exit 1 and the
    stop/migrate/start instructions; `UPGRADE_ANYWAY=1` proceeds past the
    refusal.
  - `scripts/lib/service.sh`'s `service_is_running`, sourced standalone,
    correctly reports running/not-running for both a live and a stale
    `PIDFILE`.
  - `scripts/backup-restore.sh` still sources the shared helper and behaves
    as before (`bash -n` syntax-checked; the refusal logic itself is
    unchanged, only relocated).

## Symptom

Following the documented in-place upgrade procedure ran migrations against
the database while the old process was still serving requests through it —
nothing stopped that from happening, and a failing migration's rollback
could discard writes made during the window between the snapshot and the
restart. Separately, every successful migration run left a full VACUUM'd
snapshot of the database on disk with nothing ever removing it.

## Reproduction

1. `scripts/upgrade.sh` had no check for whether the service was running —
   unlike `scripts/backup-restore.sh`, which already refused for exactly
   this reason (bug 34).
2. `docs/deployment.md`'s procedure ran `./scripts/upgrade.sh` (step 5) and
   only stopped/restarted the service afterward (step 6), so the window
   where migrations ran against a live database was the normal, documented
   path — not an operator mistake.
3. `scripts/run-migrations.coffee` wrote a timestamped snapshot before every
   run with pending migrations and never removed one after a successful run.

## Root cause

The refusal that `backup-restore.sh` gained for exactly this class of
problem (bug 34) was never applied to `upgrade.sh`, which has the same
"an open connection follows the file, not the inode" hazard. And nothing in
the pruning direction existed at all — `takeSnapshot` was written, but
nothing ever called anything named `pruneSnapshots` because it didn't exist.

## Risk

None identified. The refusal only blocks the case that was already unsafe;
`UPGRADE_ANYWAY=1` preserves the old (order-dependent) behavior for anyone
who has a reason to need it. Pruning only ever removes snapshots from a
*successful* run, keeping the 3 most recent — a failed run's own snapshot,
the one actually needed to recover from that failure, is untouched.
