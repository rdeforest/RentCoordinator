# Rent routes — event-sourced. See docs/event-model.md.
#
# All reads go through period_viewer (which folds events). All writes emit
# events into the events table. The legacy rent_periods / rent_events tables
# are no longer touched here — they remain in the DB only as a fallback
# until the cleanup migration runs.

periodViewer  = require '../services/period_viewer.coffee'
period        = require '../services/period.coffee'
eventsModel   = require '../models/events.coffee'
{ asyncRoute } = require '../middleware.coffee'

{ AGREED_MONTHLY_PAYMENT, RENT_DUE_DAY, BASE_RENT, HOURLY_CREDIT, MAX_MONTHLY_HOURS } =
  require '../config.coffee'


# Map the new period view onto the response shape the front-end already
# consumes. Keeps the wire contract stable while the model changes underneath.
toWireShape = (p) ->
  return null unless p
  Object.assign {}, p,
    amount_due_manual:  if p.amount_due_override  then 1 else 0
    amount_paid_manual: if p.amount_paid_override then 1 else 0
    manual_adjustments: 0   # legacy field; always 0 in the new model


actorFromRequest = (req, fallback = 'landlord') ->
  email = req.session?.email or 'unknown@unknown'
  actor = if email is 'lynz57@hotmail.com' then 'tenant' else fallback
  { actor, actor_user: email }


setup = (app) ->

  # ---- constants & config --------------------------------------------------

  app.get '/rent/constants', (req, res) ->
    res.json { BASE_RENT, HOURLY_CREDIT, MAX_MONTHLY_HOURS, AGREED_MONTHLY_PAYMENT, RENT_DUE_DAY }

  app.get '/rent/configuration', asyncRoute 'rent.getConfiguration', (req, res) ->
    cfg = periodViewer.getConfig()
    # Match the legacy response shape
    res.json
      id:                    'singleton'
      temporary_rent_amount: cfg.temporary_rent_amount
      apply_override:        if cfg.apply_override then 1 else 0

  app.put '/rent/configuration', asyncRoute 'rent.updateConfiguration', (req, res) ->
    { actor, actor_user } = actorFromRequest req, 'landlord'
    now = new Date().toISOString()

    if req.body.temporary_rent_amount?
      eventsModel.recordEvent
        occurred_at: now
        actor:       actor
        actor_user:  actor_user
        action:      'config-changed'
        payload:
          field:     'temporary_rent_amount'
          new_value: req.body.temporary_rent_amount

    if req.body.apply_override?
      eventsModel.recordEvent
        occurred_at: now
        actor:       actor
        actor_user:  actor_user
        action:      'config-changed'
        payload:
          field:     'apply_override'
          new_value: Boolean req.body.apply_override

    cfg = periodViewer.getConfig()
    res.json
      id:                    'singleton'
      temporary_rent_amount: cfg.temporary_rent_amount
      apply_override:        if cfg.apply_override then 1 else 0

  # ---- period reads --------------------------------------------------------

  app.get '/rent/calculate', asyncRoute 'rent.calculate', (req, res) ->
    now   = new Date()
    year  = parseInt(req.query.year)  or now.getFullYear()
    month = parseInt(req.query.month) or (now.getMonth() + 1)
    res.json toWireShape periodViewer.getPeriod year, month

  app.get '/rent/period/:year/:month', asyncRoute 'rent.getPeriod', (req, res) ->
    year  = parseInt req.params.year
    month = parseInt req.params.month
    p     = periodViewer.getPeriod year, month
    # If there's truly no activity for this month, synthesize a zero-state
    # view rather than 404 — the page expects a period object.
    unless p
      p = period.computeMonth year, month, [], 0, 0, new Date()
    res.json toWireShape p

  app.get '/rent/periods', asyncRoute 'rent.getPeriods', (req, res) ->
    periods = periodViewer.getAllPeriods()
    rows = (toWireShape p for key, p of periods)
    rows.sort (a, b) -> (a.year - b.year) or (a.month - b.month)
    res.json rows

  # ---- period writes (overrides) ------------------------------------------

  ALLOWED_OVERRIDE_FIELDS = ['amount_due', 'amount_paid']

  app.post '/rent/period/:year/:month', asyncRoute 'rent.createOrUpdatePeriod', (req, res) ->
    year  = parseInt req.params.year
    month = parseInt req.params.month
    # In the event-sourced model "create or update" a period is a no-op —
    # the view exists implicitly. Just return the current computed value.
    res.json toWireShape (periodViewer.getPeriod(year, month) or
                          period.computeMonth(year, month, [], 0, 0, new Date()))

  app.put '/rent/period/:year/:month', asyncRoute 'rent.updatePeriod', (req, res) ->
    year    = parseInt req.params.year
    month   = parseInt req.params.month
    updates = req.body or {}

    { actor, actor_user } = actorFromRequest req, 'landlord'
    now = new Date().toISOString()
    ymKey = period.monthKey year, month

    for field in ALLOWED_OVERRIDE_FIELDS when updates[field]?
      eventsModel.recordEvent
        occurred_at:   now
        effective_for: ymKey
        actor:         actor
        actor_user:    actor_user
        action:        'override'
        payload:
          target_kind: 'period-field'
          target:      { year, month, field }
          new_value:   updates[field]

    res.json toWireShape periodViewer.getPeriod year, month

  app.delete '/rent/period/:year/:month', asyncRoute 'rent.deletePeriod', (req, res) ->
    # Periods are computed in the new model — deleting one means clearing
    # any override events that target it. Other events (work, payment)
    # remain. The tenant's payment history shouldn't vanish because the
    # landlord 'deleted a period.'
    year  = parseInt req.params.year
    month = parseInt req.params.month
    ymKey = period.monthKey year, month
    { actor, actor_user } = actorFromRequest req, 'landlord'
    now = new Date().toISOString()

    overrides = eventsModel.listEventsByMonth(ymKey).filter (e) ->
      e.action is 'override' and e.payload?.target_kind is 'period-field'

    for o in overrides
      eventsModel.recordEvent
        occurred_at:     now
        effective_for:   ymKey
        actor:           actor
        actor_user:      actor_user
        action:          'deleted'
        target_event_id: o.id
        payload:         { reason: 'Period delete via PUT /rent/period' }

    res.json deleted: true, year: year, month: month

  # ---- payments ------------------------------------------------------------

  app.post '/rent/payment', asyncRoute 'rent.recordPayment', (req, res) ->
    { year, month, amount, payment_method, notes } = req.body

    unless year and month and amount
      return res.status(400).json error: 'Year, month, and amount required'

    ymKey = period.monthKey parseInt(year), parseInt(month)
    { actor, actor_user } = actorFromRequest req, 'tenant'

    event = eventsModel.recordEvent
      occurred_at:   new Date().toISOString()
      effective_for: ymKey
      actor:         actor
      actor_user:    actor_user
      action:        'payment-made'
      payload:
        amount:                   parseFloat amount
        method:                   payment_method or 'manual'
        stripe_payment_intent_id: null
        note:                     notes or null

    res.json
      id:         event.id
      year:       parseInt year
      month:      parseInt month
      amount:     parseFloat amount
      method:     payment_method or 'manual'

  # ---- summary / recalculate ----------------------------------------------

  app.get '/rent/summary', asyncRoute 'rent.summary', (req, res) ->
    periods = periodViewer.getAllPeriods()
    rows    = Object.values periods
    res.json
      total_periods:     rows.length
      total_amount_due:  rows.reduce ((s, p) -> s + p.amount_due),         0
      total_amount_paid: rows.reduce ((s, p) -> s + p.amount_paid),         0
      total_discount:    rows.reduce ((s, p) -> s + p.discount_applied),    0
      outstanding_balance: rows.reduce ((s, p) -> s + p.amount_due - p.amount_paid), 0
      periods:           rows.sort (a, b) -> (a.year - b.year) or (a.month - b.month)

  app.post '/rent/recalculate-all', asyncRoute 'rent.recalculateAll', (req, res) ->
    # Recalculation is implicit in the new model — every GET recomputes.
    # Kept for API stability; returns the current state.
    periods = periodViewer.getAllPeriods()
    rows = (toWireShape p for key, p of periods).sort (a, b) -> (a.year - b.year) or (a.month - b.month)
    res.json
      message:         'Recalculation is on-demand in the new model; current state returned.'
      periods_updated: rows.length
      periods:         rows

  # ---- events CRUD --------------------------------------------------------

  app.get '/rent/events', asyncRoute 'rent.getEvents', (req, res) ->
    { year, month, includeDeleted } = req.query
    showDeleted = includeDeleted is 'true'

    all = eventsModel.listAllEvents()

    # Build set of event ids that are deleted
    deletedIds = new Set()
    for e in all when e.action is 'deleted'
      deletedIds.add e.target_event_id

    filtered = all.filter (e) ->
      return false if e.action in ['edited', 'deleted']
      return false if deletedIds.has(e.id) and not showDeleted
      if year and month
        return e.effective_for is period.monthKey parseInt(year), parseInt(month)
      true

    res.json filtered.map (e) ->
      Object.assign {}, e,
        deleted: deletedIds.has e.id

  app.post '/rent/events', asyncRoute 'rent.createEvent', (req, res) ->
    { type, year, month, amount, description } = req.body

    unless type and year and month and amount and description
      return res.status(400).json error: 'Type, year, month, amount, and description required'

    ymKey = period.monthKey parseInt(year), parseInt(month)
    { actor, actor_user } = actorFromRequest req, 'landlord'

    # Map legacy 'type' onto the new action vocabulary
    action = switch type
      when 'payment'    then 'payment-made'
      when 'adjustment' then 'override'
      when 'manual'     then 'override'
      else 'payment-made'   # safest fallback

    payload =
      if action is 'payment-made'
        amount:                   parseFloat amount
        method:                   req.body.method or 'manual'
        stripe_payment_intent_id: null
        note:                     description
      else
        target_kind: 'period-field'
        target:      { year: parseInt(year), month: parseInt(month), field: 'amount_due' }
        new_value:   parseFloat amount
        note:        description

    event = eventsModel.recordEvent
      occurred_at:   new Date().toISOString()
      effective_for: ymKey
      actor:         actor
      actor_user:    actor_user
      action:        action
      payload:       payload

    res.json event

  app.get '/rent/events/:id', asyncRoute 'rent.getEvent', (req, res) ->
    event = eventsModel.getEvent req.params.id
    unless event
      return res.status(404).json error: 'Event not found'
    res.json event

  app.put '/rent/events/:id', asyncRoute 'rent.updateEvent', (req, res) ->
    existing = eventsModel.getEvent req.params.id
    unless existing
      return res.status(404).json error: 'Event not found'

    { actor, actor_user } = actorFromRequest req, 'landlord'

    new_payload = {}
    new_payload.amount = parseFloat req.body.amount if req.body.amount?
    new_payload.note   = req.body.description if req.body.description?

    eventsModel.recordEvent
      occurred_at:     new Date().toISOString()
      effective_for:   existing.effective_for
      actor:           actor
      actor_user:      actor_user
      action:          'edited'
      target_event_id: existing.id
      payload:         { new_payload }

    res.json eventsModel.getEvent existing.id

  app.delete '/rent/events/:id', asyncRoute 'rent.deleteEvent', (req, res) ->
    existing = eventsModel.getEvent req.params.id
    unless existing
      return res.status(404).json error: 'Event not found'

    { actor, actor_user } = actorFromRequest req, 'landlord'

    eventsModel.recordEvent
      occurred_at:     new Date().toISOString()
      effective_for:   existing.effective_for
      actor:           actor
      actor_user:      actor_user
      action:          'deleted'
      target_event_id: existing.id
      payload:         { reason: req.body?.reason or null }

    res.json message: 'Event deleted', event: existing

  app.post '/rent/events/:id/undelete', asyncRoute 'rent.undeleteEvent', (req, res) ->
    # Undeleting is a delete-of-the-delete-event.
    deletes = eventsModel.listAllEvents().filter (e) ->
      e.action is 'deleted' and e.target_event_id is req.params.id
    unless deletes.length > 0
      return res.status(400).json error: 'Event is not deleted'

    { actor, actor_user } = actorFromRequest req, 'landlord'
    latest = deletes[deletes.length - 1]

    eventsModel.recordEvent
      occurred_at:     new Date().toISOString()
      effective_for:   latest.effective_for
      actor:           actor
      actor_user:      actor_user
      action:          'deleted'
      target_event_id: latest.id
      payload:         { reason: 'Undelete via POST /rent/events/:id/undelete' }

    res.json message: 'Event undeleted', event: eventsModel.getEvent req.params.id

  # ---- audit logs ---------------------------------------------------------

  app.get '/rent/audit-logs', asyncRoute 'rent.getAuditLogs', (req, res) ->
    # The events table IS the audit log. Surface edits and deletes.
    all = eventsModel.listAllEvents()
    audits = all.filter (e) -> e.action in ['edited', 'deleted', 'override']

    res.json audits.map (e) ->
      action:      e.action
      entity_type: 'event'
      entity_id:   e.target_event_id or e.id
      user:        e.actor_user
      changes:     JSON.stringify e.payload
      created_at:  e.occurred_at


module.exports = { setup }
