# lib/services/payment.coffee

import Stripe    from 'stripe'
import * as config from '../config.coffee'
import * as rentModel from '../models/rent.coffee'

# Initialize Stripe
stripe = new Stripe(config.STRIPE_SECRET_KEY, {
  apiVersion: '2024-12-18.acacia'
})


# Create a Payment Intent for ACH payment
# Returns the client secret for frontend confirmation
export createPaymentIntent = (amount, description, metadata = {}) ->
  unless config.STRIPE_SECRET_KEY
    throw new Error 'Stripe not configured'

  # Amount must be in cents
  amountCents = Math.round(amount * 100)

  paymentIntent = await stripe.paymentIntents.create
    amount:               amountCents
    currency:             'usd'
    description:          description
    metadata:             metadata
    payment_method_types: ['us_bank_account']

  return {
    clientSecret: paymentIntent.client_secret
    id:           paymentIntent.id
    amount:       amount
  }


# Get payment status
export getPaymentStatus = (paymentIntentId) ->
  paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId)

  return {
    id:     paymentIntent.id
    status: paymentIntent.status
    amount: paymentIntent.amount / 100
  }


# Confirm successful payment and update rent record
export confirmPayment = (paymentIntentId, year, month) ->
  # Get payment details
  paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId)

  unless paymentIntent.status is 'succeeded'
    throw new Error "Payment not successful: #{paymentIntent.status}"

  # Record payment in rent system
  amount = paymentIntent.amount / 100

  await rentModel.recordPayment {
    year:           year
    month:          month
    amount:         amount
    payment_method: 'stripe_ach'
    notes:          "Stripe payment #{paymentIntentId}"
  }

  return {
    success:  true
    amount:   amount
    paidAt:   new Date()
  }


# Create a SetupIntent for saving bank account for future use
export createSetupIntent = (customerId = null) ->
  options = {
    payment_method_types: ['us_bank_account']
  }

  if customerId
    options.customer = customerId

  setupIntent = await stripe.setupIntents.create(options)

  return {
    clientSecret: setupIntent.client_secret
    id:           setupIntent.id
  }


# Get or create Stripe customer for a user
export getOrCreateCustomer = (email, name) ->
  # Search for existing customer
  customers = await stripe.customers.list {
    email: email
    limit: 1
  }

  if customers.data.length > 0
    return customers.data[0]

  # Create new customer
  customer = await stripe.customers.create {
    email:       email
    name:        name
    description: "RentCoordinator tenant"
  }

  return customer
