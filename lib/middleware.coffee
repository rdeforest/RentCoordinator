# lib/middleware.coffee

express = (await import('express')).default
cors    = (await import('cors')).default
config  = await import('./config.coffee')


export setup = (app) ->
  # CORS for potential future API clients
  app.use cors()
  
  # Body parsing
  app.use express.json()
  app.use express.urlencoded(extended: true)
  
  # Static files
  app.use express.static('static')
  
  # Request logging in development
  if config.NODE_ENV is 'development'
    app.use (req, res, next) ->
      console.log "#{new Date().toISOString()} #{req.method} #{req.path}"
      next()
  
  # Always log health checks to debug ALB
  app.use (req, res, next) ->
    if req.path is '/health'
      console.log "Health check from #{req.ip}"
    next()
  
  # Error handling
  app.use (err, req, res, next) ->
    console.error 'Error:', err.stack
    res.status(500).json
      error: 'Internal server error'
      message: if config.NODE_ENV is 'development' then err.message else undefined