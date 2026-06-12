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

  success = if year and month
    currentYear  = year
    currentMonth = month
    await loadRentPeriod year, month
  else
    await loadOutstanding()

  return unless success
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
      return false

    return true

  catch err
    console.error 'Load rent period error:', err
    showMessage err.message, 'error'
    return false


# "Pay everything outstanding" — used when the payment page is opened
# without year/month query params. Renders the total + per-month
# breakdown so Lyndzie can see what she's covering.
loadOutstanding = ->
  try
    response = await fetch '/rent/outstanding'
    data     = await response.json()
    throw new Error (data.error or 'Failed to load outstanding total') unless response.ok

    if data.total_outstanding <= 0
      showMessage 'No outstanding rent — you are paid up.', 'success'
      document.getElementById('pay-button').disabled = true
      return false

    months = data.months
    label  = if months.length is 1
      m = months[0]
      "#{new Date(m.year, m.month - 1).toLocaleString 'default', month: 'long'} #{m.year}"
    else
      first = months[0]
      last  = months[months.length - 1]
      "#{first.year}-#{String(first.month).padStart 2, '0'} through #{last.year}-#{String(last.month).padStart 2, '0'}"

    document.getElementById('payment-period').textContent = label

    currentAmount = data.total_outstanding
    document.getElementById('payment-amount').textContent = "$#{currentAmount.toFixed 2}"

    return true

  catch err
    console.error 'Load outstanding error:', err
    showMessage err.message, 'error'
    return false

initializeStripe = ->
  try
    unless currentAmount? and currentAmount > 0
      throw new Error "Invalid payment amount: #{currentAmount}"

    console.log 'Step 1: Fetching Stripe config...'
    response = await fetch '/payment/config'
    config   = await response.json()
    console.log 'Step 2: Got config:', config

    throw new Error 'Stripe not configured' unless config.publishableKey

    console.log 'Step 3: Checking Stripe.js loaded...'
    throw new Error 'Stripe.js not loaded - check script tag' unless window.Stripe

    console.log "Step 4: Initializing Stripe with amount: $#{currentAmount} (#{currentAmount * 100} cents)..."
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
    intentBody = { amount: currentAmount }
    if currentYear and currentMonth
      intentBody.year  = currentYear
      intentBody.month = currentMonth
    response = await fetch '/payment/create-intent',
      method  : 'POST'
      headers : 'Content-Type': 'application/json'
      body    : JSON.stringify intentBody

    data = await response.json()

    throw new Error (data.error or 'Failed to create payment intent') unless response.ok

    clientSecret = data.clientSecret

    console.log 'Step 3: Confirming payment...'
    user = await getCurrentUser()

    returnUrl = if currentYear and currentMonth
      "#{window.location.origin}/payment/confirm?year=#{currentYear}&month=#{currentMonth}"
    else
      "#{window.location.origin}/payment/confirm"

    result = await stripe.confirmPayment
      elements      : elements
      clientSecret  : clientSecret
      confirmParams :
        return_url : returnUrl
        payment_method_data:
          billing_details:
            name  : user.email
            email : user.email
      redirect : 'if_required'

    if result.error
      console.error 'Stripe error:', result.error
      throw new Error result.error.message

    console.log 'Step 4: Payment result:', result.paymentIntent?.status

    if result.paymentIntent?.status is 'succeeded'
      await confirmPayment result.paymentIntent.id
    else if result.paymentIntent?.status is 'requires_payment_method'
      throw new Error 'Unable to verify payment method. Please check your bank account details.'
    else if result.paymentIntent?.status in ['processing', 'requires_action']
      showMessage 'Payment initiated! ACH payments take 4-5 business days to process.', 'success'
      await checkPaymentStatus result.paymentIntent.id
    else if result.paymentIntent?.status is 'canceled'
      throw new Error 'Payment was canceled. Please try again.'
    else if result.paymentIntent?.status is 'requires_capture'
      throw new Error 'Payment requires manual capture. Please contact support.'
    else
      console.error "Unhandled payment status: #{result.paymentIntent?.status}"
      showMessage "Payment status: #{result.paymentIntent?.status}. Please contact support.", 'error'
      await checkPaymentStatus result.paymentIntent.id

  catch err
    console.error 'Process payment error:', err
    console.error 'Error details:', JSON.stringify(err, null, 2)

    errorMessage = err.message or 'An unexpected error occurred'

    if errorMessage.includes 'payment_method'
      errorMessage = 'Unable to verify your bank account. Please check your account details and try again.'
    else if errorMessage.includes 'insufficient_funds'
      errorMessage = 'Insufficient funds in your bank account.'
    else if errorMessage.includes 'account_closed'
      errorMessage = 'The bank account appears to be closed or invalid.'

    showMessage errorMessage, 'error'
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
      else if status.status is 'canceled'
        throw new Error 'Payment was canceled'
      else if status.status is 'requires_capture'
        throw new Error 'Payment requires manual capture. Contact support.'
      else
        throw new Error "Payment failed with status: #{status.status}"

    await checkStatus()

  catch err
    console.error 'Check payment status error:', err
    showMessage err.message, 'error'


confirmPayment = (paymentIntentId) ->
  try
    confirmBody = { paymentIntentId }
    if currentYear and currentMonth
      confirmBody.year  = currentYear
      confirmBody.month = currentMonth
    response = await fetch '/payment/confirm',
      method  : 'POST'
      headers : 'Content-Type': 'application/json'
      body    : JSON.stringify confirmBody

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
