express = require 'express'
cors    = require 'cors'
session = require 'express-session'
crypto  = require 'crypto'
config  = require './config.coffee'
logger  = require './logger.coffee'


setup = (app) ->
  app.set 'trust proxy', 1

  app.use cors()
  app.use express.json()
  app.use express.urlencoded extended: true

  app.use session
    secret:            config.SESSION_SECRET
    resave:            false
    saveUninitialized: false
    cookie:
      secure:   config.NODE_ENV is 'production'
      httpOnly: true
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

  # Error handler with structured logging
  app.use (err, req, res, next) ->
    logger.error 'middleware.errorHandler', err,
      { path: req.path, method: req.method },
      req.id

    res.status(500).json
      error:   'Internal server error'
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


module.exports = { setup, requireAuth, asyncRoute }
