Stripe        = require 'stripe'
config        = require '../config.coffee'
eventsModel   = require '../models/events.coffee'
{ transaction } = require '../db/utils.coffee'

stripe = null

getStripe = ->
  unless config.STRIPE_SECRET_KEY
    throw new Error 'Stripe not configured'

  unless stripe
    stripe = new Stripe config.STRIPE_SECRET_KEY,
      apiVersion: '2024-12-18.acacia'

  return stripe


createPaymentIntent = (amount, description, metadata = {}) ->
  stripeClient = getStripe()

  amountCents = Math.round amount * 100

  paymentIntent = await stripeClient.paymentIntents.create
    amount:               amountCents
    currency:             'usd'
    description:          description
    metadata:             metadata
    payment_method_types: ['us_bank_account']

  return
    clientSecret: paymentIntent.client_secret
    id:           paymentIntent.id
    amount:       amount


getPaymentStatus = (paymentIntentId) ->
  stripeClient  = getStripe()
  paymentIntent = await stripeClient.paymentIntents.retrieve paymentIntentId

  return
    id:     paymentIntent.id
    status: paymentIntent.status
    amount: paymentIntent.amount / 100


# The allocation plan the intent was created with, stored in metadata at
# checkout. Replaying it means confirm and the webhook record the exact same
# split — possibly days apart — without recomputing "outstanding", which may
# have moved on. Falls back to a single month for intents created before the
# plan was stored (or elsewhere).
parseAllocation = (paymentIntent) ->
  meta = paymentIntent.metadata or {}
  if meta.allocation
    return JSON.parse meta.allocation

  amount = paymentIntent.amount / 100
  if meta.year and meta.month
    [ { year: parseInt(meta.year), month: parseInt(meta.month), amount } ]
  else
    now = new Date()
    [ { year: now.getFullYear(), month: now.getMonth() + 1, amount } ]


# Record the payment-made event(s) for a settled PaymentIntent, exactly once.
# Called from both the client confirm and the Stripe webhook, and safe to
# retry: if any event already carries this intent id we no-op (bug 10). The
# check and the inserts run with no await between them, so the single-threaded
# event loop can't interleave a concurrent caller between them — a client
# retry racing the webhook still credits once.
recordPaymentFromIntent = (paymentIntent) ->
  existing = eventsModel.paymentEventsForIntent paymentIntent.id
  if existing.length > 0
    return
      success:         true
      alreadyRecorded: true
      amount:          existing.reduce ((s, e) -> s + e.payload.amount), 0

  allocation = parseAllocation paymentIntent
  occurredAt = new Date().toISOString()

  transaction ->
    for a in allocation
      monthKey = "#{a.year}-#{String(a.month).padStart 2, '0'}"
      eventsModel.recordEvent
        occurred_at:   occurredAt
        effective_for: monthKey
        actor:         'tenant'
        actor_user:    'lynz57@hotmail.com'
        action:        'payment-made'
        payload:
          amount:                   a.amount
          method:                   'stripe_ach'
          stripe_payment_intent_id: paymentIntent.id
          note:                     "Stripe payment #{paymentIntent.id}"

  return
    success:         true
    alreadyRecorded: false
    amount:          allocation.reduce ((s, a) -> s + a.amount), 0
    allocated:       allocation
    paidAt:          new Date()


# Client-side confirm path: only fires when the intent already settled
# (instant methods, or an ACH that happened to settle inside the poll
# window). ACH normally settles later and is recorded by the webhook.
confirmPayment = (paymentIntentId) ->
  stripeClient  = getStripe()
  paymentIntent = await stripeClient.paymentIntents.retrieve paymentIntentId

  unless paymentIntent.status is 'succeeded'
    throw new Error "Payment not successful: #{paymentIntent.status}"

  recordPaymentFromIntent paymentIntent


# Verify a Stripe webhook's signature against the raw request body and return
# the parsed event. Throws if the signature or secret is invalid — the route
# turns that into a 400 so an unsigned caller can't write payment events.
constructWebhookEvent = (rawBody, signature) ->
  unless config.STRIPE_WEBHOOK_SECRET
    throw new Error 'Stripe webhook secret not configured'
  getStripe().webhooks.constructEvent rawBody, signature, config.STRIPE_WEBHOOK_SECRET


createSetupIntent = (customerId = null) ->
  stripeClient = getStripe()
  options      =
    payment_method_types: ['us_bank_account']

  if customerId
    options.customer = customerId

  setupIntent = await stripeClient.setupIntents.create options

  return
    clientSecret: setupIntent.client_secret
    id:           setupIntent.id


getOrCreateCustomer = (email, name) ->
  stripeClient = getStripe()
  customers    = await stripeClient.customers.list
    email: email
    limit: 1

  if customers.data.length > 0
    return customers.data[0]

  customer = await stripeClient.customers.create
    email:       email
    name:        name
    description: "RentCoordinator tenant"

  return customer

module.exports = {
  createPaymentIntent
  getPaymentStatus
  confirmPayment
  recordPaymentFromIntent
  constructWebhookEvent
  createSetupIntent
  getOrCreateCustomer
}
