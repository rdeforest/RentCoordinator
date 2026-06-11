# migrations/2026-06-11_130000_seed_events_from_legacy.coffee
#
# One-time seed: reads the legacy tables (rent_events, work_logs,
# rent_periods.amount_due_manual / amount_paid_manual,
# rent_configuration) and emits equivalent rows into the new events
# table. See docs/event-model.md.
#
# Idempotent by virtue of "skip if events table already has rows."
# Does NOT drop the legacy tables — that's a separate cleanup step
# scheduled after the route rewrite and a verification pass.

{ DatabaseSync } = require 'node:sqlite'
{ v7: uuidv7 }   = require 'uuid'

DB_PATH = process.env.DB_PATH or './tenant-coordinator.db'
db      = new DatabaseSync DB_PATH

console.log "Running migration: seed_events_from_legacy against #{DB_PATH}"


WORKER_TO_USER =
  lyndzie: 'lynz57@hotmail.com'
  robert:  'robert@defore.st'


WORKER_TO_ACTOR =
  lyndzie: 'tenant'
  robert:  'landlord'


monthKey = (year, month) -> "#{year}-#{String(month).padStart 2, '0'}"


monthKeyFromISO = (iso) ->
  d = new Date iso
  monthKey d.getUTCFullYear(), d.getUTCMonth() + 1


insertEvent = (e) ->
  db.prepare("""
    INSERT INTO events
      (id, occurred_at, effective_for, actor, actor_user, action, payload, target_event_id)
    VALUES
      (?, ?, ?, ?, ?, ?, ?, ?)
  """).run(
    e.id or uuidv7()
    e.occurred_at
    e.effective_for or null
    e.actor
    e.actor_user
    e.action
    JSON.stringify(e.payload or {})
    e.target_event_id or null
  )


try
  # Skip if already seeded
  count = db.prepare('SELECT COUNT(*) AS n FROM events').get().n
  if count > 0
    console.log "  events table already has #{count} rows — skipping seed"
    process.exit 0

  db.exec 'BEGIN TRANSACTION'

  emitted = { 'payment-made': 0, 'work-reported': 0, 'override': 0, 'discarded-rent-due': 0 }

  # --- Payments ---------------------------------------------------------------
  # rent_events with type='payment'. Map period_id back to (year,month) for
  # the effective_for field. Skip soft-deleted rows.

  periodById = {}
  for p in db.prepare('SELECT id, year, month FROM rent_periods').all()
    periodById[p.id] = p

  payments = db.prepare("""
    SELECT id, period_id, amount, description, metadata, created_at, deleted_at
    FROM rent_events
    WHERE type = 'payment' AND deleted_at IS NULL
    ORDER BY created_at
  """).all()

  for p in payments
    period = periodById[p.period_id]
    unless period
      console.log "  payment #{p.id} references missing period #{p.period_id} — skipping"
      continue

    meta = if p.metadata then JSON.parse p.metadata else {}
    insertEvent
      id:            p.id  # preserve original id so audit links survive
      occurred_at:   p.created_at
      effective_for: monthKey period.year, period.month
      actor:         'tenant'
      actor_user:    'lynz57@hotmail.com'
      action:        'payment-made'
      payload:
        amount:                   Math.abs p.amount   # payments stored as positive in new model
        method:                   meta?.method or 'unknown'
        stripe_payment_intent_id: meta?.payment_intent_id or null
        note:                     p.description or null
    emitted['payment-made'] += 1

  # --- Phantom rent_due events ------------------------------------------------
  # Old "Rent due for X" events (both type='rent_due' and type='manual' with
  # metadata.category='rent_due') are discarded. BASE_RENT alone represents
  # "rent is owed" in the new model.

  phantom_rent_due = db.prepare("""
    SELECT id, type, metadata FROM rent_events WHERE deleted_at IS NULL
  """).all()
  for row in phantom_rent_due
    meta = if row.metadata then JSON.parse row.metadata else {}
    if row.type is 'rent_due' or (row.type is 'manual' and meta?.category is 'rent_due')
      emitted['discarded-rent-due'] += 1

  # --- Work logs --------------------------------------------------------------
  # work_logs become work-reported events. Worker maps to actor/actor_user.
  # Robert's stray work_log (~10 minutes) becomes an actor='landlord' event,
  # which the calc filters out — so the data is preserved but doesn't shift
  # the credit math.

  logs = db.prepare("""
    SELECT id, worker, start_time, end_time, duration, project_id, task_id, description
    FROM work_logs
    ORDER BY start_time
  """).all()

  for log in logs
    actor      = WORKER_TO_ACTOR[log.worker] or 'tenant'
    actor_user = WORKER_TO_USER[log.worker]  or "unknown@unknown"
    insertEvent
      id:            log.id
      occurred_at:   log.start_time
      effective_for: monthKeyFromISO log.start_time
      actor:         actor
      actor_user:    actor_user
      action:        'work-reported'
      payload:
        hours:      (log.duration or 0) / 60
        started_at: log.start_time
        ended_at:   log.end_time
        project:    log.project_id   or null
        task:       log.task_id      or null
        note:       log.description  or null
    emitted['work-reported'] += 1

  # --- Overrides --------------------------------------------------------------
  # rent_periods with amount_due_manual=1 (or amount_paid_manual=1) become
  # period-field override events.

  overridden = db.prepare("""
    SELECT id, year, month, amount_due, amount_due_manual,
           amount_paid, amount_paid_manual, updated_at
    FROM rent_periods
    WHERE amount_due_manual = 1 OR amount_paid_manual = 1
    ORDER BY year, month
  """).all()

  for p in overridden
    if p.amount_due_manual
      insertEvent
        occurred_at:   p.updated_at
        effective_for: monthKey p.year, p.month
        actor:         'landlord'
        actor_user:    'robert@defore.st'
        action:        'override'
        payload:
          target_kind: 'period-field'
          target:      { year: p.year, month: p.month, field: 'amount_due' }
          new_value:   p.amount_due
          note:        "Seeded from rent_periods.amount_due_manual"
      emitted['override'] += 1

    if p.amount_paid_manual
      insertEvent
        occurred_at:   p.updated_at
        effective_for: monthKey p.year, p.month
        actor:         'landlord'
        actor_user:    'robert@defore.st'
        action:        'override'
        payload:
          target_kind: 'period-field'
          target:      { year: p.year, month: p.month, field: 'amount_paid' }
          new_value:   p.amount_paid
          note:        "Seeded from rent_periods.amount_paid_manual"
      emitted['override'] += 1

  # --- Config -----------------------------------------------------------------
  # rent_configuration: emit a config-changed event for each non-default field.

  cfg = db.prepare('SELECT * FROM rent_configuration WHERE id = ?').get 'singleton'
  if cfg
    if cfg.temporary_rent_amount?
      insertEvent
        occurred_at: cfg.updated_at
        actor:       'landlord'
        actor_user:  'robert@defore.st'
        action:      'config-changed'
        payload:     { field: 'temporary_rent_amount', new_value: cfg.temporary_rent_amount, note: 'Seeded from rent_configuration' }
    if cfg.apply_override
      insertEvent
        occurred_at: cfg.updated_at
        actor:       'landlord'
        actor_user:  'robert@defore.st'
        action:      'config-changed'
        payload:     { field: 'apply_override', new_value: true, note: 'Seeded from rent_configuration' }

  # --- Disable the "Monthly Rent Due" recurring template ---------------------
  # In the new model BASE_RENT alone represents "rent is owed." This template
  # is what was creating the phantom -$1600 events that caused the May/June
  # double-count bug. Disable it so no further phantoms get created.

  result = db.prepare("""
    UPDATE recurring_events
    SET active = 0
    WHERE description LIKE '%rent due%' OR description LIKE '%Rent Due%' OR type = 'rent_due'
  """).run()
  disabled = result.changes

  db.exec 'COMMIT'

  console.log "Migration completed successfully:"
  console.log "  payment-made:       #{emitted['payment-made']}"
  console.log "  work-reported:      #{emitted['work-reported']}"
  console.log "  override:           #{emitted['override']}"
  console.log "  discarded rent_due: #{emitted['discarded-rent-due']}"
  console.log "  recurring templates disabled: #{disabled}"

catch err
  console.error 'Migration failed:', err.message
  console.error err.stack
  try
    db.exec 'ROLLBACK'
  throw err

finally
  db.close()
