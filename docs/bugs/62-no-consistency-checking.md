# Bug 62 — Nothing checks the database for consistency except migrations

**Reported:** 2026-09-24 by the pre-deploy review of the 2026-09 sweep
**Status:** resolved 2026-09-25

## Symptom

The only integrity checks in the app run inside migrations. A problem found
there aborts the migration, and since migrations run at boot, the server
refuses to start (bug 54 was one such case). Outside of migrations, nothing
notices an orphaned row, a corrupt month, or a ledger that contradicts
itself, until Lyndzie says a number looks wrong.

## Root cause

Consistency is only ever checked as a gate, never reported. Bugs happen and
will leave bad rows; the app has no place to surface them that does not also
stop it.

## Proposed fix

A scheduled check that reports and never blocks:

- SQLite `PRAGMA integrity_check` and `PRAGMA foreign_key_check`.
- Manual vs automatic disagreements: a `payment-made` recorded after an
  `amount_paid` pin on the same month, a pinned amount that differs from what
  the events compute, a payment filed under a different month than its Stripe
  description. Each finding gets a way to annotate its origin or to resolve
  it (Robert, 2026-09-24).
- Backup age: the newest S3 backup is older than ~26 hours (bug 64 went
  unnoticed for three weeks).
- Ledger invariants: every `payment-made` names a real month; no delete of a
  delete (the pre-bug-16 undelete shape); no month the fold marks `corrupt`;
  allocations on Stripe payments sum to the intent amount.

Results go to the application log and to an issues list.

**UI:** a red warning icon in the nav, shown only to the landlord (Robert),
only while the latest check has findings. It links to a page listing them.
Tenants never see it. The point is a quick answer when Lyndzie reports that
something looks off.

Migrations keep their own narrow checks (scoped to the tables they touch, as
bug 54 left them); the new check does not replace those.

## Decisions (Robert, 2026-09-25)

- **When:** at startup, and once a day at 03:00 UTC (after the 02:00 nightly
  backup) only if the data has changed since the last run. Activity is a few
  entries a week; hourly checks would be noise. "Changed" is a fingerprint of
  the tables that hold real data (events, work logs, sessions excluded), not
  the file mtime.
- **Backup check:** the newest S3 backup is older than the newest write — a
  change no backup contains. (An old backup is fine when nothing changed.)
- **Stripe cross-check:** included, on the same schedule, read-only.
- **Existing pins and pre-bug-09 Stripe payments:** flagged like anything
  else; Robert acknowledges each by hand, with a note, to build a memory of
  the system. No bulk or pre-seeded acknowledgments.
- **Where:** its own landlord-only page for now; it joins the UI overhaul
  discussion later.

## Resolution (2026-09-25)

Implemented as designed, with a few choices made along the way:

- **Checks** (`lib/services/consistency.coffee`): each is a small function of
  `deps → findings`, run by `runChecks()`; a check that throws becomes one
  `error` finding for that check rather than aborting the run. Covers
  `PRAGMA integrity_check` / `PRAGMA foreign_key_check` against the shared db
  handle; ledger shape (corrupt months from `computeAllPeriods`, invalid
  `effective_for` on `work-reported`/`payment-made`/`override`/`adjustment`,
  `edited`/`deleted`/`undeleted` events with a missing target, delete-of-delete);
  manual-vs-automatic (`payment-made` after an `amount_paid` pin, an
  `amount_paid` pin that disagrees with the summed payments, an `amount_due`
  pin — which, by design, always differs from the full calculation once one
  exists); the newest S3 backup vs. the newest write; and settled Stripe
  PaymentIntents vs. linked `payment-made` events (unlinked, or a linked
  intent whose allocation disagrees in month or amount). The Stripe listing
  and the S3/backup-age reads are both injectable, so the tests never touch
  the network.
- **A finding's `key`** encodes the kind and the values involved (e.g. the
  pinned cents and the computed cents), so it is stable for the same problem
  but changes — reappearing as a new, unacknowledged finding — the moment the
  underlying numbers do.
- **Storage:** `consistency_runs` (last 30, pruned on write) and
  `finding_acknowledgments` (keyed by finding key, so acknowledging survives
  the finding reappearing with the same key and disappears if it doesn't) —
  both in `lib/db/schema.coffee`'s `SCHEMA`, no separate migration.
- **Scheduling** (`lib/services/consistency-scheduler.coffee`): an
  unconditional run at startup (`main.coffee`, after `app.listen`, same spot
  as `startIdleBackup`), plus an unref'd daily timer at 03:00 UTC that only
  reruns if `lib/models/consistency.coffee::currentFingerprint()` — counts
  and max rowids of `events` and `work_logs` — differs from the last stored
  run's fingerprint. The decision (`shouldRunScheduled`) and the 03:00
  calculation (`msUntilNext3amUTC`) are both pure and unit-tested without a
  timer.
- **Routes** (`lib/routes/consistency.coffee`): `GET/POST /admin/consistency*`
  behind `requireAdmin` (403 for the tenant, same as every other `/admin/*`
  route); `GET /issues` behind `requireAdminPage`, matching `/admin`'s own
  pattern — a tenant who navigates there is redirected home (302), not
  handed a JSON 403, since the data itself is already withheld by the API
  routes underneath it.
- **UI:** `static/issues.html` / `static/coffee/issues.coffee` — open
  findings first (by severity), acknowledged ones greyed with their note; the
  nav badge (`SharedUtils.showConsistencyBadge`, called once from
  `shared-utils.coffee` for `/`, `/work`, `/rent` rather than duplicated into
  each page) hits `/admin/consistency/summary` and only ever renders on a
  200 with `open > 0` — a tenant's 403 there is silently a no-op, not a
  console error or a beacon.
- Added `logger.info` (`lib/logger.coffee`) — the run-summary log line asked
  for in the design had no matching log level before this.
