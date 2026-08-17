# Known Bugs

This directory tracks active and recently-resolved bugs. Each bug has its
own file with reproduction steps, root cause, and (when known) a link to
the proposed fix in `docs/fixes/`.

## Active

| # | Title | Severity | Fix |
|---|---|---|---|
| 01 | Periods table shows raw `amount_due` instead of stress-free display | Low (UX) | [fixes/01](../fixes/01-periods-table-display.md) |
| 02 | Cannot delete rent period (FK constraint) | High | [fixes/02](../fixes/02-cascade-delete-migration.md) |
| 03 | Soft-delete UI wired to hard-delete model | Medium | [fixes/03](../fixes/03-soft-delete-events.md) |
| 04 | Lyndzie's work hours not appearing in rent periods | High | [fixes/04](../fixes/04-missing-work-hours.md) |
| 05 | `recalculateAllRent` retroactive logic discarded | Medium | [fixes/05](../fixes/05-recalculate-persists-retroactive.md) |

### 2026-08-15 audit batch

Found in a full-codebase sweep; fixes described inline in each file, not
yet in `docs/fixes/`.

| # | Title | Severity | Fix |
|---|---|---|---|
| 06 | [Work hours never credit rent (event model)](06-work-hours-never-credit.md) | High | inline |
| 07 | [Timer-stopped work logs always save duration 0](07-timer-duration-zero.md) | High | inline |
| 08 | [`DELETE /work-logs/:id` always 500s](08-delete-work-log-undefined.md) | High | inline |
| 09 | [ACH payments never recorded (no webhook)](09-ach-payment-not-recorded.md) | High | inline |
| 10 | [Payment confirmation not idempotent (double-credit)](10-payment-not-idempotent.md) | High | inline |
| 11 | [`SESSION_SECRET` falls back to a public default in prod](11-session-secret-default.md) | High (security) | inline |
| 12 | [Verification code brute-forceable (no lockout)](12-verification-code-brute-force.md) | High (security) | inline |
| 13 | [Verification codes use `Math.random()`](13-verification-code-weak-random.md) | High (security) | inline |
| 14 | [Adjustment/manual events overwrite `amount_due` instead of adding](14-adjustment-overwrites-amount-due.md) | Medium | inline |
| 15 | [`work_value_change` events silently recorded as payments](15-work-value-change-as-payment.md) | Medium | inline |
| 16 | [Undelete is a no-op in the event fold](16-undelete-noop.md) | Medium | inline |
| 17 | [Rent events table always empty (client/server field mismatch)](17-events-list-empty.md) | Medium | inline |
| 18 | [`/rent/summary` uses raw `amount_due`, not display value](18-summary-raw-amount-due.md) | Medium | inline |
| 19 | [Summary "total credits" renders undefined](19-summary-total-credits-undefined.md) | Low | inline |
| 20 | [`temporary_rent_amount` can never be cleared](20-temporary-rent-amount-cannot-clear.md) | Medium | inline |
| 21 | [Global error handler registered before routes; never catches](21-error-handler-registration-order.md) | Medium | inline |
| 22 | [Email casing mismatch can break verification](22-email-casing-mismatch.md) | Medium | inline |
| 23 | [`NODE_ENV=test` fully bypasses auth](23-test-env-auth-bypass.md) | Medium (security) | inline |
| 24 | [Edit-work billable checkbox uses `isnt false`](24-billable-checkbox-isnt-false.md) | Medium | inline |
| 25 | [Duplicate `GET /work-logs`; richer handler is dead code](25-duplicate-work-logs-route.md) | Medium | inline |
| 26 | [Recurring-events scheduler writes legacy tables](26-recurring-events-legacy-tables.md) | Medium | inline |
| 27 | [Payment-history page reads legacy `rent_events` table](27-payment-history-legacy-table.md) | Medium | inline |
| 28 | [Recurring-event processing logs hardcode `status: success`](28-recurring-logs-hardcoded-success.md) | Medium | inline |
| 29 | [Timer `project_id`/`task_id` silently dropped](29-timer-project-task-dropped.md) | Low | inline |
| 30 | [Documented 8-hour auto-timeout not implemented](30-session-timeout-not-implemented.md) | Low | inline |
| 31 | [Timer-created logs bypass rent recalc](31-timer-bypasses-recalc.md) | Low | inline |
| 32 | [`resumeSession` lacks ownership/state validation](32-resume-session-no-validation.md) | Low | inline |
| 33 | [`admin/detokenize` gated only by shared auth, not admin role](33-admin-detokenize-no-role.md) | Low (privilege) | inline |
| 34 | [Backup restore not atomic; safety-copy name self-clobbers](34-backup-restore-not-atomic.md) | Low | inline |
| 35 | [Money handled as floating-point dollars throughout](35-money-floating-point.md) | Low | inline |
| 36 | [Logger doesn't tokenize error message/stack (PII leak)](36-logger-untokenized-errors.md) | Low (PII) | inline |
| 37 | [Wide-open CORS, no explicit `sameSite`, no CSRF token](37-cors-csrf-hardening.md) | Low (security) | inline |
| 38 | [Used/expired verification codes never purged](38-verification-codes-not-purged.md) | Low | inline |
| 39 | [`period.coffee` `DEFAULT_CONFIG` duplicates config constants](39-default-config-duplication.md) | Low | inline |
| 40 | [`calculateNextDueDate` month/year math fragile](40-next-due-date-math.md) | Low | inline |
| 41 | [`transaction()` helper doesn't await callback, can't nest](41-transaction-helper-not-await.md) | Low | inline |
| 42 | [Health check opens/closes a fresh DB connection per hit](42-health-check-new-connection.md) | Low | inline |
| 43 | [`scripts/install.sh` targets abandoned Deno stack](43-install-sh-deno-stale.md) | Low (stale infra) | inline |
| 44 | [`dist` build never copies `package.json`](44-dist-missing-package-json.md) | Medium (latent) | inline |
| 45 | [`backup-*.sh` mangle `.env` secrets via `xargs`](45-backup-env-parsing.md) | Medium | inline |
| 46 | [Boot-time migration loop swallows failures (no `set -e`)](46-migration-loop-no-set-e.md) | Medium (infra) | inline |
| 47 | [`scripts/upgrade.sh` is empty but docs say it runs migrations](47-upgrade-sh-empty.md) | Low | inline |
| 48 | [Projects/tasks/sessions FKs lack `ON DELETE` (same class as 02)](48-fk-no-on-delete.md) | Medium (latent) | inline |

## Resolved

(none recorded yet — start adding when you fix the active ones)

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
