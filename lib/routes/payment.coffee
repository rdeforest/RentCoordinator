# lib/routes/payment.coffee

paymentService = await import('../services/payment.coffee')
rentModel      = await import('../models/rent.coffee')
config         = await import('../config.coffee')


export setup = (app) ->
  # Note: /payment/config is set up as a public route in routing.coffee
  # since the publishable key is safe to expose publicly

  # Create payment intent for rent payment
  app.post '/payment/create-intent', (req, res) ->
    { year, month, amount } = req.body

    unless year and month and amount
      return res.status(400).json error: 'Year, month, and amount required'

    try
      # Get rent period to verify amount
      period = await rentModel.getRentPeriod(year, month)

      unless period
        return res.status(404).json error: 'Rent period not found'

      # Calculate amount due
      amountDue = period.amount_due - (period.amount_paid or 0)

      # Verify requested amount matches (allow small rounding differences)
      if Math.abs(amount - amountDue) > 0.01
        return res.status(400).json
          error: 'Amount mismatch'
          expected: amountDue
          requested: amount

      # Create payment intent
      result = await paymentService.createPaymentIntent(
        amount,
        "Rent payment for #{year}-#{String(month).padStart(2, '0')}",
        { year, month, tenant: req.session.email }
      )

      res.json result

    catch err
      console.error 'Create payment intent error:', err
      res.status(500).json error: err.message


  # Confirm payment and record in database
  app.post '/payment/confirm', (req, res) ->
    { paymentIntentId, year, month } = req.body

    unless paymentIntentId and year and month
      return res.status(400).json error: 'Payment intent ID, year, and month required'

    try
      result = await paymentService.confirmPayment(paymentIntentId, year, month)
      res.json result

    catch err
      console.error 'Confirm payment error:', err
      res.status(400).json error: err.message


  # Get payment status
  app.get '/payment/status/:paymentIntentId', (req, res) ->
    { paymentIntentId } = req.params

    try
      status = await paymentService.getPaymentStatus(paymentIntentId)
      res.json status

    catch err
      console.error 'Get payment status error:', err
      res.status(500).json error: err.message


  # Create setup intent for saving bank account
  app.post '/payment/setup-intent', (req, res) ->
    try
      # Get or create customer
      customer = await paymentService.getOrCreateCustomer(
        req.session.email,
        req.session.email.split('@')[0]
      )

      # Create setup intent
      result = await paymentService.createSetupIntent(customer.id)

      res.json Object.assign({}, result, { customerId: customer.id })

    catch err
      console.error 'Create setup intent error:', err
      res.status(500).json error: err.message
