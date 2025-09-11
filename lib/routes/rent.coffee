# lib/routes/rent.coffee

rentService = await import('../services/rent.coffee')
rentModel   = await import('../models/rent.coffee')


export setup = (app) ->

  # Calculate rent for current month
  app.get '/rent/calculate', (req, res) ->
    { year, month } = req.query

    # Default to current month
    now = new Date()
    year = parseInt(year) or now.getFullYear()
    month = parseInt(month) or (now.getMonth() + 1)

    try
      calculation = await rentService.calculateRent(year, month)
      res.json calculation
    catch err
      res.status(500).json error: err.message


  # Get or create rent period
  app.get '/rent/period/:year/:month', (req, res) ->
    year = parseInt(req.params.year)
    month = parseInt(req.params.month)

    try
      period = await rentModel.getRentPeriod(year, month)

      if not period
        # Calculate and create if doesn't exist
        period = await rentService.createOrUpdateRentPeriod(year, month)

      res.json period
    catch err
      res.status(500).json error: err.message


  # Update rent period (usually after recalculation)
  app.post '/rent/period/:year/:month', (req, res) ->
    year = parseInt(req.params.year)
    month = parseInt(req.params.month)

    try
      period = await rentService.createOrUpdateRentPeriod(year, month)
      res.json period
    catch err
      res.status(500).json error: err.message


  # Record payment
  app.post '/rent/payment', (req, res) ->
    { year, month, amount, payment_method, notes } = req.body

    if not year or not month or not amount
      return res.status(400).json error: 'Year, month, and amount required'

    try
      payment = await rentModel.recordPayment
        year: parseInt(year)
        month: parseInt(month)
        amount: parseFloat(amount)
        payment_method: payment_method
        notes: notes

      res.json payment
    catch err
      res.status(500).json error: err.message


  # Get rent summary
  app.get '/rent/summary', (req, res) ->
    try
      summary = await rentService.getRentSummary()
      res.json summary
    catch err
      res.status(500).json error: err.message


  # Recalculate all periods with retroactive adjustments
  app.post '/rent/recalculate-all', (req, res) ->
    try
      periods = await rentService.recalculateAllRent()

      # Save all recalculated periods
      for period in periods
        await rentService.createOrUpdateRentPeriod(period.year, period.month)

      res.json
        message: 'Recalculation complete'
        periods_updated: periods.length
        periods: periods
    catch err
      res.status(500).json error: err.message


  # Get all rent periods
  app.get '/rent/periods', (req, res) ->
    try
      periods = await rentModel.getAllRentPeriods()
      res.json periods
    catch err
      res.status(500).json error: err.message


  # Rent Events CRUD
  app.get '/rent/events', (req, res) ->
    { year, month } = req.query

    try
      if year and month
        events = await rentModel.getRentEventsForPeriod(parseInt(year), parseInt(month))
      else
        events = await rentModel.getAllRentEvents()
      
      res.json events
    catch err
      res.status(500).json error: err.message


  app.post '/rent/events', (req, res) ->
    { type, date, year, month, amount, description, notes, metadata } = req.body

    if not type or not year or not month or not amount or not description
      return res.status(400).json error: 'Type, year, month, amount, and description required'

    try
      event = await rentModel.createRentEvent
        type: type
        date: date
        year: parseInt(year)
        month: parseInt(month)
        amount: parseFloat(amount)
        description: description
        notes: notes
        metadata: metadata or {}

      res.json event
    catch err
      res.status(500).json error: err.message


  app.get '/rent/events/:id', (req, res) ->
    try
      event = await rentModel.getRentEvent(req.params.id)
      
      if not event
        return res.status(404).json error: 'Event not found'
      
      res.json event
    catch err
      res.status(500).json error: err.message


  app.put '/rent/events/:id', (req, res) ->
    { type, date, year, month, amount, description, notes, metadata } = req.body

    try
      event = await rentModel.updateRentEvent req.params.id,
        type: type
        date: date
        year: if year then parseInt(year) else undefined
        month: if month then parseInt(month) else undefined
        amount: if amount then parseFloat(amount) else undefined
        description: description
        notes: notes
        metadata: metadata

      res.json event
    catch err
      if err.message.includes 'not found'
        res.status(404).json error: err.message
      else
        res.status(500).json error: err.message


  app.delete '/rent/events/:id', (req, res) ->
    try
      deletedEvent = await rentModel.deleteRentEvent(req.params.id)
      res.json message: 'Event deleted', event: deletedEvent
    catch err
      if err.message.includes 'not found'
        res.status(404).json error: err.message
      else
        res.status(500).json error: err.message