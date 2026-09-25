# Bug 62 — Nothing checks the database for consistency except migrations

**Reported:** 2026-09-24 by the pre-deploy review of the 2026-09 sweep
**Status:** open (design agreed, not started)

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
