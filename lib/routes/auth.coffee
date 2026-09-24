authModel = require '../models/auth.coffee'
{ AUTHORIZATION_REJECTION } = authModel
rateLimit = require '../rate_limit.coffee'
config    = require '../config.coffee'
logger    = require '../logger.coffee'


LIMITS =
  'send-code':
    email:    config.SEND_CODE_LIMIT
    ip:       config.SEND_CODE_IP_LIMIT
    windowMs: config.SEND_CODE_WINDOW
  'verify-code':
    email:    config.VERIFY_RATE_LIMIT
    ip:       config.VERIFY_IP_LIMIT
    windowMs: config.VERIFY_RATE_WINDOW


# An address long enough to matter is an attack on the counter map, not a
# login attempt. Truncate before it becomes a key.
MAX_KEY_EMAIL = 128

# RFC 5321's limit. Anything longer is not an address, and letting it through
# put attacker-sized strings into the rate-limit map, the database and the log.
MAX_EMAIL_LENGTH = 254

# The address bucket is consulted first, and deliberately: it is the one that
# bounds how many keys a single caller can create, so checking it second let a
# spray insert a key per made-up address before being rejected.
#
# The second key is (address, email), not email alone. An email-only bucket is
# an unauthenticated lockout — both addresses are published, so anyone could
# spend the real user's budget from anywhere.
#
# Behind the ALB the socket address is the balancer's; `trust proxy` is set in
# middleware.setup, which makes req.ip the X-Forwarded-For client.
throttle = (req, res, bucket, email) ->
  limits = LIMITS[bucket]
  caller = req.ip
  scoped = "#{caller}|#{email[0...MAX_KEY_EMAIL]}"

  for [key, limit] in [["#{bucket}:ip:#{caller}", limits.ip], ["#{bucket}:caller:#{scoped}", limits.email]]
    result = rateLimit.hit key, limit, limits.windowMs

    unless result.allowed
      res.set 'Retry-After', String result.retryAfter
      res.status(429).json
        error:      'Too many requests. Try again later.'
        retryAfter: result.retryAfter
      return false

  return true


setup = (app) ->
  app.post '/auth/send-code', (req, res) ->
    email = authModel.normalizeEmail req.body?.email

    unless email
      return res.status(400).json error: 'Email required'

    if email.length > MAX_EMAIL_LENGTH
      return res.status(400).json error: 'Email address is too long'

    return unless throttle req, res, 'send-code', email

    try
      result = await authModel.sendVerificationCode email
      res.json result
    catch err
      # A refused address is not a user, and not an error worth a stack
      # trace — it's whatever an anonymous caller typed into the login form.
      # logger.error tokenizes it into pii_tokens forever regardless of
      # outcome (bug 60); a rejection this routine and this common must not
      # be the reason a made-up address becomes a permanent row. Handled
      # first, and logged at most as a warning with no address and no stack.
      if err.message is AUTHORIZATION_REJECTION
        logger.warn 'auth.sendCode.rejected',
          'refused a send-code request for an address not on the allowlist',
          {},
          req.id
        return res.status(400).json error: err.message

      logger.error 'auth.sendCode', err,
        { email },
        req.id

      res.status(500).json error: 'Could not send a verification code'

  app.post '/auth/verify-code', (req, res) ->
    email    = authModel.normalizeEmail req.body?.email
    { code } = req.body

    unless email and code
      return res.status(400).json error: 'Email and code required'

    if email.length > MAX_EMAIL_LENGTH
      return res.status(400).json error: 'Email address is too long'

    return unless throttle req, res, 'verify-code', email

    try
      result = await authModel.verifyCode email, code

      if result.success
        req.session.email         = email
        req.session.authenticated = true

        await new Promise (resolve, reject) ->
          req.session.save (err) ->
            if err then reject err else resolve()

        res.json
          success: true
          email:   email
      else
        res.status(400).json result
    catch err
      logger.error 'auth.verifyCode', err,
        { email },
        req.id
      res.status(500).json error: 'Verification failed'

  app.get '/auth/status', (req, res) ->
    if req.session?.authenticated
      res.json
        authenticated: true
        email:         req.session.email
    else
      res.json
        authenticated: false

  app.post '/auth/logout', (req, res) ->
    email = req.session?.email

    req.session.destroy (err) ->
      if err
        logger.error 'auth.logout', err,
          { email },
          req.id
        return res.status(500).json error: 'Logout failed'

      res.json success: true

module.exports = { setup }
