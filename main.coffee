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


# Graceful shutdown
for signal in ['SIGINT', 'SIGTERM']
  Deno.addSignalListener signal, ->
    console.log "\nShutting down gracefully..."
    server.close()
    Deno.exit(0)