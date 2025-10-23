emailForm    = null
verifyForm   = null
emailStep    = null
verifyStep   = null
emailInput   = null
codeInput    = null
messageDiv   = null
currentEmail = null


document.addEventListener 'DOMContentLoaded', ->
  emailForm  = document.getElementById 'emailForm'
  verifyForm = document.getElementById 'verifyForm'
  emailStep  = document.getElementById 'emailStep'
  verifyStep = document.getElementById 'verifyStep'
  emailInput = document.getElementById 'email'
  codeInput  = document.getElementById 'code'
  messageDiv = document.getElementById 'message'
  backLink   = document.getElementById 'backToEmail'

  emailForm .addEventListener 'submit', handleEmailSubmit
  verifyForm.addEventListener 'submit', handleVerifySubmit
  backLink  .addEventListener 'click',  handleBackToEmail

  checkAuthStatus()


checkAuthStatus = ->
  try
    response = await fetch '/auth/status'
    data     = await response.json()

    window.location.href = '/' if data.authenticated
  catch err
    console.error 'Auth check failed:', err


handleEmailSubmit = (e) ->
  e.preventDefault()

  email = emailInput.value.trim()
  return showMessage 'Please enter your email address', 'error' unless email

  currentEmail = email

  emailForm.querySelector('button').disabled = true
  showMessage 'Sending verification code...', 'success'

  try
    response = await fetch '/auth/send-code',
      method  : 'POST'
      headers : 'Content-Type': 'application/json'
      body    : JSON.stringify email: email

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


handleVerifySubmit = (e) ->
  e.preventDefault()

  code = codeInput.value.trim()
  return showMessage 'Please enter the 6-digit code', 'error' unless code and code.length is 6

  verifyForm.querySelector('button').disabled = true
  showMessage 'Verifying code...', 'success'

  try
    response = await fetch '/auth/verify-code',
      method  : 'POST'
      headers : 'Content-Type': 'application/json'
      body    : JSON.stringify
        email : currentEmail
        code  : code

    data = await response.json()

    if response.ok
      showMessage 'Success! Redirecting...', 'success'
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


showVerifyStep = ->
  emailStep .style.display = 'none'
  verifyStep.style.display = 'block'
  codeInput.value = ''
  codeInput.focus()


handleBackToEmail = (e) ->
  e.preventDefault()
  emailStep .style.display = 'block'
  verifyStep.style.display = 'none'
  emailForm.querySelector('button').disabled = false
  emailInput.focus()
  showMessage '', ''


showMessage = (text, type) ->
  unless text
    messageDiv.innerHTML = ''
    messageDiv.className = 'message'
    return

  messageDiv.textContent = text
  messageDiv.className   = "message #{type}"
