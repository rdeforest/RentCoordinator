express    = require 'express'
cors       = require 'cors'
config     = require './lib/config.coffee'
middleware = require './lib/middleware.coffee'
routing    = require './lib/routing.coffee'
db         = require './lib/db/schema.coffee'


# Main startup function
startServer = ->
  # Initialize database on startup
  await db.initialize()

  # Create and configure Express app
  app = express()

  middleware.setup(app)
  routing.setup(app)

  # Start server
  server = app.listen config.PORT, ->
    console.log """
      Tenant Coordinator Service Started
      ==================================
      Port:        #{config.PORT}
      Environment: #{config.NODE_ENV or 'development'}
      Database:    #{config.DB_PATH}

      Timer API available at http://localhost:#{config.PORT}/
    """

    # Start recurring events daily processing
    recurringEventsService = require './lib/services/recurring_events.coffee'
    recurringEventsService.scheduleDailyProcessing()
    console.log 'Recurring events daily processing scheduled'

  # Graceful shutdown
  for signal in ['SIGINT', 'SIGTERM']
    process.on signal, ->
      console.log "\nShutting down gracefully..."
      server.close()
      process.exit(0)


# Start the server
startServer().catch (err) ->
  console.error 'Failed to start server:', err
  process.exit(1)