# RentCoordinator Architecture

A one-page tour of how the pieces fit together. Read this when you need
to remember where a thing lives or want to make a structural change.

## Layered structure

```
┌─────────────────────────────────────────────────────────┐
│  Browser                                                │
│    static/*.html  +  static/js/*.js (compiled coffee)   │
└────────────────────────┬────────────────────────────────┘
                         │ HTTP/JSON
┌────────────────────────┴────────────────────────────────┐
│  Express (main.coffee)                                  │
│    lib/middleware.coffee   — sessions, CORS, static     │
│    lib/routing.coffee      — health + delegates below   │
│                                                         │
│  Routes                                                 │
│    lib/routes/*.coffee     — HTTP shape + validation    │
│                                                         │
│  Services                                               │
│    lib/services/*.coffee   — business logic             │
│                                                         │
│  Models                                                 │
│    lib/models/*.coffee     — SQL only                   │
│                                                         │
│  Database                                               │
│    lib/db/schema.coffee    — node:sqlite, schema init   │
│    lib/db/utils.coffee     — named-param helper         │
└─────────────────────────────────────────────────────────┘
                         │
┌────────────────────────┴────────────────────────────────┐
│  External                                               │
│    Stripe (lib/services/payment.coffee)                 │
│    AWS SES (lib/services/email.coffee)                  │
│    AWS S3 (lib/services/backup.coffee)                  │
│    AWS Secrets Manager (loaded at startup)              │
└─────────────────────────────────────────────────────────┘
```

## The three flows that matter

### Rent flow (the dominant one)

```
Browser (rent.html)
  → GET /rent/period/:year/:month       (routes/rent.coffee)
    → rentService.createOrUpdateRentPeriod
      → rentService.calculateRent         (services/rent.coffee)
        → workLogModel.getWorkLogs        (models/work_log.coffee)
        → rentModel.getRentPeriod         (models/rent.coffee)
        → rentModel.getRentEventsForPeriod
      → rentConfiguration.getConfiguration  (models/rent_configuration.coffee)
      → rentModel.createRentPeriod | updateRentPeriod
    → routes/rent.coffee::getDisplayAmountDue  ← stress-free display layer
  ← JSON { ...period, display_amount_due }
```

Key invariant: **`amount_due` in the database is the *real* obligation.
`display_amount_due` in the API response is the *stress-free* value the
UI shows by default.** The two diverge intentionally (see the
"Stress-Free Display Logic" section in CLAUDE.md).

### Timer flow

```
Browser (work.html, index.html)
  → POST /timer/start | /timer/pause | /timer/resume | /timer/stop
    → timerService.{start,pause,resume,stop}Timer  (services/timer.coffee)
      → workSessionModel + work_events             (models/work_session.coffee)
      → on stop, creates work_logs row             (models/work_log.coffee)
```

Timer state lives in `timer_state` (one row per worker). Sessions live
in `work_sessions` with detail events in `work_events`. Completed work
becomes a `work_logs` row, which is what rent calculations read from.

### Payment flow (Stripe ACH)

```
Browser (payment.html)
  → POST /payment/setup-intent             (routes/payment.coffee)
    → paymentService.getOrCreateCustomer   (services/payment.coffee)
    → paymentService.createSetupIntent
  ← clientSecret
Browser → Stripe.js → bank account collected
  → POST /payment/create-intent
    → paymentService.createPaymentIntent
  ← paymentIntentId, clientSecret
Browser → Stripe.js → confirms
  → POST /payment/confirm
    → paymentService.confirmPayment
      → on success: rentModel.recordPayment (creates a payment rent_event)
```

Note that `routes/payment.coffee` and `routes/payments.coffee` are
**different things**:

- `payment.coffee` (singular) is the Stripe checkout flow above
- `payments.coffee` (plural) is the payment-history CRUD: list,
  reassign-to-different-period, delete

They probably should be renamed for clarity. See
`docs/code-review-2026-05.md` §3.1.

## The data model in plain language

| Table | Purpose | Key relationships |
|---|---|---|
| `projects` | Optional grouping for work | parent of `tasks`, `work_logs` |
| `tasks` | Optional sub-grouping | references `projects` |
| `work_sessions` | An active or completed timer session | parent of `work_events` |
| `work_events` | start/pause/resume/stop ticks for a session | references `work_sessions` |
| `current_sessions` | Lookup: which session is each worker on | references `work_sessions` |
| `work_logs` | A completed unit of billable work | the **authoritative source** of hours-worked |
| `timer_state` | One row per worker — current timer status | per `WORKERS` config |
| `rent_periods` | One row per month — calculation state | parent of `rent_events`, `recurring_event_logs` |
| `rent_events` | Payments, adjustments, manual entries against a period | references `rent_periods` (CASCADE) |
| `recurring_events` | Templates for monthly rent-due / recalculation jobs | parent of `recurring_event_logs` |
| `recurring_event_logs` | Audit trail of which months were processed when | references both above (CASCADE) |
| `rent_configuration` | Singleton: temporary rent override + apply flag | — |
| `audit_logs` | Append-only record of CRUD actions on entities | not FK-linked (entity IDs are loose references) |
| `auth_sessions` | Email verification codes | — |
| `pii_tokens` | Tokenization mapping for logger | — |

### Computed vs authoritative columns

- `rent_periods.hours_worked` — **computed** from `work_logs`. Recalculated
  on every `calculateRent` call.
- `rent_periods.discount_applied` — computed from `hours_worked` and the
  hourly credit rate.
- `rent_periods.amount_due` — computed by default. Becomes authoritative
  if `amount_due_manual = 1` (a manual override).
- `rent_periods.amount_paid` — computed by summing payment `rent_events`,
  unless `amount_paid_manual = 1`.

This split is the source of most confusion when debugging rent
calculations. "Why does the database say X but the page says Y?" almost
always reduces to the manual-override flags.

## Configuration sources

- `lib/config.coffee` — defaults for everything; reads `process.env.*`
- `.env` on production servers (loaded by systemd unit)
- AWS Secrets Manager for production secrets (loaded by
  `scripts/restore-secrets.sh`)
- `rent_configuration` table — the in-database singleton for the
  temporary rent override

## Build and run

- Server-side CoffeeScript runs directly: `coffee main.coffee`
- Client-side CoffeeScript is compiled to JS on server startup
  (see `scripts/build.ts`)
- No webpack, no bundler — files in `static/js/` are loaded directly
- SQLite is `node:sqlite` (built into Node 22+), so no driver install

## Deployment

- AWS Auto Scaling Group with `ReplaceUnhealthy` suspended (instances
  stay up when unhealthy rather than being terminated — important for
  debugging)
- Application Load Balancer with health checks against `/health`
- CloudWatch Logs for the application's structured logs
- S3 bucket `rent-coordinator-backups-822812818413` (us-west-2),
  30-day retention

## Things that aren't obvious

1. **The recurring events scheduler runs on server startup.**
   `lib/db/schema.coffee::initialize` calls
   `recurringEventsService.initializeRecurringEvents()`, which creates
   default events on first boot and processes any due events
   immediately. A bad recurring event template will break startup.

2. **There is no migration framework.** Migrations are CoffeeScript files
   in `migrations/` run manually (or by `scripts/upgrade.sh`) in
   alphabetical order. There is no "ran migrations" tracking table.
   This is fine for a 2-user app but means: don't make the same
   migration name twice, and write migrations to be idempotent.

3. **The frontend has no module system.** Each `static/coffee/*.coffee`
   compiles to a standalone `<script>` file with everything at module
   scope and functions exposed via `window.foo = ->`. This is fragile;
   see `docs/code-review-2026-05.md` §3.12.

4. **The `audit_logs.entity_id` is a loose reference.** No foreign key
   constrains it. This is intentional — audit logs persist beyond the
   life of the entities they describe — but means audit cleanup is
   manual.

## Where the bodies are buried

See `docs/bugs/` for the known issues, each in its own file with
reproduction steps, root cause, and proposed fix.

See `docs/code-review-2026-05.md` for the broader code-smell list.
