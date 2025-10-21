# lib/middleware.coffee

express        = (await import('express')).default
cors           = (await import('cors')).default
session        = (await import('express-session')).default
config         = await import('./config.coffee')


export setup = (app) ->
  # Trust proxy (for ALB HTTPS termination)
  # This allows secure cookies to work when behind a load balancer
  app.set 'trust proxy', 1

  # CORS for potential future API clients
  app.use cors()

  # Body parsing
  app.use express.json()
  app.use express.urlencoded(extended: true)

  # Session management
  app.use session
    secret:            config.SESSION_SECRET
    resave:            false
    saveUninitialized: false
    cookie:
      secure:   config.NODE_ENV is 'production'
      httpOnly: true
      maxAge:   config.SESSION_MAX_AGE

  # Serve CoffeeScript browser compiler from static/vendor
  app.get '/vendor/coffeescript.js', (req, res) ->
    res.type('application/javascript')
    res.sendFile 'coffeescript.js',
      root: "#{config.STATIC_DIR}/vendor/"

  # Static assets (CSS, JS, images, etc.) - but NOT HTML files
  # HTML files will be served through explicit routes with auth
  app.use '/css',    express.static("#{config.STATIC_DIR}/css")
  app.use '/js',     express.static("#{config.STATIC_DIR}/js")
  app.use '/vendor', express.static("#{config.STATIC_DIR}/vendor")
  app.use '/images', express.static("#{config.STATIC_DIR}/images")

  # Serve CoffeeScript files with correct MIME type
  app.use '/coffee', express.static("#{config.STATIC_DIR}/coffee",
    setHeaders: (res, path) ->
      if path.endsWith('.coffee')
        res.set('Content-Type', 'text/coffeescript'))

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


# Authentication middleware - checks if user is authenticated
export requireAuth = (req, res, next) ->
  if req.session?.authenticated
    next()
  else
    # For browser requests (HTML pages), redirect to login
    # For API requests (JSON), return 401
    if req.accepts('html')
      res.redirect(302, '/login.html')
    else
      res.status(401).json
        error: 'Authentication required'
        redirect: '/login.html'