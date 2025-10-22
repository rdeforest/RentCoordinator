# lib/routes/auth.coffee

authModel = require '../models/auth.coffee'


setup = (app) ->
  # Send verification code to email
  app.post '/auth/send-code', (req, res) ->
    { email } = req.body

    if not email
      return res.status(400).json error: 'Email required'

    try
      result = await authModel.sendVerificationCode(email)
      res.json result
    catch err
      console.error 'Send code error:', err
      res.status(400).json error: err.message


  # Verify code and create session
  app.post '/auth/verify-code', (req, res) ->
    { email, code } = req.body

    if not email or not code
      return res.status(400).json error: 'Email and code required'

    try
      result = await authModel.verifyCode(email, code)

      if result.success
        # Set session
        req.session.email = email
        req.session.authenticated = true

        res.json
          success: true
          email:   email
      else
        res.status(400).json result
    catch err
      console.error 'Verify code error:', err
      res.status(500).json error: 'Verification failed'


  # Check authentication status
  app.get '/auth/status', (req, res) ->
    if req.session?.authenticated
      res.json
        authenticated: true
        email:         req.session.email
    else
      res.json
        authenticated: false


  # Logout
  app.post '/auth/logout', (req, res) ->
    req.session.destroy (err) ->
      if err
        console.error 'Logout error:', err
        return res.status(500).json error: 'Logout failed'

      res.json success: true

module.exports = { setup }
