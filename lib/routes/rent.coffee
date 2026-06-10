rentService       = require '../services/rent.coffee'
rentModel         = require '../models/rent.coffee'
rentConfiguration = require '../models/rent_configuration.coffee'
{ asyncRoute }    = require '../middleware.coffee'

{ AGREED_MONTHLY_PAYMENT, RENT_DUE_DAY, BASE_RENT, HOURLY_CREDIT, MAX_MONTHLY_HOURS } = require '../config.coffee'


getEffectiveAgreedPayment = ->
  rentConfig = rentConfiguration.getConfiguration()
  if rentConfig?.apply_override and rentConfig?.temporary_rent_amount?
    rentConfig.temporary_rent_amount
  else
    AGREED_MONTHLY_PAYMENT


getDisplayAmountDue = (period) ->
  return period.amount_due if period.amount_due_manual

  now          = new Date()
  currentYear  = now.getFullYear()
  currentMonth = now.getMonth() + 1
  currentDay   = now.getDate()

  isCurrent = period.year is currentYear and period.month is currentMonth
  isFuture  = period.year > currentYear or (period.year is currentYear and period.month > currentMonth)

  agreedPayment = getEffectiveAgreedPayment()

  return period.amount_due                                       if isFuture
  return (if currentDay < RENT_DUE_DAY then 0 else agreedPayment) if isCurrent
  return agreedPayment


getPaymentStatus = (period) ->
  displayDue = getDisplayAmountDue period
  paid       = period.amount_paid or 0

  now         = new Date()
  isCurrent   = period.year is now.getFullYear() and period.month is (now.getMonth() + 1)
  isBeforeDue = isCurrent and now.getDate() < RENT_DUE_DAY

  return 'NOT DUE' if isBeforeDue
  return 'PAID'    if paid >= displayDue
  return 'PARTIAL' if paid > 0
  return 'UNPAID'


decoratePeriod = (period) ->
  Object.assign {}, period,
    display_amount_due:       getDisplayAmountDue(period)
    payment_status:           getPaymentStatus(period)
    effective_agreed_payment: getEffectiveAgreedPayment()


ALLOWED_PERIOD_UPDATE_FIELDS = [
  'manual_adjustments'
  'amount_due'
  'amount_paid'
  'base_rent'
  'hourly_credit'
  'max_monthly_hours'
]


setup = (app) ->
  app.get '/rent/constants', (req, res) ->
    res.json {
      BASE_RENT
      HOURLY_CREDIT
      MAX_MONTHLY_HOURS
      AGREED_MONTHLY_PAYMENT
      RENT_DUE_DAY
    }

  app.get '/rent/configuration', asyncRoute 'rent.getConfiguration', (req, res) ->
    res.json rentConfiguration.getConfiguration()

  app.put '/rent/configuration', asyncRoute 'rent.updateConfiguration', (req, res) ->
    res.json rentConfiguration.updateConfiguration req.body

  app.get '/rent/calculate', asyncRoute 'rent.calculate', (req, res) ->
    now   = new Date()
    year  = parseInt(req.query.year)  or now.getFullYear()
    month = parseInt(req.query.month) or (now.getMonth() + 1)

    res.json await rentService.calculateRent year, month

  app.get '/rent/period/:year/:month', asyncRoute 'rent.getPeriod', (req, res) ->
    year  = parseInt req.params.year
    month = parseInt req.params.month

    period = await rentModel.getRentPeriod year, month
    period ?= await rentService.createOrUpdateRentPeriod year, month

    res.json decoratePeriod period

  app.post '/rent/period/:year/:month', asyncRoute 'rent.createOrUpdatePeriod', (req, res) ->
    year  = parseInt req.params.year
    month = parseInt req.params.month

    res.json await rentService.createOrUpdateRentPeriod year, month

  app.put '/rent/period/:year/:month', asyncRoute 'rent.updatePeriod', (req, res) ->
    year    = parseInt req.params.year
    month   = parseInt req.params.month
    updates = req.body or {}

    filteredUpdates = {}
    for key, value of updates
      filteredUpdates[key] = value if key in ALLOWED_PERIOD_UPDATE_FIELDS

    filteredUpdates.amount_due_manual  = 1 if filteredUpdates.amount_due?
    filteredUpdates.amount_paid_manual = 1 if filteredUpdates.amount_paid?

    unless Object.keys(filteredUpdates).length > 0
      return res.status(400).json error: 'No valid fields to update'

    res.json await rentModel.updateRentPeriod year, month, filteredUpdates

  app.delete '/rent/period/:year/:month', asyncRoute 'rent.deletePeriod', (req, res) ->
    year  = parseInt req.params.year
    month = parseInt req.params.month
    res.json await rentModel.deleteRentPeriod year, month

  app.post '/rent/payment', asyncRoute 'rent.recordPayment', (req, res) ->
    { year, month, amount, payment_method, notes } = req.body

    unless year and month and amount
      return res.status(400).json error: 'Year, month, and amount required'

    res.json rentModel.recordPayment
      year:           parseInt year
      month:          parseInt month
      amount:         parseFloat amount
      payment_method: payment_method
      notes:          notes

  app.get '/rent/summary', asyncRoute 'rent.summary', (req, res) ->
    res.json await rentService.getRentSummary()

  app.post '/rent/recalculate-all', asyncRoute 'rent.recalculateAll', (req, res) ->
    periods = await rentService.recalculateAllRent()
    res.json
      message:         'Recalculation complete'
      periods_updated: periods.length
      periods:         periods

  app.get '/rent/periods', asyncRoute 'rent.getPeriods', (req, res) ->
    periods = await rentModel.getAllRentPeriods()
    res.json periods.map decoratePeriod

  app.get '/rent/events', asyncRoute 'rent.getEvents', (req, res) ->
    { year, month, includeDeleted } = req.query
    showDeleted = includeDeleted is 'true'

    events = if year and month
      rentModel.getRentEventsForPeriod parseInt(year), parseInt(month), showDeleted
    else
      rentModel.getAllRentEvents showDeleted

    res.json events

  app.post '/rent/events', asyncRoute 'rent.createEvent', (req, res) ->
    { type, year, month, amount, description } = req.body

    unless type and year and month and amount and description
      return res.status(400).json error: 'Type, year, month, amount, and description required'

    res.json rentModel.createRentEvent
      type:        type
      date:        req.body.date
      year:        parseInt year
      month:       parseInt month
      amount:      parseFloat amount
      description: description
      notes:       req.body.notes
      metadata:    req.body.metadata or {}

  app.get '/rent/events/:id', asyncRoute 'rent.getEvent', (req, res) ->
    event = rentModel.getRentEvent req.params.id

    unless event
      return res.status(404).json error: 'Event not found'

    res.json event

  app.put '/rent/events/:id', asyncRoute 'rent.updateEvent', (req, res) ->
    { type, date, year, month, amount, description, notes, metadata } = req.body

    res.json rentModel.updateRentEvent req.params.id,
      type:        type
      date:        date
      year:        if year   then parseInt year     else undefined
      month:       if month  then parseInt month    else undefined
      amount:      if amount then parseFloat amount else undefined
      description: description
      notes:       notes
      metadata:    metadata

  app.delete '/rent/events/:id', asyncRoute 'rent.deleteEvent', (req, res) ->
    deletedEvent = rentModel.deleteRentEvent req.params.id
    res.json message: 'Event deleted', event: deletedEvent

  app.post '/rent/events/:id/undelete', asyncRoute 'rent.undeleteEvent', (req, res) ->
    undeletedEvent = rentModel.undeleteRentEvent req.params.id
    res.json message: 'Event undeleted', event: undeletedEvent

  app.get '/rent/audit-logs', asyncRoute 'rent.getAuditLogs', (req, res) ->
    { entity_type, entity_id, action, user } = req.query

    filters = {}
    filters.entity_type = entity_type if entity_type
    filters.entity_id   = entity_id   if entity_id
    filters.action      = action      if action
    filters.user        = user        if user

    res.json rentModel.getAuditLogs filters


module.exports = { setup }
