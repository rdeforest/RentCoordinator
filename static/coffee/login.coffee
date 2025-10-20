# static/coffee/login.coffee

# DOM elements
emailForm   = null
verifyForm  = null
emailStep   = null
verifyStep  = null
emailInput  = null
codeInput   = null
messageDiv  = null

currentEmail = null


# Initialize on DOM load
document.addEventListener 'DOMContentLoaded', ->
  emailForm  = document.getElementById('emailForm')
  verifyForm = document.getElementById('verifyForm')
  emailStep  = document.getElementById('emailStep')
  verifyStep = document.getElementById('verifyStep')
  emailInput = document.getElementById('email')
  codeInput  = document.getElementById('code')
  messageDiv = document.getElementById('message')

  backLink = document.getElementById('backToEmail')

  # Set up event listeners
  emailForm.addEventListener  'submit', handleEmailSubmit
  verifyForm.addEventListener 'submit', handleVerifySubmit
  backLink.addEventListener   'click',  handleBackToEmail

  # Check if already authenticated
  checkAuthStatus()


# Check if user is already authenticated
checkAuthStatus = ->
  try
    response = await fetch('/auth/status')
    data = await response.json()

    if data.authenticated
      # Already logged in, redirect to home
      window.location.href = '/'
  catch err
    console.error 'Auth check failed:', err


# Handle email form submission
handleEmailSubmit = (e) ->
  e.preventDefault()

  email = emailInput.value.trim()
  if not email
    return showMessage 'Please enter your email address', 'error'

  currentEmail = email

  # Disable form
  emailForm.querySelector('button').disabled = true
  showMessage 'Sending verification code...', 'success'

  try
    response = await fetch '/auth/send-code',
      method: 'POST'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify(email: email)

    data = await response.json()

    if response.ok
      showMessage 'Verification code sent! Check your email (or console in dev mode)', 'success'
      showVerifyStep()
    else
      showMessage data.error or 'Failed to send code', 'error'
      emailForm.querySelector('button').disabled = false
  catch err
    console.error 'Send code error:', err
    showMessage 'Network error. Please try again.', 'error'
    emailForm.querySelector('button').disabled = false


# Handle verification form submission
handleVerifySubmit = (e) ->
  e.preventDefault()

  code = codeInput.value.trim()
  if not code or code.length isnt 6
    return showMessage 'Please enter the 6-digit code', 'error'

  # Disable form
  verifyForm.querySelector('button').disabled = true
  showMessage 'Verifying code...', 'success'

  try
    response = await fetch '/auth/verify-code',
      method: 'POST'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify
        email: currentEmail
        code:  code

    data = await response.json()

    if response.ok
      showMessage 'Success! Redirecting...', 'success'
      # Redirect to home page after a brief delay
      setTimeout (-> window.location.href = '/'), 1000
    else
      showMessage data.error or 'Invalid or expired code', 'error'
      verifyForm.querySelector('button').disabled = false
      codeInput.value = ''
      codeInput.focus()
  catch err
    console.error 'Verify code error:', err
    showMessage 'Network error. Please try again.', 'error'
    verifyForm.querySelector('button').disabled = false


# Show verify step
showVerifyStep = ->
  emailStep.style.display  = 'none'
  verifyStep.style.display = 'block'
  codeInput.value = ''
  codeInput.focus()


# Back to email entry
handleBackToEmail = (e) ->
  e.preventDefault()
  emailStep.style.display  = 'block'
  verifyStep.style.display = 'none'
  emailForm.querySelector('button').disabled = false
  emailInput.focus()
  showMessage '', ''


# Show message to user
showMessage = (text, type) ->
  if not text
    messageDiv.innerHTML = ''
    messageDiv.className = 'message'
    return

  messageDiv.textContent = text
  messageDiv.className = "message #{type}"
