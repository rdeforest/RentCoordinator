stripe             = null
elements           = null
bankAccountElement = null
paymentIntent      = null
currentYear        = null
currentMonth       = null
currentAmount      = null

getPaymentPeriod = ->
  params = new URLSearchParams window.location.search
  year   = parseInt params.get 'year'
  month  = parseInt params.get 'month'
  { year, month }


document.addEventListener 'DOMContentLoaded', ->
  await requireAuth()

  { year, month } = getPaymentPeriod()

  unless year and month
    showMessage 'Invalid payment period', 'error'
    return

  currentYear  = year
  currentMonth = month

  await loadRentPeriod year, month
  await initializeStripe()

loadRentPeriod = (year, month) ->
  try
    response = await fetch "/rent/period/#{year}/#{month}"
    data     = await response.json()

    throw new Error (data.error or 'Failed to load rent period') unless response.ok

    monthName = new Date(year, month - 1).toLocaleString 'default', month: 'long'
    document.getElementById('payment-period').textContent = "#{monthName} #{year}"

    amountDue     = data.amount_due - (data.amount_paid or 0)
    currentAmount = amountDue
    document.getElementById('payment-amount').textContent = "$#{amountDue.toFixed 2}"

    if amountDue <= 0
      showMessage 'This period is already paid in full', 'success'
      document.getElementById('pay-button').disabled = true

  catch err
    console.error 'Load rent period error:', err
    showMessage err.message, 'error'

initializeStripe = ->
  try
    console.log 'Step 1: Fetching Stripe config...'
    response = await fetch '/payment/config'
    config   = await response.json()
    console.log 'Step 2: Got config:', config

    throw new Error 'Stripe not configured' unless config.publishableKey

    console.log 'Step 3: Checking Stripe.js loaded...'
    throw new Error 'Stripe.js not loaded - check script tag' unless window.Stripe

    console.log 'Step 4: Initializing Stripe...'
    stripe = Stripe config.publishableKey

    elements = stripe.elements
      mode                 : 'payment'
      amount               : currentAmount * 100
      currency             : 'usd'
      payment_method_types : ['us_bank_account']

    console.log 'Step 5: Creating payment element...'

    bankAccountElement = elements.create 'payment',
      layout             : 'tabs'
      paymentMethodOrder : ['us_bank_account']

    console.log 'Step 6: Mounting element...'
    bankAccountElement.mount '#bank-account-element'
    console.log 'Step 7: Stripe initialized successfully'

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

document.addEventListener 'click', (e) ->
  if e.target.id is 'pay-button'
    e.preventDefault()
    await processPayment()


processPayment = ->
  payButton = document.getElementById 'pay-button'
  payButton.disabled    = true
  payButton.textContent = 'Processing...'

  try
    console.log 'Step 1: Submitting payment element...'
    submitResult = await elements.submit()

    throw new Error submitResult.error.message if submitResult.error

    console.log 'Step 2: Creating payment intent...'
    response = await fetch '/payment/create-intent',
      method  : 'POST'
      headers : 'Content-Type': 'application/json'
      body    : JSON.stringify
        year   : currentYear
        month  : currentMonth
        amount : currentAmount

    data = await response.json()

    throw new Error (data.error or 'Failed to create payment intent') unless response.ok

    clientSecret = data.clientSecret

    console.log 'Step 3: Confirming payment...'
    user = await getCurrentUser()

    result = await stripe.confirmPayment
      elements      : elements
      clientSecret  : clientSecret
      confirmParams :
        return_url : "#{window.location.origin}/payment/confirm?year=#{currentYear}&month=#{currentMonth}"
        payment_method_data:
          billing_details:
            name  : user.email
            email : user.email
      redirect : 'if_required'

    throw new Error result.error.message if result.error

    console.log 'Step 4: Payment result:', result.paymentIntent?.status

    if result.paymentIntent?.status is 'succeeded'
      await confirmPayment result.paymentIntent.id
    else
      showMessage 'Payment initiated! You may need to verify with your bank.', 'success'
      await checkPaymentStatus result.paymentIntent.id

  catch err
    console.error 'Process payment error:', err
    showMessage err.message, 'error'
    payButton.disabled    = false
    payButton.textContent = 'Process Payment'

checkPaymentStatus = (paymentIntentId) ->
  try
    maxAttempts = 30
    attempt     = 0

    checkStatus = ->
      attempt++

      response = await fetch "/payment/status/#{paymentIntentId}"
      status   = await response.json()

      if status.status is 'succeeded'
        await confirmPayment paymentIntentId
        return true
      else if status.status is 'requires_action' or status.status is 'processing'
        if attempt < maxAttempts
          setTimeout checkStatus, 2000
        else
          showMessage 'Payment is processing. Check back later.', 'success'
          setTimeout (-> window.location.href = '/rent'), 3000
      else if status.status is 'requires_payment_method'
        throw new Error 'Payment method verification required'
      else
        throw new Error "Payment failed: #{status.status}"

    await checkStatus()

  catch err
    console.error 'Check payment status error:', err
    showMessage err.message, 'error'


confirmPayment = (paymentIntentId) ->
  try
    response = await fetch '/payment/confirm',
      method  : 'POST'
      headers : 'Content-Type': 'application/json'
      body    : JSON.stringify
        paymentIntentId : paymentIntentId
        year            : currentYear
        month           : currentMonth

    data = await response.json()

    throw new Error (data.error or 'Failed to confirm payment') unless response.ok

    showMessage 'Payment successful! Redirecting...', 'success'
    setTimeout (-> window.location.href = '/rent'), 2000

  catch err
    console.error 'Confirm payment error:', err
    showMessage err.message, 'error'


showMessage = (text, type) ->
  container = document.getElementById 'message-container'
  container.innerHTML = """
    <div class="message #{type}">#{text}</div>
  """

clearMessage = ->
  container = document.getElementById 'message-container'
  container.innerHTML = ''
