Stripe    = require 'stripe'
config    = require '../config.coffee'
eventsModel = require '../models/events.coffee'

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


confirmPayment = (paymentIntentId, year, month) ->
  stripeClient  = getStripe()
  paymentIntent = await stripeClient.paymentIntents.retrieve paymentIntentId

  unless paymentIntent.status is 'succeeded'
    throw new Error "Payment not successful: #{paymentIntent.status}"

  amount = paymentIntent.amount / 100

  monthKey = "#{year}-#{String(month).padStart 2, '0'}"

  eventsModel.recordEvent
    occurred_at:   new Date().toISOString()
    effective_for: monthKey
    actor:         'tenant'
    actor_user:    'lynz57@hotmail.com'
    action:        'payment-made'
    payload:
      amount:                   amount
      method:                   'stripe_ach'
      stripe_payment_intent_id: paymentIntentId
      note:                     "Stripe payment #{paymentIntentId}"

  return
    success: true
    amount:  amount
    paidAt:  new Date()


# Allocate one Stripe payment across multiple outstanding months,
# oldest-first. Emits one payment-made event per covered month. All
# events share the same stripe_payment_intent_id so the chain is
# traceable back to a single Stripe transaction.
confirmPaymentAllocated = (paymentIntentId, outstanding) ->
  stripeClient  = getStripe()
  paymentIntent = await stripeClient.paymentIntents.retrieve paymentIntentId

  unless paymentIntent.status is 'succeeded'
    throw new Error "Payment not successful: #{paymentIntent.status}"

  total      = paymentIntent.amount / 100
  remaining  = total
  allocated  = []
  occurredAt = new Date().toISOString()

  for m in outstanding.months
    break if remaining <= 0
    chunk = Math.min remaining, m.outstanding

    monthKey = "#{m.year}-#{String(m.month).padStart 2, '0'}"
    eventsModel.recordEvent
      occurred_at:   occurredAt
      effective_for: monthKey
      actor:         'tenant'
      actor_user:    'lynz57@hotmail.com'
      action:        'payment-made'
      payload:
        amount:                   chunk
        method:                   'stripe_ach'
        stripe_payment_intent_id: paymentIntentId
        note:                     "Stripe payment #{paymentIntentId} (allocation across #{outstanding.months.length} months)"

    allocated.push { year: m.year, month: m.month, amount: chunk }
    remaining -= chunk

  # Any leftover (tenant paid more than outstanding) goes to the most
  # recent unpaid month as an advance, or — if there's nothing
  # outstanding at all — gets recorded against the current month.
  if remaining > 0
    target = outstanding.months[outstanding.months.length - 1]
    unless target
      now = new Date()
      target = { year: now.getFullYear(), month: now.getMonth() + 1 }

    monthKey = "#{target.year}-#{String(target.month).padStart 2, '0'}"
    eventsModel.recordEvent
      occurred_at:   occurredAt
      effective_for: monthKey
      actor:         'tenant'
      actor_user:    'lynz57@hotmail.com'
      action:        'payment-made'
      payload:
        amount:                   remaining
        method:                   'stripe_ach'
        stripe_payment_intent_id: paymentIntentId
        note:                     "Stripe payment #{paymentIntentId} (overage)"

    allocated.push { year: target.year, month: target.month, amount: remaining }

  return
    success:   true
    amount:    total
    allocated: allocated
    paidAt:    new Date()


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
  confirmPaymentAllocated
  createSetupIntent
  getOrCreateCustomer
}
