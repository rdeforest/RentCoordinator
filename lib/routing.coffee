# lib/routing.coffee

timerService = await import('./services/timer.coffee')
workLogModel = await import('./models/work_log.coffee')
rentRoutes   = await import('./routes/rent.coffee')


export setup = (app) ->
  # Main interface
  app.get '/', (req, res) ->
    res.sendFile 'index.html', root: './static'

  # Rent dashboard
  app.get '/rent', (req, res) ->
    res.sendFile 'rent.html', root: './static'


  # Timer operations
  app.post '/timer/start', (req, res) ->
    { worker, project_id, task_id } = req.body

    if not worker
      return res.status(400).json error: 'Worker required'

    try
      session = await timerService.startTimer worker, project_id, task_id
      res.json session
    catch err
      res.status(400).json error: err.message


  app.post '/timer/stop', (req, res) ->
    { worker, description } = req.body

    if not worker or not description
      return res.status(400).json error: 'Worker and description required'

    try
      workLog = await timerService.stopTimer worker, description
      res.json workLog
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


  # Health check
  app.get '/health', (req, res) ->
    res.json
      status: 'healthy'
      timestamp: new Date().toISOString()