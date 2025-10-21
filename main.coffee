express    = (await import('express')).default
cors       = (await import('cors')).default

config     = await import('./lib/config.coffee')
middleware = await import('./lib/middleware.coffee')
routing    = await import('./lib/routing.coffee')
db         = await import('./lib/db/schema.coffee')


# Initialize database on startup
await db.initialize()


# Create and configure Express app
app = express()

middleware.setup(app)
routing   .setup(app)


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
  recurringEventsService = await import('./lib/services/recurring_events.coffee')
  recurringEventsService.scheduleDailyProcessing()
  console.log 'Recurring events daily processing scheduled'


# Graceful shutdown
for signal in ['SIGINT', 'SIGTERM']
  process.on signal, ->
    console.log "\nShutting down gracefully..."
    server.close()
    process.exit(0)