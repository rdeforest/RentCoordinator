express = require 'express'
cors    = require 'cors'
session = require 'express-session'
config  = require './config.coffee'


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
  app.use '/js',     express.static './dist/static/js'
  app.use '/vendor', express.static "#{config.STATIC_DIR}/vendor"
  app.use '/images', express.static "#{config.STATIC_DIR}/images"

  app.use '/coffee', express.static "#{config.STATIC_DIR}/coffee",
    setHeaders: (res, path) ->
      if path.endsWith '.coffee'
        res.set 'Content-Type', 'text/coffeescript'

  if config.NODE_ENV is 'development'
    app.use (req, res, next) ->
      console.log "#{new Date().toISOString()} #{req.method} #{req.path}"
      next()

  app.use (req, res, next) ->
    if req.path is '/health'
      console.log "Health check from #{req.ip}"
    next()

  app.use (err, req, res, next) ->
    console.error 'Error:', err.stack
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


module.exports = { setup, requireAuth }
