Stripe    = require 'stripe'
config    = require '../config.coffee'
rentModel = require '../models/rent.coffee'

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

  await rentModel.recordPayment
    year:           year
    month:          month
    amount:         amount
    payment_method: 'stripe_ach'
    notes:          "Stripe payment #{paymentIntentId}"

  return
    success: true
    amount:  amount
    paidAt:  new Date()


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
  createSetupIntent
  getOrCreateCustomer
}
