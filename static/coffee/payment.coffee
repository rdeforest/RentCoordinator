# static/coffee/payment.coffee

# Global variables
stripe           = null
elements         = null
bankAccountElement = null
paymentIntent    = null
currentYear      = null
currentMonth     = null
currentAmount    = null

# Get payment period from URL query string
getPaymentPeriod = ->
  params = new URLSearchParams(window.location.search)
  year = parseInt(params.get('year'))
  month = parseInt(params.get('month'))
  { year, month }

# Initialize on page load
document.addEventListener 'DOMContentLoaded', ->
  # Require authentication
  await requireAuth()

  # Get payment period
  { year, month } = getPaymentPeriod()

  unless year and month
    showMessage 'Invalid payment period', 'error'
    return

  currentYear = year
  currentMonth = month

  # Load rent period info
  await loadRentPeriod(year, month)

  # Initialize Stripe
  await initializeStripe()

# Load rent period details
loadRentPeriod = (year, month) ->
  try
    response = await fetch("/rent/period/#{year}/#{month}")
    data = await response.json()

    unless response.ok
      throw new Error(data.error or 'Failed to load rent period')

    # Display payment info
    monthName = new Date(year, month - 1).toLocaleString('default', { month: 'long' })
    document.getElementById('payment-period').textContent = "#{monthName} #{year}"

    amountDue = data.amount_due - (data.amount_paid or 0)
    currentAmount = amountDue
    document.getElementById('payment-amount').textContent = "$#{amountDue.toFixed(2)}"

    if amountDue <= 0
      showMessage 'This period is already paid in full', 'success'
      document.getElementById('pay-button').disabled = true

  catch err
    console.error 'Load rent period error:', err
    showMessage err.message, 'error'

# Initialize Stripe
initializeStripe = ->
  try
    console.log 'Step 1: Fetching Stripe config...'
    # Get publishable key from backend
    response = await fetch('/payment/config')
    config = await response.json()
    console.log 'Step 2: Got config:', config

    unless config.publishableKey
      throw new Error('Stripe not configured')

    console.log 'Step 3: Checking Stripe.js loaded...'
    unless window.Stripe
      throw new Error('Stripe.js not loaded - check script tag')

    console.log 'Step 4: Initializing Stripe...'
    # Initialize Stripe
    stripe = Stripe(config.publishableKey)

    # Create elements with payment intent client secret options
    # For now, create without client secret - will be created on submit
    elements = stripe.elements
      mode: 'payment'
      amount: currentAmount * 100  # Stripe uses cents
      currency: 'usd'
      payment_method_types: ['us_bank_account']

    console.log 'Step 5: Creating payment element...'

    # Create unified payment element (supports multiple payment methods)
    bankAccountElement = elements.create 'payment',
      layout: 'tabs'
      paymentMethodOrder: ['us_bank_account']

    console.log 'Step 6: Mounting element...'
    bankAccountElement.mount('#bank-account-element')
    console.log 'Step 7: Stripe initialized successfully'

    # Enable pay button when element is ready
    bankAccountElement.on 'ready', ->
      console.log 'Stripe element ready'
      document.getElementById('pay-button').disabled = false

    bankAccountElement.on 'change', (event) ->
      if event.error
        showMessage event.error.message, 'error'
      else
        clearMessage()

  catch err
    console.error 'Initialize Stripe error:', err
    console.error 'Error stack:', err.stack
    showMessage "Failed to initialize payment system: #{err.message}", 'error'

# Handle payment submission
document.addEventListener 'click', (e) ->
  if e.target.id is 'pay-button'
    e.preventDefault()
    await processPayment()

processPayment = ->
  payButton = document.getElementById('pay-button')
  payButton.disabled = true
  payButton.textContent = 'Processing...'

  try
    # Step 1: Submit the payment element to validate and collect data
    console.log 'Step 1: Submitting payment element...'
    submitResult = await elements.submit()

    if submitResult.error
      throw new Error(submitResult.error.message)

    console.log 'Step 2: Creating payment intent...'
    # Step 2: Create payment intent on server
    response = await fetch '/payment/create-intent',
      method: 'POST'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify
        year: currentYear
        month: currentMonth
        amount: currentAmount

    data = await response.json()

    unless response.ok
      throw new Error(data.error or 'Failed to create payment intent')

    clientSecret = data.clientSecret

    console.log 'Step 3: Confirming payment...'
    # Step 3: Confirm payment using the unified Payment Element
    user = await getCurrentUser()

    result = await stripe.confirmPayment
      elements: elements
      clientSecret: clientSecret
      confirmParams:
        return_url: "#{window.location.origin}/payment/confirm?year=#{currentYear}&month=#{currentMonth}"
        payment_method_data:
          billing_details:
            name: user.email
            email: user.email
      redirect: 'if_required'

    if result.error
      throw new Error(result.error.message)

    console.log 'Step 4: Payment result:', result.paymentIntent?.status
    # Payment initiated successfully
    if result.paymentIntent?.status is 'succeeded'
      # Payment completed immediately
      await confirmPayment(result.paymentIntent.id)
    else
      # Payment requires additional action
      showMessage 'Payment initiated! You may need to verify with your bank.', 'success'
      await checkPaymentStatus(result.paymentIntent.id)

  catch err
    console.error 'Process payment error:', err
    showMessage err.message, 'error'
    payButton.disabled = false
    payButton.textContent = 'Process Payment'

# Check payment status and confirm
checkPaymentStatus = (paymentIntentId) ->
  try
    # Poll for payment status
    maxAttempts = 30
    attempt = 0

    checkStatus = ->
      attempt++

      response = await fetch("/payment/status/#{paymentIntentId}")
      status = await response.json()

      if status.status is 'succeeded'
        # Confirm payment in backend
        await confirmPayment(paymentIntentId)
        return true
      else if status.status is 'requires_action' or status.status is 'processing'
        if attempt < maxAttempts
          setTimeout checkStatus, 2000  # Check again in 2 seconds
        else
          showMessage 'Payment is processing. Check back later.', 'success'
          setTimeout (-> window.location.href = '/rent'), 3000
      else if status.status is 'requires_payment_method'
        throw new Error('Payment method verification required')
      else
        throw new Error("Payment failed: #{status.status}")

    await checkStatus()

  catch err
    console.error 'Check payment status error:', err
    showMessage err.message, 'error'

# Confirm payment in backend
confirmPayment = (paymentIntentId) ->
  try
    response = await fetch '/payment/confirm',
      method: 'POST'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify
        paymentIntentId: paymentIntentId
        year: currentYear
        month: currentMonth

    data = await response.json()

    unless response.ok
      throw new Error(data.error or 'Failed to confirm payment')

    showMessage 'Payment successful! Redirecting...', 'success'
    setTimeout (-> window.location.href = '/rent'), 2000

  catch err
    console.error 'Confirm payment error:', err
    showMessage err.message, 'error'

# Show message to user
showMessage = (text, type) ->
  container = document.getElementById('message-container')
  container.innerHTML = """
    <div class="message #{type}">#{text}</div>
  """

clearMessage = ->
  container = document.getElementById('message-container')
  container.innerHTML = ''
