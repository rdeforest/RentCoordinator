# Event Model

**Status:** design — not yet implemented.
**Supersedes:** the current persisted-period model (see "What this replaces" below).

## Why

The current data model persists computed answers (`rent_periods.amount_due`,
`amount_paid`, `discount_applied`, …) alongside the facts those answers are
derived from. To protect a hand-edited answer from being overwritten on the
next recalc, the schema grew `amount_due_manual` / `amount_paid_manual`
flags. To represent "rent is due for this month," a recurring template
creates a `type='manual', amount=-1600` event — which the calc then
double-counts against `BASE_RENT`. Both of these are symptoms of the same
underlying problem: the schema mixes facts and conclusions in the same
rows.

In an app with two users and no performance pressure, the answer is to
keep only facts, and compute everything else on demand.

## The events table

```
events
  id                    TEXT PRIMARY KEY              (uuid v7 so id sorts by time)
  occurred_at           DATETIME NOT NULL             (when the event actually happened)
  effective_for         TEXT                          ('YYYY-MM' the event applies to,
                                                       NULL when it applies globally;
                                                       differs from occurred_at when a
                                                       landlord retroactively targets
                                                       a past month)
  actor                 TEXT NOT NULL                 ('tenant' | 'landlord')
  actor_user            TEXT NOT NULL                 (email; 'robert@…' / 'lynz57@…')
  action                TEXT NOT NULL                 (see below)
  payload               TEXT NOT NULL                 (JSON; shape depends on action)
  target_event_id       TEXT                          (FK events.id when this event
                                                       acts on another event)
  created_at            DATETIME DEFAULT CURRENT_TIMESTAMP

  INDEX  events_effective_for
  INDEX  events_actor_user
  INDEX  events_target_event_id
```

No `updated_at`, no `deleted_at`. Events are immutable. To change an event,
emit an `edited` or `deleted` event referencing it.

## Actions

Seven kinds. The third column says which payload fields are required.

| action                | actor    | payload                                              |
|-----------------------|----------|------------------------------------------------------|
| `work-reported`       | tenant   | `{hours, started_at, ended_at, project, note?}`      |
| `payment-made`        | tenant   | `{amount, method, stripe_payment_intent_id?, note?}` |
| `config-changed`      | landlord | `{field, new_value, note?}`                          |
| `work-acknowledged`   | landlord | `{}` — `target_event_id` points at the work-reported |
| `override`            | landlord | `{target_kind, target, new_value, note?}`            |
| `edited`              | either   | `{new_payload}` — `target_event_id` set              |
| `deleted`             | either   | `{reason?}` — `target_event_id` set                  |

### `override` payload detail

`target_kind` is either `'event'` or `'period-field'`.

When `target_kind = 'event'`, `target_event_id` is set and `new_value`
replaces the *amount* on that event for calculation purposes. (Used when
the landlord adjusts a payment or a work-reported entry the tenant
submitted.)

When `target_kind = 'period-field'`, `target` is `{year, month, field}`
where `field ∈ {amount_due, amount_paid}`. `new_value` is the pinned
amount. (Used when the landlord wants "for May 2026, the bottom line is
$X" regardless of what the calc would say. Replaces today's
`amount_due_manual` mechanism.)

### Why `edited` / `deleted` are events, not row mutations

Two reasons:

1. *I thought I fixed that* — if rows are mutated in place, the question
   "when did this $X become $Y, and who did it?" requires `audit_logs`,
   which can drift from the actual row state. Edits as events answer the
   question by definition.
2. *Soft-delete already exists* on rent_events today and the rest of the
   code has to know about `WHERE deleted_at IS NULL`. Edits-as-events is
   the same shape (skip events whose `target_event_id` appears as a
   `deleted` event's target) and removes the special column from the
   schema entirely.

## How computation works

A single function:

```
computePeriod(year, month) → {
  hours_worked, hours_from_previous, hours_to_next,
  hours_applied, discount_applied, retroactive_credit,
  base_rent, agreed_payment, amount_due, amount_paid,
  payment_status, display_amount_due
}
```

Algorithm:

1. Resolve `configAt(end-of-month)` — fold all `config-changed` events with
   `occurred_at ≤ end-of-month` into a config snapshot.
2. Build a set of "effective" events: every event whose `effective_for`
   matches this month *or* an earlier month (for retroactive credit
   carry-over), excluding any event that's a `deleted` target.
3. For each non-deleted, non-edit/delete event, resolve its current value
   by walking forward through any `edited` events targeting it (last write
   wins).
4. Sum `work-reported.hours` per month → `hours_worked[m]`.
5. Walk months in chronological order, applying the cap-and-carry rule
   plus retroactive credit retiring prior shortfalls (current logic in
   `services/rent.coffee::recalculateAllRent`, lines 64-139 — the math is
   right; the persistence is what we drop).
6. Sum `payment-made.amount` for the month → `amount_paid`.
7. Apply any `override` events with `target_kind='period-field'` matching
   this period.
8. Return.

The function is pure given the events table and the current date. No
writes. Tests become fold-events-and-assert.

### Caching

Not now. Two users, fewer than 2000 events expected over the app's
lifetime, SQLite indexed reads. When (if) a real perf problem shows up:
memoize `computePeriod(year, month)` keyed by
`(year, month, max(events.id) WHERE effective_for ≤ month)`. The id is a
uuid v7 so it sorts by time; appending an event for that month or earlier
changes the key automatically.

## What this replaces

**Deleted from the schema:**
- `rent_periods` table — every column except `(year, month)` was a
  computed answer.
- `amount_due_manual`, `amount_paid_manual` flags — replaced by override
  events.
- `rent_events.deleted_at` column — replaced by `deleted` events.
- `rent_events.type` field — too generic, and `'manual'` was overloaded.
  Subsumed by `events.action`.
- `audit_logs` table — the event log *is* the audit log.

**Disabled, kept around for general use:**
- `recurring_events` mechanism — fine for future recurring charges
  (utilities, etc.). The specific "Monthly Rent Due" template is removed
  — `config.BASE_RENT` (now sourced from config events) is the source of
  truth for "rent is due."

**Unchanged:**
- `work_logs` — already an event log; treat each row as a `work-reported`
  event in the new model. (See migration note: we *could* fold work_logs
  rows into the events table outright, or keep work_logs as a typed view
  of the work-reported events. Leaning fold-in for a single source of
  truth.)
- `rent_configuration` — replaced by `config-changed` events. The current
  singleton row becomes the seed event.

## Migration

One-time seed script. Reads the current DB, writes events, drops the
no-longer-needed tables in the same transaction. The migration is
**not** idempotent in the usual sense — it's a one-way conversion that
detects "already migrated" by the presence of the `events` table.

Concretely:

1. `CREATE TABLE events …` (new).
2. For each row in `rent_configuration`: one `config-changed` event per
   non-null field, `occurred_at = updated_at`, `actor = landlord`,
   `actor_user = robert@defore.st`.
3. For each row in `work_logs`: one `work-reported` event,
   `occurred_at = start_time`, `effective_for = YYYY-MM of start_time`,
   `actor = tenant`, `actor_user = lynz57@hotmail.com`.
4. For each row in `rent_events` where `type = 'payment'`: one
   `payment-made` event.
5. For each row in `rent_events` where `type IN ('manual', 'adjustment')`
   AND `metadata.category != 'rent_due'`: one event mapped to the closest
   action. (Hand-inspect; should be a small list.)
6. For each row in `rent_events` where `metadata.category = 'rent_due'`:
   **discard** — these are the phantom events that caused today's bug.
7. For each row in `rent_periods` with `amount_due_manual = 1`: one
   `override` event with `target_kind='period-field'`,
   `target={year, month, field:'amount_due'}`, `new_value=amount_due`.
   Same for `amount_paid_manual`.
8. Drop `rent_periods`, `rent_events`, `audit_logs`, `rent_configuration`.
9. Disable the "Monthly Rent Due" entry in `recurring_events` (set
   `active=0`).

After the migration, `computePeriod` against the new events table should
return values that match what the UI currently shows for known-correct
months (April 2026: $1200) and the values it *should* show for known-bad
months (May/June: $1200, not -$400).

## Verification gate

The seed migration is the only place where current data crosses the
boundary. Before deploying:

1. Snapshot the current DB.
2. Run the migration locally.
3. For every month in 2025-04 .. 2026-06, assert
   `computePeriod(year, month).amount_due` equals the value the user
   expects (April-06 = $1200, May-06 = $1200, June-06 = before-the-15th
   value, etc.).
4. For each month, assert `amount_paid` matches the sum of
   `payment-made` events.

If the asserts pass, the seed is sound. Deploy.
