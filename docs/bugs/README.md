# Known Bugs

This directory tracks active and recently-resolved bugs. Each bug has its
own file with reproduction steps, root cause, and (when known) a link to
the proposed fix in `docs/fixes/`.

## Active

Three remain, all deferred deliberately rather than missed.

| # | Title | Severity | Why it is still here |
|---|---|---|---|
| 23 | [`NODE_ENV=test` fully bypasses auth](23-test-env-auth-bypass.md) | Medium (security) | Removing the bypass means the integration suite has to establish real sessions — worth doing, but it touches every test file and the owner asked to understand the tradeoffs first. |
| 27 | [Payment-history page reads legacy `rent_events`](27-payment-history-legacy-table.md) | Medium | Same decision. |
| 29 | [Timer `project_id`/`task_id` silently dropped](29-timer-project-task-dropped.md) | Low | Add the columns or drop the parameters; deferred pending that call. |

### The remaining structural debt

The app still runs two "what's owed" models: the event-sourced `events` table
that the dashboard, the rent math and the Stripe path all read, and the legacy
`rent_periods` / `rent_events` tables that the recurring-events scheduler and
the payment-history page still write. Nothing reconciles them.

Bug 26 — the recurring-events scheduler — has now been deleted rather than
ported, which removes one of the two remaining writers to the dead side. Bug 27
(the payment-history page) is the other, and an architectural review recommends
the same treatment: it reads 11 pre-migration rows, cannot see the 13 real
`payment-made` events, will never gain a row, and its delete and reassign
buttons report success while changing nothing about what is owed.

The legacy tables themselves are left in place. They hold real history, nothing
writes to them after bug 26, and dropping them has its own gotchas — the health
check in `lib/routing.coffee` asserts `rent_periods` *exists*, so dropping it
without changing that line turns every instance unhealthy at the ALB.

## Resolved

| # | Title | Resolved | Notes |
|---|---|---|---|
| 01 | Periods table shows raw `amount_due` | 2026-09-23 | Already fixed in the client; the file had not been updated. |
| 02 | Cannot delete rent period (FK constraint) | 2026-09-23 | Cascade migration + the route no longer hard-deletes at all. |
| 03 | Soft-delete UI wired to hard-delete model | 2026-09-23 | `deleted_at` and `undeleteRentEvent` both exist. |
| 04 | Lyndzie's work hours not appearing | 2026-08-17 | Same root cause as 06. |
| 05 | `recalculateAllRent` retroactive logic discarded | 2026-09-23 | The event fold retires the shortfall forward rather than rewriting history. |
| 06 | Work hours never credit rent | 2026-08-17 | `createWorkLog` emits a `work-reported` event. |
| 07 | Timer logs always save duration 0 | 2026-09-23 | Duration comes from the event timeline, not the dead column. |
| 08 | `DELETE /work-logs/:id` always 500s | 2026-08-17 | Added `deleteWorkLog`; retracts the credit. |
| 09 | ACH payments never recorded | 2026-08-17 | Signature-verified webhook. |
| 10 | Payment confirmation not idempotent | 2026-08-17 | Idempotent on the Stripe intent id. |
| 11 | `SESSION_SECRET` falls back to a public default | 2026-09-23 | No committed secret exists now; unset outside dev/test refuses to boot. |
| 12 | Verification code brute-forceable | 2026-09-23 | Attempt counter burns the code; throttled per (address, email). |
| 13 | Verification codes use `Math.random()` | 2026-09-23 | `crypto.randomInt`. |
| 14 | Adjustments overwrite `amount_due` | 2026-09-23 | Additive `adjustment` action; `override` stays the absolute pin. |
| 15 | `work_value_change` recorded as a payment | 2026-09-23 | Unknown types are a 400; the option is gone from the UI. |
| 16 | Undelete is a no-op in the fold | 2026-09-23 | `undeleted` action; delete/undelete resolved by time. |
| 17 | Rent events table always empty | 2026-09-04 | Route projects events onto the flat shape. |
| 18 | `/rent/summary` uses raw `amount_due` | 2026-09-23 | Sums `display_amount_due`, clamped per month. |
| 19 | Summary "total credits" renders `$NaN` | 2026-09-04 | Client reads `total_discount`. |
| 20 | `temporary_rent_amount` can never be cleared | 2026-09-23 | Presence check, not a null check. |
| 21 | Error handler registered before routes | 2026-09-23 | Mounted last; honours `err.status`. |
| 22 | Email casing mismatch breaks verification | 2026-09-23 | Normalized at the route boundary. |
| 24 | Billable checkbox uses `isnt false` | 2026-09-23 | `!!log.billable`. |
| 25 | Duplicate `GET /work-logs` | 2026-09-23 | One handler; the session-merging one would now double-count. |
| 28 | Processing logs hardcode `status: success` | 2026-09-23 | Outcome columns added and used. |
| 30 | Documented 8-hour timeout not implemented | 2026-09-23 | Implemented: the open segment is capped and the session closed at the cap. |
| 31 | Timer logs bypass rent recalc | 2026-09-23 | `stopTimer` recalculates for the tenant. |
| 32 | `resumeSession` lacks validation | 2026-09-23 | Ownership and state checked. |
| 33 | `admin/detokenize` not admin-gated | 2026-09-23 | `requireAdmin` on all admin routes and the page. |
| 34 | Backup restore not atomic | 2026-09-23 | Timestamped safety copy; rename into place. |
| 35 | Money as floating-point dollars | 2026-09-23 (partly) | Amounts round to the cent so a month can be paid exactly; the full integer-cents representation is still open. |
| 36 | Logger doesn't tokenize error text | 2026-09-23 | Addresses inside messages and stacks are tokenized; the trace survives. |
| 37 | Wide-open CORS, no `sameSite` | 2026-09-23 | cors not mounted unless configured; `sameSite: 'lax'`. |
| 38 | Verification codes never purged | 2026-09-23 | Deleted on use, superseded on reissue, swept on expiry. |
| 26 | Recurring-events scheduler writes legacy tables | 2026-09-23 | Removed, not ported — no reader, and it sat in the boot path. |
| 39 | `DEFAULT_CONFIG` duplicates constants | 2026-09-08 | Derived from `config.coffee`. |
| 40 | `calculateNextDueDate` month/year math | 2026-09-23 | Day clamped to month length; yearly uses its configured date. |
| 41 | `transaction()` doesn't await, can't nest | 2026-09-23 | `SAVEPOINT`; async callbacks refused. |
| 42 | Health check opens a fresh connection | 2026-09-23 | Uses the shared handle. |
| 43 | `scripts/install.sh` targets Deno | 2026-09-23 | Deleted; CLAUDE.md corrected. |
| 44 | `dist` build never copies `package.json` | 2026-09-23 | Three separate faults; the artifact now starts. |
| 45 | `backup-*.sh` mangle `.env` secrets | 2026-09-23 | Source the file instead of `xargs`. |
| 46 | Migration loop swallows failures | 2026-09-23 | `set -euo pipefail`, delegating to `upgrade.sh`. |
| 47 | `scripts/upgrade.sh` is empty | 2026-09-23 | Real runner; migrations also apply at boot. |
| 48 | Projects/tasks/sessions FKs lack `ON DELETE` | 2026-09-23 | Cascade for parts, `SET NULL` for references. |

Not in the numbered catalog but fixed this cycle: the daily-backup cron hit an
auth-gated endpoint (now `backup-now.sh`); the init script's pidfile
daemonization broke restart (now `exec node`); `npm run test:focus` had never
run anything (`scripts/run-tests.coffee` did not parse and searched a `tests/`
directory that does not exist); and `scripts/build.coffee` had been failing
since May on a stale copy of the repo under `tmp/`, because it compiled `.`.

## Adding a bug

Use this template:

```markdown
# Bug NN — Short title

**Reported:** YYYY-MM-DD by whoever
**Status:** active | investigating | fix-proposed | resolved

## Symptom

What the user sees.

## Reproduction

1. ...
2. ...

## Root cause

What's actually wrong. Often this needs a paragraph; sometimes it's "we
don't know yet".

## Proposed fix

Link to `docs/fixes/NN-...md` once you have one.

## Risk

What could go wrong applying the fix.
```
