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
        allocation  = [ { year: parseInt(year), month: parseInt(month), amount } ]
        meta        = { year, month, tenant: req.session.email, allocation: JSON.stringify allocation }
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
        # Freeze the oldest-first split now so confirm and the webhook credit
        # the same months later, whatever "outstanding" looks like by then.
        allocation  = ({ year: m.year, month: m.month, amount: m.outstanding } for m in outstanding.months)
        meta        = { covers: ymList, tenant: req.session.email, allocation: JSON.stringify allocation }

      result = await paymentService.createPaymentIntent amount, description, meta
      res.json result

    catch err
      logger.error 'payment.createIntent', err,
        { year, month, amount, tenant: req.session.email },
        req.id
      res.status(500).json error: err.message

  # Client confirm. Only fires when the intent already settled; recording
  # replays the allocation frozen into the intent's metadata at create time,
  # so year/month in the body are no longer needed. Idempotent on the intent
  # id, so it's safe alongside the webhook.
  app.post '/payment/confirm', (req, res) ->
    { paymentIntentId } = req.body

    unless paymentIntentId
      return res.status(400).json error: 'Payment intent ID required'

    try
      result = await paymentService.confirmPayment paymentIntentId
      res.json result

    catch err
      logger.error 'payment.confirmPayment', err,
        { paymentIntentId },
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

# The Stripe webhook is the authoritative record of ACH settlement (the
# client poll gives up long before an ACH clears). It must be registered
# BEFORE requireAuth — Stripe sends no session cookie — so it lives in its
# own setup that routing.coffee calls ahead of the auth gate. Authenticity
# comes from the signature check, verified against the raw request body.
setupWebhook = (app) ->
  app.post '/payment/webhook', (req, res) ->
    signature = req.headers['stripe-signature']

    try
      event = paymentService.constructWebhookEvent req.rawBody, signature
    catch err
      logger.error 'payment.webhook.signature', err, {}, req.id
      return res.status(400).json error: 'Webhook signature verification failed'

    try
      if event.type is 'payment_intent.succeeded'
        paymentService.recordPaymentFromIntent event.data.object
      res.json received: true
    catch err
      logger.error 'payment.webhook.handle', err, { type: event.type }, req.id
      res.status(500).json error: err.message

module.exports = { setup, setupWebhook }
