express    = require 'express'
cors       = require 'cors'
config     = require './lib/config.coffee'
middleware = require './lib/middleware.coffee'
routing    = require './lib/routing.coffee'
db         = require './lib/db/schema.coffee'


startServer = ->
  await db.initialize()

  app    = express()
  server = null

  middleware.setup app
  routing   .setup app, -> server

  server = app.listen config.PORT, ->
    console.log """
      Tenant Coordinator Service Started
      ==================================
      Port:        #{config.PORT}
      Environment: #{config.NODE_ENV or 'development'}
      Database:    #{config.DB_PATH}

      Timer API available at http://localhost:#{config.PORT}/
    """

    recurringEventsService = require './lib/services/recurring_events.coffee'
    recurringEventsService.scheduleDailyProcessing()
    console.log 'Recurring events daily processing scheduled'

  for signal in ['SIGINT', 'SIGTERM']
    process.on signal, ->
      console.log "\nShutting down gracefully..."
      server.close()
      process.exit 0


startServer().catch (err) ->
  console.error 'Failed to start server:', err
  process.exit 1
