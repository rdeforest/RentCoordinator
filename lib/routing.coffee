# lib/routing.coffee

config                = require './config.coffee'
timerService          = require './services/timer.coffee'
workLogModel          = require './models/work_log.coffee'
rentRoutes            = require './routes/rent.coffee'
workRoutes            = require './routes/work.coffee'
recurringEventsRoutes = require './routes/recurring_events.coffee'
authRoutes            = require './routes/auth.coffee'
paymentRoutes         = require './routes/payment.coffee'
middleware            = require './middleware.coffee'


setup = (app) ->
  # Health check (public)
  app.get '/health', (req, res) ->
    res.json
      status: 'healthy'
      timestamp: new Date().toISOString()

  # Set up auth routes (public)
  authRoutes.setup(app)

  # Login page (public)
  app.get '/login.html', (req, res) ->
    res.sendFile 'login.html', root: config.STATIC_DIR

  # Stripe publishable key (public - safe to expose)
  app.get '/payment/config', (req, res) ->
    res.json
      publishableKey: config.STRIPE_PUBLISHABLE_KEY

  # Apply authentication to all routes below this point
  app.use middleware.requireAuth

  # Main interface
  app.get '/', (req, res) ->
    res.sendFile 'index.html', root: config.STATIC_DIR

  # Rent dashboard
  app.get '/rent', (req, res) ->
    res.sendFile 'rent.html', root: config.STATIC_DIR

  # Work management
  app.get '/work', (req, res) ->
    res.sendFile 'work.html', root: config.STATIC_DIR

  # Payment page
  app.get '/payment', (req, res) ->
    res.sendFile 'payment.html', root: config.STATIC_DIR


  # Timer operations
  app.post '/timer/start', (req, res) ->
    { worker, project_id, task_id } = req.body

    if not worker
      return res.status(400).json error: 'Worker required'

    try
      result = await timerService.startTimer worker, project_id, task_id
      res.json result
    catch err
      res.status(400).json error: err.message


  app.post '/timer/pause', (req, res) ->
    { worker } = req.body

    if not worker
      return res.status(400).json error: 'Worker required'

    try
      session = await timerService.pauseTimer worker
      res.json session
    catch err
      res.status(400).json error: err.message


  app.post '/timer/resume', (req, res) ->
    { worker, session_id } = req.body

    if not worker
      return res.status(400).json error: 'Worker required'

    try
      result = await timerService.resumeTimer worker, session_id
      res.json result
    catch err
      res.status(400).json error: err.message


  app.post '/timer/stop', (req, res) ->
    { worker, completed } = req.body

    if not worker
      return res.status(400).json error: 'Worker required'

    try
      result = await timerService.stopTimer worker, completed ? true
      res.json result
    catch err
      res.status(400).json error: err.message


  app.put '/timer/description', (req, res) ->
    { worker, description } = req.body

    if not worker
      return res.status(400).json error: 'Worker required'

    try
      session = await timerService.updateDescription worker, description
      res.json session
    catch err
      res.status(400).json error: err.message


  app.get '/timer/status', (req, res) ->
    { worker } = req.query

    if not worker
      return res.status(400).json error: 'Worker required'

    try
      status = await timerService.getStatus worker
      res.json status
    catch err
      res.status(400).json error: err.message


  app.get '/timer/sessions', (req, res) ->
    { worker } = req.query

    if not worker
      return res.status(400).json error: 'Worker required'

    try
      sessions = await timerService.getAllSessions worker
      res.json sessions
    catch err
      res.status(400).json error: err.message


  # Work logs
  app.get '/work-logs', (req, res) ->
    { worker, project_id, limit } = req.query

    try
      logs = await workLogModel.getWorkLogs
        worker: worker
        project_id: project_id
        limit: limit ? 50

      res.json logs
    catch err
      res.status(500).json error: err.message


  # Set up rent routes
  rentRoutes.setup(app)

  # Set up work management routes
  workRoutes.setup(app)

  # Set up recurring events routes
  recurringEventsRoutes.setup(app)

  # Set up payment routes
  paymentRoutes.setup(app)

module.exports = { setup }