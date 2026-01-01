paymentService = require '../services/payment.coffee'
rentModel      = require '../models/rent.coffee'
config         = require '../config.coffee'
logger         = require '../logger.coffee'


setup = (app) ->
  app.post '/payment/create-intent', (req, res) ->
    { year, month, amount } = req.body

    unless year and month and amount
      return res.status(400).json error: 'Year, month, and amount required'

    try
      period = await rentModel.getRentPeriod year, month

      unless period
        return res.status(404).json error: 'Rent period not found'

      amountDue = period.amount_due - (period.amount_paid or 0)

      if Math.abs(amount - amountDue) > 0.01
        return res.status(400).json
          error:     'Amount mismatch'
          expected:  amountDue
          requested: amount

      result = await paymentService.createPaymentIntent(
        amount,
        "Rent payment for #{year}-#{String(month).padStart 2, '0'}",
        { year, month, tenant: req.session.email }
      )

      res.json result

    catch err
      logger.error 'payment.createIntent', err,
        { year, month, amount, tenant: req.session.email },
        req.id
      res.status(500).json error: err.message

  app.post '/payment/confirm', (req, res) ->
    { paymentIntentId, year, month } = req.body

    unless paymentIntentId and year and month
      return res.status(400).json error: 'Payment intent ID, year, and month required'

    try
      result = await paymentService.confirmPayment paymentIntentId, year, month

      res.json result

    catch err
      logger.error 'payment.confirmPayment', err,
        { paymentIntentId, year, month },
        req.id
      res.status(400).json error: err.message

  app.get '/payment/status/:paymentIntentId', (req, res) ->
    { paymentIntentId } = req.params

    try
      status = await paymentService.getPaymentStatus paymentIntentId
      res.json status

    catch err
      logger.error 'payment.getStatus', err,
        { paymentIntentId },
        req.id
      res.status(500).json error: err.message

  app.post '/payment/setup-intent', (req, res) ->
    try
      customer = await paymentService.getOrCreateCustomer(
        req.session.email,
        req.session.email.split('@')[0]
      )

      result = await paymentService.createSetupIntent customer.id

      res.json Object.assign {}, result, { customerId: customer.id }

    catch err
      logger.error 'payment.createSetupIntent', err,
        { email: req.session.email },
        req.id
      res.status(500).json error: err.message

module.exports = { setup }
