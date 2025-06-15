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