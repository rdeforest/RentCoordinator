paymentService = require '../services/payment.coffee'
periodViewer   = require '../services/period_viewer.coffee'
config         = require '../config.coffee'
logger         = require '../logger.coffee'


computeOutstanding = ->
  periods = periodViewer.getAllPeriods()
  rows    = Object.values(periods)
    .filter (p) -> p.payment_status isnt 'NOT DUE'
    .map (p) ->
      owed = p.display_amount_due
      paid = p.amount_paid or 0
      outstanding = Math.max 0, owed - paid
      { year: p.year, month: p.month, owed, paid, outstanding }
    .filter (r) -> r.outstanding > 0
    .sort   (a, b) -> (a.year - b.year) or (a.month - b.month)
  total: rows.reduce ((s, r) -> s + r.outstanding), 0
  months: rows


setup = (app) ->
  # If year/month are supplied, the tenant is paying a specific month
  # (legacy flow + the Stripe checkout link in the rent UI). If they're
  # absent, the tenant is paying everything outstanding in one shot —
  # confirmPayment will split the result across months oldest-first.
  app.post '/payment/create-intent', (req, res) ->
    { year, month, amount } = req.body

    unless amount
      return res.status(400).json error: 'Amount required'

    try
      if year and month
        period = periodViewer.getPeriod parseInt(year), parseInt(month)
        return res.status(404).json error: 'Rent period not found' unless period

        expected = period.display_amount_due - (period.amount_paid or 0)
        # Before the 15th, display is 0 — but tenant may still want to pay
        # the agreed amount early.
        if expected <= 0 and period.amount_paid < period.effective_agreed_payment
          expected = period.effective_agreed_payment - period.amount_paid

        if Math.abs(amount - expected) > 0.01
          return res.status(400).json
            error:     'Amount mismatch'
            expected:  expected
            requested: amount

        description = "Rent payment for #{year}-#{String(month).padStart 2, '0'}"
        meta        = { year, month, tenant: req.session.email }
      else
        # "Pay everything outstanding" flow.
        outstanding = computeOutstanding()
        expected    = outstanding.total

        if expected <= 0
          return res.status(400).json error: 'Nothing outstanding to pay'

        if Math.abs(amount - expected) > 0.01
          return res.status(400).json
            error:     'Amount mismatch'
            expected:  expected
            requested: amount

        ymList      = (m.year + '-' + String(m.month).padStart(2,'0') for m in outstanding.months).join ','
        description = "Rent payment covering #{ymList}"
        meta        = { covers: ymList, tenant: req.session.email }

      result = await paymentService.createPaymentIntent amount, description, meta
      res.json result

    catch err
      logger.error 'payment.createIntent', err,
        { year, month, amount, tenant: req.session.email },
        req.id
      res.status(500).json error: err.message

  # confirm accepts the same shape with year/month optional. When absent,
  # the Stripe intent's amount is allocated across outstanding months
  # oldest-first, emitting one payment-made event per covered month.
  app.post '/payment/confirm', (req, res) ->
    { paymentIntentId, year, month } = req.body

    unless paymentIntentId
      return res.status(400).json error: 'Payment intent ID required'

    try
      if year and month
        result = await paymentService.confirmPayment paymentIntentId, parseInt(year), parseInt(month)
      else
        result = await paymentService.confirmPaymentAllocated paymentIntentId, computeOutstanding()

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
