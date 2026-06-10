# Code Review — May 2026

Snapshot of a review conducted 2026-05-19. The per-bug detail and proposed
fixes live in `docs/bugs/` and `docs/fixes/`; this file is the narrative
summary and the catalog of structural concerns that aren't tied to a
specific bug ticket.

## Active bugs

See `docs/bugs/` for the working list. As of this review:

- **01** — Periods table shows raw amount instead of stress-free display
- **02** — Cannot delete rent period (FK constraint)
- **03** — Soft-delete UI wired to hard-delete model
- **04** — Lyndzie's hours not appearing in rent periods
- **05** — Recalculate-all discards retroactive logic

## Code smells & structural concerns

These aren't bugs in the sense that they break user-visible behavior, but
they're the things most likely to bite during future work.

### 3.1 The two `payment*` files are confusing

`lib/routes/payment.coffee` handles Stripe checkout flow (create-intent,
confirm). `lib/routes/payments.coffee` handles a payment history view
(list, reassign, delete). Same problem for `static/payment.html` /
`static/payments.html` and the corresponding `.coffee` files.

The URL schemes also disagree: `payments.coffee` uses `/v1/api/payments`
while `payment.coffee` uses `/payment/...`.

**Suggestion:** rename for clarity. `routes/stripe.coffee` and
`routes/payment_history.coffee` would be clearer. Pick one URL scheme.

### 3.2 The `recurring_events` table is doing two jobs

The model code constantly translates between the schema's columns
(`type`, `description`, `frequency`, `day_of_month`, `active`, `metadata`)
and the application's richer mental model (`event_type`, `name`,
`day_of_week`, `time_of_day`, `event_template`, `next_due`, `enabled`).
Most of the application-model fields live inside the JSON `metadata`
column.

There's an explicit `XXX` comment in `createProcessingLog` about the
schema not matching what the code wants to store. Eventually, evolve the
schema to match the application model.

### 3.3 SQL parameter binding inconsistency

- `work_log.coffee::createWorkLog` uses named bindings (`:id`, `:worker`)
- `rent.coffee::createRentPeriod` uses positional bindings (`?`)

Named bindings are much safer with the kind of column count `rent_periods`
has. `lib/db/utils.coffee::formatSQLParameters` exists for exactly this —
promote it everywhere.

### 3.4 `getAllRentEvents` ignores its `includeDeleted` parameter

(Fixed as part of bug #03's soft-delete work.)

### 3.5 No transaction wrappers around multi-statement operations

`createRentEvent` does (1) INSERT into `rent_events` and (2) call
`createAuditLog` (another INSERT). If step 1 succeeds and step 2 fails,
you have a rent event with no audit trail. Same problem in `recordPayment`
and `deleteRentEvent`. Wrap multi-statement business operations in
`db.exec 'BEGIN'` / `COMMIT` / `ROLLBACK`.

### 3.6 `async`/`await` used inconsistently

`node:sqlite` is synchronous, but the model layer is sprinkled with `async`
and `await` in places where nothing actually returns a Promise. This adds
no concurrency benefit and obscures whether things can actually fail
concurrently. Either commit to sync or commit to async, but be consistent.

### 3.7 Hard-coded constants duplicated

- `AGREED_MONTHLY_PAYMENT = 950` in `lib/routes/rent.coffee` AND
  `static/coffee/rent.coffee`
- `RENT_DUE_DAY = 15` in the same two places
- `BASE_RENT`, `HOURLY_CREDIT`, `MAX_MONTHLY_HOURS` in `config.coffee`
  AND re-defaulted in `services/rent.coffee` (the `or 1600` fallbacks
  are unreachable)

For the front-end duplication: serve these constants via
`/rent/configuration` and have the front-end fetch them. One source of
truth.

### 3.8 Stress-free display logic lives in two places

Both `lib/routes/rent.coffee::getDisplayAmountDue` and
`static/coffee/rent.coffee::getDisplayAmountDue` exist. The frontend one
is now a thin wrapper around `period.display_amount_due` from the server,
which is good. But `getPaymentStatus` in the frontend re-derives the
"current month, before 15th" logic that lives server-side too.

**Cleanup:** add `payment_status` to the server's response. Any
user-facing money decision should be made server-side and shipped to the
client as a display-ready value.

### 3.9 No tests for the rent flow

The known bugs include calculation issues, and `npm test` runs one file:
`test/services/rent.coffee`. Given that the rent calculation has
overlapping concerns (hours, carry-over, retroactive, manual adjustments,
payments, configuration override), this is where unit tests would pay
for themselves quickly.

Concrete starting points:

- `calculateRent` with: no work logs / partial month / over-cap /
  carry-over from previous / configuration override active / manual
  adjustments / negative payments
- `recalculateAllRent`: empty DB / single month / multi-month shortfall
  recovery (covers bug #05)
- `getDisplayAmountDue` with frozen "current date" for: past / current
  before 15 / current after 15 / future / manual override on

Each is ~10 lines with `node:test`. Half a day's work covers the most
business-critical logic.

### 3.10 Logger usage uneven

Some routes call `logger.error` in their catch blocks; others log nothing.
A small async-route wrapper would eliminate the per-route try/catch and
make logging uniform:

```coffee
# lib/middleware.coffee
asyncRoute = (name, handler) -> (req, res) ->
  try
    await handler req, res
  catch err
    logger.error name, err, { body: req.body, query: req.query, params: req.params }, req.id
    statusCode = if err.message?.includes 'not found' then 404 else 500
    res.status(statusCode).json error: err.message
```

### 3.11 No frontend module system

`static/coffee/rent.coffee` is a 600-line top-level script with
module-globals and `window.foo = ->` exports for inline `onclick`
handlers. Works but fragile. The defensive double-filter in
`renderEventsTable` for "malformed events" is a symptom of this — the
real bug is that `event.date` isn't a column on `rent_events`, but
nothing in the front-end's structure makes that obvious.

**Incremental cleanups:**
- Replace `onclick="..."` strings with `addEventListener`
- Group module state into a single object
- Move `formatCurrency`, `formatDate`, `formatMonthYear`, `escapeHtml`
  into `static/coffee/shared-utils.coffee` (which already exists!)

### 3.12 No CI

Tests exist; nothing runs them automatically. Even a basic GitHub Action
that runs `npm test` and `npm run test:integration` on push would have
caught at least bug #03 (which any test exercising the undelete route
would have hit immediately).

## Documentation findings

### Stale or wrong

- **CLAUDE.md "Project Structure"** is missing several files that exist:
  `lib/logger.coffee`, `lib/services/payment.coffee`,
  `lib/services/tokenization.coffee`,
  `lib/models/rent_configuration.coffee`,
  `lib/routes/admin.coffee`, `lib/routes/payment.coffee`,
  `lib/routes/payments.coffee`, `lib/routes/backup.coffee`.
- **CLAUDE.md says** `migrations/` is "empty for now". It's not.
- **SSH user disagreement.** CLAUDE.md says `admin@<INSTANCE_IP>`; the
  migrations README says `ubuntu@<INSTANCE_IP>`. Pick one.
- **`docs/README.md`** describes frontend as "Vanilla JavaScript,
  CoffeeScript" — actually CoffeeScript-compiled-to-JS.
- **`docs/README.md` "Recent Updates"** dated 2025-12-29 — move to a
  CHANGELOG.md or remove dates.
- **GitHub path in CLAUDE.md** — repo is at `rdeforest/RentCoordinator`,
  not `thatsnice/RentCoordinator`.

### Newly added in this review

- `docs/architecture.md` — the missing one-page tour
- `docs/bugs/` — one file per known issue
- `docs/fixes/` — proposed patches for each bug
- This review file

### Still missing

- `docs/development.md` — local-dev quickstart (env vars, troubleshooting)
- `docs/data-model.md` — could be promoted from `docs/architecture.md`'s
  Data Model section if it grows
- `docs/decision-log.md` — ADRs for the structural choices (SQLite,
  CoffeeScript, no migration framework, etc.)
- A test plan describing what's covered and what isn't

## On working with AI coding assistants

A pattern visible in the codebase: defense-on-top-of-defense. The
clearest example is the double null-check filter in `renderEventsTable`:

```coffee
events = events.filter (event) ->
  event.type? and event.date? and event.year? and event.month? and
  event.amount? and event.description? and event.id?
# ...later, inside the same call chain...
validEvents = events.filter (event) ->
  event.type? and event.date? and event.year? and event.month? and
  event.amount? and event.description? and event.id?
```

Two identical filters back-to-back is what you get when symptom-fixing
"undefined errors" without understanding why the events are malformed.
The real reason: `event.date` isn't a column on `rent_events`. The
filters hide that fact rather than reveal it.

The structural lesson isn't "AI tools are bad at this" — it's that
point-fix conversations tend to produce point-fixes, and code accumulates
defensive scar tissue when the diagnostic step is skipped. The mitigation
is to occasionally do a wider read of the codebase and remove the scar
tissue once the structural issue is found.

(See also the discussion of Claude Code settings in your conversation
notes — same pattern, slightly different framing.)
