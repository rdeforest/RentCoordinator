express   = require 'express'
cors      = require 'cors'
session   = require 'express-session'
crypto    = require 'crypto'
config    = require './config.coffee'
logger    = require './logger.coffee'


setup = (app) ->
  app.set 'trust proxy', 1

  # Reflecting every origin is a default nobody chose, and `origin: false` is
  # not the opposite of it — cors@2.8.5 reads a falsy origin as "allow any"
  # and is saved only by an early return elsewhere in the library. This app is
  # same-origin, so cors is simply not mounted; CORS_ORIGINS exists for the
  # day that stops being true, and then it needs credentials to be of any use.
  if config.CORS_ORIGINS.length > 0
    app.use cors origin: config.CORS_ORIGINS, credentials: true
  # Capture the raw request bytes so the Stripe webhook can verify its
  # signature (a re-serialized body won't match). JSON parsing for every
  # other route is unchanged.
  app.use express.json
    verify: (req, res, buf) -> req.rawBody = buf
  app.use express.urlencoded extended: true

  app.use session
    secret:            config.SESSION_SECRET
    resave:            false
    saveUninitialized: false
    cookie:
      secure:   config.NODE_ENV is 'production'
      httpOnly: true
      sameSite: 'lax'
      maxAge:   config.SESSION_MAX_AGE

  app.get '/vendor/coffeescript.js', (req, res) ->
    res.type 'application/javascript'
    res.sendFile 'coffeescript.js', root: "#{config.STATIC_DIR}/vendor/"

  app.use '/css',    express.static "#{config.STATIC_DIR}/css"
  app.use '/js',     express.static "#{config.STATIC_DIR}/js"
  app.use '/vendor', express.static "#{config.STATIC_DIR}/vendor"
  app.use '/images', express.static "#{config.STATIC_DIR}/images"

  app.use '/coffee', express.static "#{config.STATIC_DIR}/coffee",
    setHeaders: (res, path) ->
      if path.endsWith '.coffee'
        res.set 'Content-Type', 'text/coffeescript'

  # Add request ID for correlation
  app.use (req, res, next) ->
    req.id = crypto.randomUUID()
    next()


# Express only selects a 4-argument error handler that was registered after
# the route that failed, so this must be the last thing mounted on the app —
# call it after routing.setup, not from setup above.
setupErrorHandler = (app) ->
  app.use (err, req, res, next) ->
    logger.error 'middleware.errorHandler', err,
      { path: req.path, method: req.method },
      req.id

    # Honour the status the error carries. Body-parser marks a malformed JSON
    # body 400; while this handler was dead (bug 21) Express's own handler
    # respected that, and turning every one of them into a 500 would be a
    # regression introduced by fixing the ordering.
    status = err.status or err.statusCode or 500

    res.status(status).json
      error:   if status >= 500 then 'Internal server error' else err.message
      message: if config.NODE_ENV is 'development' then err.message else undefined


requireAuth = (req, res, next) ->
  if config.NODE_ENV is 'test'
    return next()

  if req.session?.authenticated
    next()
  else
    if req.accepts 'html'
      res.redirect 302, '/login.html'
    else
      res.status(401).json
        error:    'Authentication required'
        redirect: '/login.html'


# requireAuth only proves the caller is one of the two whitelisted users.
# Admin routes hand back detokenized PII and raw logs, so they need to know
# which one.
isAdmin = (req) ->
  req.session?.authenticated and config.isAdminEmail req.session.email


# The API gate: always a status and a reason. Sniffing Accept to decide
# between JSON and a redirect does not work — `Accept: */*` is what fetch,
# curl and most HTTP clients send, and req.accepts('html') answers 'html' for
# it, so every API caller would be redirected into a 200 HTML page and its
# response.json() would throw on the doctype.
requireAdmin = (req, res, next) ->
  return next() if isAdmin req

  res.status(403).json error: 'Admin only'


# The page gate, for the one route that serves HTML to a browser. A person who
# is not the admin gets sent somewhere they can use rather than a JSON body
# rendered as a document.
requireAdminPage = (req, res, next) ->
  return next() if isAdmin req

  res.redirect 302, '/'


asyncRoute = (name, handler) -> (req, res) ->
  try
    await handler req, res
  catch err
    logger.error name, err,
      { body: req.body, query: req.query, params: req.params },
      req.id

    statusCode = if err.message?.match /not found/i
      404
    else if err.message?.match /already deleted|not deleted/i
      400
    else
      500

    res.status(statusCode).json error: err.message


module.exports = { setup, setupErrorHandler, requireAuth, requireAdmin, requireAdminPage, asyncRoute }
