config                = require './config.coffee'
timerService          = require './services/timer.coffee'
workLogModel          = require './models/work_log.coffee'
rentRoutes            = require './routes/rent.coffee'
workRoutes            = require './routes/work.coffee'
recurringEventsRoutes = require './routes/recurring_events.coffee'
authRoutes            = require './routes/auth.coffee'
paymentRoutes         = require './routes/payment.coffee'
paymentsRoutes        = require './routes/payments.coffee'
backupRoutes          = require './routes/backup.coffee'
adminRoutes           = require './routes/admin.coffee'
observabilityRoutes   = require './routes/observability.coffee'
middleware            = require './middleware.coffee'
{ DatabaseSync }      = require 'node:sqlite'
pkg                   = require '../package.json'
fs                    = require 'node:fs'


# Startup readiness tracking
appReadyState =
  dbInitialized:     false
  dbConnectable:     false
  schemaValid:       false
  startupComplete:   false
  startTime:         Date.now()


# Mark app as ready (called after successful startup)
markAppReady = ->
  appReadyState.dbInitialized   = true
  appReadyState.dbConnectable   = true
  appReadyState.schemaValid     = true
  appReadyState.startupComplete = true


# Health check with database validation
healthCheck = (req, res) ->
  try
    # Check if database file exists
    unless fs.existsSync config.DB_PATH
      return res.status(503).json
        status:  'unhealthy'
        error:   'Database file not found'
        dbPath:  config.DB_PATH

    # Try to connect and query database
    db = new DatabaseSync config.DB_PATH
    db.exec 'PRAGMA foreign_keys = ON'

    # Verify critical tables exist
    tables = db.prepare("""
      SELECT name FROM sqlite_master
      WHERE type='table' AND name IN ('work_logs', 'rent_periods', 'timer_state')
    """).all()

    db.close()

    if tables.length < 3
      return res.status(503).json
        status:       'unhealthy'
        error:        'Database schema incomplete'
        foundTables:  tables.length
        expectedTables: 3

    # All checks passed
    appReadyState.dbConnectable = true
    appReadyState.schemaValid = true

    res.json
      status:    'healthy'
      version:   pkg.version
      uptime:    Math.floor((Date.now() - appReadyState.startTime) / 1000)
      timestamp: new Date().toISOString()
      ready:     appReadyState.startupComplete

  catch error
    console.error 'Health check failed:', error.message
    res.status(503).json
      status:    'unhealthy'
      error:     error.message
      timestamp: new Date().toISOString()


# Readiness check (stricter - only passes after full initialization)
readinessCheck = (req, res) ->
  if appReadyState.startupComplete
    res.json
      status:  'ready'
      version: pkg.version
      uptime:  Math.floor((Date.now() - appReadyState.startTime) / 1000)
  else
    res.status(503).json
      status:         'not_ready'
      dbInitialized:  appReadyState.dbInitialized
      dbConnectable:  appReadyState.dbConnectable
      schemaValid:    appReadyState.schemaValid
      startupComplete: appReadyState.startupComplete


setup = (app, getServer) ->
  # Health check endpoint (with DB validation)
  app.get '/health', healthCheck

  # Readiness check endpoint (only passes after full startup)
  app.get '/health/ready', readinessCheck

  app.post '/v1/shutdown', (req, res) ->
    unless config.NODE_ENV is 'test'
      return res.status(403).json error: 'Shutdown only allowed in test mode'

    res.json message: 'Server shutting down'

    server = getServer()
    if server
      setTimeout ->
        server.close ->
          process.exit 0
      , 100

  authRoutes.setup app

  app.get '/login.html', (req, res) ->
    res.sendFile 'login.html', root: config.STATIC_DIR

  app.get '/payment/config', (req, res) ->
    res.json publishableKey: config.STRIPE_PUBLISHABLE_KEY

  # Stripe webhook: no session cookie, authenticated by signature instead, so
  # it must be registered ahead of the auth gate.
  paymentRoutes.setupWebhook app

  app.use middleware.requireAuth

  app.get '/',         (req, res) -> res.sendFile 'index.html',    root: config.STATIC_DIR
  app.get '/rent',     (req, res) -> res.sendFile 'rent.html',    root: config.STATIC_DIR
  app.get '/work',     (req, res) -> res.sendFile 'work.html',    root: config.STATIC_DIR
  app.get '/payment',  (req, res) -> res.sendFile 'payment.html', root: config.STATIC_DIR
  app.get '/payments', (req, res) -> res.sendFile 'payments.html', root: config.STATIC_DIR
  app.get '/admin',    (req, res) -> res.sendFile 'admin.html',   root: config.STATIC_DIR


  app.post '/timer/start', (req, res) ->
    { worker, project_id, task_id } = req.body

    return res.status(400).json error: 'Worker required' unless worker

    try
      result = await timerService.startTimer worker, project_id, task_id
      res.json result
    catch err
      res.status(400).json error: err.message


  app.post '/timer/pause', (req, res) ->
    { worker } = req.body

    return res.status(400).json error: 'Worker required' unless worker

    try
      session = await timerService.pauseTimer worker
      res.json session
    catch err
      res.status(400).json error: err.message


  app.post '/timer/resume', (req, res) ->
    { worker, session_id } = req.body

    return res.status(400).json error: 'Worker required' unless worker

    try
      result = await timerService.resumeTimer worker, session_id
      res.json result
    catch err
      res.status(400).json error: err.message


  app.post '/timer/stop', (req, res) ->
    { worker, completed } = req.body

    return res.status(400).json error: 'Worker required' unless worker

    try
      result = await timerService.stopTimer worker, completed ? true
      res.json result
    catch err
      res.status(400).json error: err.message


  app.put '/timer/description', (req, res) ->
    { worker, description } = req.body

    return res.status(400).json error: 'Worker required' unless worker

    try
      session = await timerService.updateDescription worker, description
      res.json session
    catch err
      res.status(400).json error: err.message


  app.get '/timer/status', (req, res) ->
    { worker } = req.query

    return res.status(400).json error: 'Worker required' unless worker

    try
      status = await timerService.getStatus worker
      res.json status
    catch err
      res.status(400).json error: err.message


  app.get '/timer/sessions', (req, res) ->
    { worker } = req.query

    return res.status(400).json error: 'Worker required' unless worker

    try
      sessions = await timerService.getAllSessions worker
      res.json sessions
    catch err
      res.status(400).json error: err.message


  app.get '/work-logs', (req, res) ->
    { worker, project_id, limit } = req.query

    try
      logs = await workLogModel.getWorkLogs
        worker:     worker
        project_id: project_id
        limit:      limit ? 50

      res.json logs
    catch err
      res.status(500).json error: err.message


  rentRoutes           .setup app
  workRoutes           .setup app
  recurringEventsRoutes.setup app
  paymentRoutes        .setup app
  paymentsRoutes       .setup app
  backupRoutes         .setup app
  adminRoutes          .setup app
  observabilityRoutes  .setup app


module.exports = { setup, markAppReady }
