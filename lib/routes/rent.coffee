# Rent routes — event-sourced. See docs/event-model.md.
#
# All reads go through period_viewer (which folds events). All writes emit
# events into the events table. The legacy rent_periods / rent_events tables
# are no longer touched here — they remain in the DB only as a fallback
# until the cleanup migration runs.

periodViewer  = require '../services/period_viewer.coffee'
period        = require '../services/period.coffee'
eventsModel   = require '../models/events.coffee'
{ transaction } = require '../db/utils.coffee'
money         = require '../money.coffee'
{ asyncRoute } = require '../middleware.coffee'

config = require '../config.coffee'
{ AGREED_MONTHLY_PAYMENT, RENT_DUE_DAY, BASE_RENT, HOURLY_CREDIT, MAX_MONTHLY_HOURS } = config


# Map the new period view onto the response shape the front-end already
# consumes. Keeps the wire contract stable while the model changes underneath.
toWireShape = (p) ->
  return null unless p
  Object.assign {}, p,
    amount_due_manual:  if p.amount_due_override  then 1 else 0
    amount_paid_manual: if p.amount_paid_override then 1 else 0
    manual_adjustments: 0   # legacy field; always 0 in the new model


# Project a folded event onto the flat shape the events table + editor expect
# (the legacy rent_events shape). Inverse of the POST /rent/events mapping.
# Only financial events (payment-made, override) get an `amount`; for other
# actions it's undefined, so the client's amount guard hides them — matching
# the old "Rent Events" table, which only ever listed financial entries.
eventToWireShape = (e, deleted) ->
  [year, month] =
    if e.effective_for
      e.effective_for.split('-').map (n) -> parseInt n, 10
    else
      [undefined, undefined]

  type = switch e.action
    when 'payment-made' then 'payment'
    when 'adjustment'   then 'adjustment'
    when 'override'     then 'manual'
    else e.action

  amount = e.payload?[AMOUNT_FIELD[e.action]]

  Object.assign {}, e,
    type:        type
    date:        e.occurred_at
    year:        year
    month:       month
    amount:      amount
    description: e.payload?.note or ''
    deleted:     deleted


# The legacy 'type' the client sends, mapped onto the event vocabulary.
# 'adjustment' moves the amount due by a delta; 'manual' pins it absolutely.
# Conflating the two is what made a $100 late fee leave a month owing $100
# instead of $1,700 (bug 14).
EVENT_TYPE_ACTIONS =
  payment:    'payment-made'
  adjustment: 'adjustment'
  manual:     'override'


# Where each action keeps its number. One table, so the write path, the read
# projection and the edit path cannot disagree about it.
AMOUNT_FIELD =
  'payment-made': 'amount'
  'adjustment':   'delta'
  'override':     'new_value'


buildEventPayload = (action, body) ->
  amount = parseFloat body.amount
  target = { year: parseInt(body.year), month: parseInt(body.month), field: 'amount_due' }

  switch action
    when 'payment-made'
      amount:                   amount
      method:                   body.method or 'manual'
      stripe_payment_intent_id: null
      note:                     body.description
    when 'adjustment'
      target_kind: 'period-field'
      target:      target
      delta:       amount
      note:        body.description
    when 'override'
      target_kind: 'period-field'
      target:      target
      new_value:   amount
      note:        body.description


actorFromRequest = (req, fallback = 'landlord') ->
  email = req.session?.email or 'unknown@unknown'
  actor = if config.normalizeEmail(email) is config.TENANT_EMAIL then 'tenant' else fallback
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

    changes = []

    # Presence, not non-null: the client sends an explicit null to clear the
    # override amount, and a null check silently discarded it (bug 20).
    if 'temporary_rent_amount' of req.body
      amount = req.body.temporary_rent_amount

      if amount? and not Number.isFinite amount
        return res.status(400).json
          error: "temporary_rent_amount must be a number or null, got #{JSON.stringify amount}"

      changes.push field: 'temporary_rent_amount', new_value: amount

    if req.body.apply_override?
      changes.push field: 'apply_override', new_value: Boolean req.body.apply_override

    # Both together or neither: written separately, a rejection of the second
    # left the first committed and told the caller the request had failed.
    transaction ->
      for change in changes
        eventsModel.recordEvent
          occurred_at: now
          actor:       actor
          actor_user:  actor_user
          action:      'config-changed'
          payload:     change

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
    includeSuppressed = req.query.includeSuppressed is 'true'
    periods = periodViewer.getAllPeriods({ includeSuppressed })
    rows = (toWireShape p for key, p of periods)
    # Newest first — matches the legacy ORDER BY year DESC, month DESC.
    rows.sort (a, b) -> (b.year - a.year) or (b.month - a.month)
    res.json rows

  # Total outstanding across every month that's actually due. Used by the
  # "Pay Rent Online" flow so the tenant sees one combined number rather
  # than one month at a time. Months still in NOT DUE status (current month
  # before the 15th) are excluded — they can be paid early but they aren't
  # part of the "what do I owe" total.
  app.get '/rent/outstanding', asyncRoute 'rent.getOutstanding', (req, res) ->
    { total, months } = periodViewer.computeOutstanding()
    res.json total_outstanding: total, months: months

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
          new_value:   parseFloat updates[field]

    res.json toWireShape periodViewer.getPeriod year, month

  app.delete '/rent/period/:year/:month', asyncRoute 'rent.deletePeriod', (req, res) ->
    # In the event-sourced model a period is a derived view: it exists for
    # every month that has events with that effective_for. "Deleting" a
    # period therefore can't mean "remove the events" — those are facts
    # (work was reported, payments were made). What the landlord actually
    # wants is "this month isn't part of the rent arrangement; hide it
    # from the dashboard." We express that as a period-suppressed event.
    # Work hours still carry over to the next month; the row just doesn't
    # show. Reversible by deleting (or undeleting) the suppression event.
    year  = parseInt req.params.year
    month = parseInt req.params.month
    ymKey = period.monthKey year, month
    { actor, actor_user } = actorFromRequest req, 'landlord'

    eventsModel.recordEvent
      occurred_at:   new Date().toISOString()
      effective_for: ymKey
      actor:         actor
      actor_user:    actor_user
      action:        'period-suppressed'
      payload:       { reason: req.body?.reason or 'Period removed from dashboard' }

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
    # One clock for both: computed separately, the rows and the total could
    # land on opposite sides of the due date.
    now     = new Date()
    periods = periodViewer.getAllPeriods {}, now
    rows    = Object.values periods
    # display_amount_due, not amount_due: the summary has to agree with the
    # rows beneath it and with /rent/outstanding. Summing the raw value put
    # the full base rent into "outstanding" the moment a month began, which
    # is the "$1,600 overdue!" the display logic exists to avoid (bug 18).
    #
    # outstanding_balance comes from computeOutstanding, which also excludes
    # months still NOT DUE — so it now matches /rent/outstanding exactly
    # rather than approximately.
    res.json
      total_periods:       rows.length
      total_amount_due:    money.dollars rows.reduce ((s, p) -> s + p.display_amount_due), 0
      total_amount_paid:   money.dollars rows.reduce ((s, p) -> s + p.amount_paid),        0
      total_discount:      money.dollars rows.reduce ((s, p) -> s + p.discount_applied),   0
      outstanding_balance: periodViewer.computeOutstanding(now).total
      periods:             rows.sort (a, b) -> (a.year - b.year) or (a.month - b.month)

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

    all        = eventsModel.listAllEvents()
    deletedIds = period.deletedEventIds all

    # Fold edits in, the way the period math does. Listing the raw events meant
    # an edited amount or note never showed here, so the table and the ledger
    # disagreed about the same event.
    #
    # Edits are applied without dropping deletes: resolveEditsAndDeletes
    # removes deleted rows from its map, so using it here showed the raw,
    # pre-edit payload for exactly the rows includeDeleted exists to inspect —
    # the same event displaying two different amounts depending on the toggle.
    edited = new Map ([e.id, e] for e in period.applyEdits all)
    visible = (edited.get(e.id) ? e for e in all when e.action not in period.META_ACTIONS)

    filtered = visible.filter (e) ->
      return false if deletedIds.has(e.id) and not showDeleted
      if year and month
        return e.effective_for is period.monthKey parseInt(year), parseInt(month)
      true

    res.json filtered.map (e) ->
      eventToWireShape e, deletedIds.has e.id

  app.post '/rent/events', asyncRoute 'rent.createEvent', (req, res) ->
    { type, year, month, amount, description } = req.body

    unless type and year and month and amount and description
      return res.status(400).json error: 'Type, year, month, amount, and description required'

    ymKey = period.monthKey parseInt(year), parseInt(month)
    { actor, actor_user } = actorFromRequest req, 'landlord'

    action = EVENT_TYPE_ACTIONS[type]

    # Defaulting an unrecognized type to 'payment-made' fabricated a payment
    # nobody made (bug 15). An unknown type is a client bug; say so.
    unless action
      return res.status(400).json
        error: "Unknown event type: #{type}"
        known: Object.keys EVENT_TYPE_ACTIONS

    payload = buildEventPayload action, req.body

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

    # The key that holds the number depends on the action: a payment has
    # `amount`, an adjustment a `delta`, an override a `new_value`. Writing
    # `amount` unconditionally meant an edit merged a key nothing reads, and
    # the event kept its original figure while the UI reported success.
    #
    # An action with no amount at all — work-reported, config-changed,
    # period-suppressed — is a 400 rather than a key named "undefined" merged
    # permanently onto the event.
    amountField = AMOUNT_FIELD[existing.action]

    if req.body.amount? and not amountField
      return res.status(400).json
        error: "#{existing.action} events have no editable amount"

    if req.body.amount? and not Number.isFinite parseFloat req.body.amount
      return res.status(400).json
        error: "Amount must be a number, got #{JSON.stringify req.body.amount}"

    new_payload = {}
    new_payload[amountField] = parseFloat req.body.amount if req.body.amount?
    new_payload.note         = req.body.description if req.body.description?

    unless Object.keys(new_payload).length > 0
      return res.status(400).json error: 'Nothing to change'

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
    # Undelete used to mean "delete the delete event", which the fold never
    # saw: its byId map only ever held non-meta events, so removing a delete
    # event's id removed nothing (bug 16). An `undeleted` event targeting the
    # original is something both the fold and the events list understand.
    existing = eventsModel.getEvent req.params.id
    unless existing
      return res.status(404).json error: 'Event not found'

    unless period.deletedEventIds(eventsModel.listAllEvents()).has existing.id
      return res.status(400).json error: 'Event is not deleted'

    { actor, actor_user } = actorFromRequest req, 'landlord'

    eventsModel.recordEvent
      occurred_at:     new Date().toISOString()
      effective_for:   existing.effective_for
      actor:           actor
      actor_user:      actor_user
      action:          'undeleted'
      target_event_id: existing.id
      payload:         { reason: req.body?.reason or null }

    res.json message: 'Event undeleted', event: eventsModel.getEvent existing.id

  # ---- audit logs ---------------------------------------------------------

  app.get '/rent/audit-logs', asyncRoute 'rent.getAuditLogs', (req, res) ->
    # The events table IS the audit log. Surface edits and deletes.
    all = eventsModel.listAllEvents()
    audits = all.filter (e) -> e.action in [period.META_ACTIONS..., 'override', 'adjustment']

    res.json audits.map (e) ->
      action:      e.action
      entity_type: 'event'
      entity_id:   e.target_event_id or e.id
      user:        e.actor_user
      changes:     JSON.stringify e.payload
      created_at:  e.occurred_at


module.exports = { setup }
