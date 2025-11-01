rentService = require '../services/rent.coffee'
rentModel   = require '../models/rent.coffee'


setup = (app) ->
  app.get '/rent/calculate', (req, res) ->
    { year, month } = req.query

    now   = new Date()
    year  = parseInt(year) or now.getFullYear()
    month = parseInt(month) or (now.getMonth() + 1)

    try
      calculation = await rentService.calculateRent year, month
      res.json calculation
    catch err
      res.status(500).json error: err.message

  app.get '/rent/period/:year/:month', (req, res) ->
    year  = parseInt req.params.year
    month = parseInt req.params.month

    try
      period = await rentModel.getRentPeriod year, month

      unless period
        period = await rentService.createOrUpdateRentPeriod year, month

      res.json period
    catch err
      res.status(500).json error: err.message

  app.post '/rent/period/:year/:month', (req, res) ->
    year  = parseInt req.params.year
    month = parseInt req.params.month

    try
      period = await rentService.createOrUpdateRentPeriod year, month
      res.json period
    catch err
      res.status(500).json error: err.message

  app.put '/rent/period/:year/:month', (req, res) ->
    year  = parseInt req.params.year
    month = parseInt req.params.month
    updates = req.body

    unless updates and Object.keys(updates).length > 0
      return res.status(400).json error: 'No updates provided'

    try
      # Only allow updating specific fields
      allowedFields = [
        'manual_adjustments'
        'amount_due'
        'amount_paid'
        'base_rent'
        'hourly_credit'
        'max_monthly_hours'
      ]

      filteredUpdates = {}
      for key, value of updates
        if key in allowedFields
          filteredUpdates[key] = value

      unless Object.keys(filteredUpdates).length > 0
        return res.status(400).json error: 'No valid fields to update'

      period = await rentModel.updateRentPeriod year, month, filteredUpdates
      res.json period
    catch err
      res.status(500).json error: err.message

  app.delete '/rent/period/:year/:month', (req, res) ->
    year  = parseInt req.params.year
    month = parseInt req.params.month

    try
      result = await rentModel.deleteRentPeriod year, month
      res.json result
    catch err
      if err.message.includes 'not found'
        res.status(404).json error: err.message
      else
        res.status(500).json error: err.message

  app.post '/rent/payment', (req, res) ->
    { year, month, amount, payment_method, notes } = req.body

    unless year and month and amount
      return res.status(400).json error: 'Year, month, and amount required'

    try
      payment = await rentModel.recordPayment
        year:           parseInt year
        month:          parseInt month
        amount:         parseFloat amount
        payment_method: payment_method
        notes:          notes

      res.json payment
    catch err
      res.status(500).json error: err.message

  app.get '/rent/summary', (req, res) ->
    try
      summary = await rentService.getRentSummary()
      res.json summary
    catch err
      res.status(500).json error: err.message

  app.post '/rent/recalculate-all', (req, res) ->
    try
      periods = await rentService.recalculateAllRent()

      for period in periods
        await rentService.createOrUpdateRentPeriod period.year, period.month

      res.json
        message:         'Recalculation complete'
        periods_updated: periods.length
        periods:         periods
    catch err
      res.status(500).json error: err.message

  app.get '/rent/periods', (req, res) ->
    try
      periods = await rentModel.getAllRentPeriods()
      res.json periods
    catch err
      res.status(500).json error: err.message

  app.get '/rent/events', (req, res) ->
    { year, month, includeDeleted } = req.query

    try
      showDeleted = includeDeleted is 'true'

      if year and month
        events = await rentModel.getRentEventsForPeriod parseInt(year), parseInt(month), showDeleted
      else
        events = await rentModel.getAllRentEvents showDeleted

      res.json events
    catch err
      res.status(500).json error: err.message

  app.post '/rent/events', (req, res) ->
    { type, date, year, month, amount, description, notes, metadata } = req.body

    unless type and year and month and amount and description
      return res.status(400).json error: 'Type, year, month, amount, and description required'

    try
      event = await rentModel.createRentEvent
        type:        type
        date:        date
        year:        parseInt year
        month:       parseInt month
        amount:      parseFloat amount
        description: description
        notes:       notes
        metadata:    metadata or {}

      res.json event
    catch err
      res.status(500).json error: err.message

  app.get '/rent/events/:id', (req, res) ->
    try
      event = await rentModel.getRentEvent req.params.id

      unless event
        return res.status(404).json error: 'Event not found'

      res.json event
    catch err
      res.status(500).json error: err.message

  app.put '/rent/events/:id', (req, res) ->
    { type, date, year, month, amount, description, notes, metadata } = req.body

    try
      event = await rentModel.updateRentEvent req.params.id,
        type:        type
        date:        date
        year:        if year then parseInt year else undefined
        month:       if month then parseInt month else undefined
        amount:      if amount then parseFloat amount else undefined
        description: description
        notes:       notes
        metadata:    metadata

      res.json event
    catch err
      if err.message.includes 'not found'
        res.status(404).json error: err.message
      else
        res.status(500).json error: err.message

  app.delete '/rent/events/:id', (req, res) ->
    try
      deletedEvent = await rentModel.deleteRentEvent req.params.id
      res.json message: 'Event deleted', event: deletedEvent
    catch err
      if err.message.includes 'not found'
        res.status(404).json error: err.message
      else
        res.status(500).json error: err.message

  app.post '/rent/events/:id/undelete', (req, res) ->
    try
      undeletedEvent = await rentModel.undeleteRentEvent req.params.id
      res.json message: 'Event undeleted', event: undeletedEvent
    catch err
      if err.message.includes 'not found'
        res.status(404).json error: err.message
      else if err.message.includes 'not deleted'
        res.status(400).json error: err.message
      else
        res.status(500).json error: err.message

  app.get '/rent/audit-logs', (req, res) ->
    { entity_type, entity_id, action, user } = req.query

    try
      filters = {}
      if entity_type then filters.entity_type = entity_type
      if entity_id   then filters.entity_id   = entity_id
      if action      then filters.action      = action
      if user        then filters.user        = user

      logs = await rentModel.getAuditLogs filters
      res.json logs
    catch err
      res.status(500).json error: err.message

module.exports = { setup }
