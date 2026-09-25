express         = require 'express'
cors            = require 'cors'
{ execSync }    = require 'child_process'
fs              = require 'node:fs'
config          = require './lib/config.coffee'
middleware      = require './lib/middleware.coffee'
routing         = require './lib/routing.coffee'
db              = require './lib/db/schema.coffee'
logger          = require './lib/logger.coffee'


CLIENT_SOURCE = 'static/coffee'


# Running from source, the client JavaScript is compiled at startup so an edit
# needs no separate step. The compiled artifact has no CoffeeScript to compile
# — the build did it — and this used to run unconditionally against a path
# that is not there, so the artifact exited before it ever listened.
compileClient = ->
  unless fs.existsSync CLIENT_SOURCE
    console.log 'No client CoffeeScript source; serving the compiled output in static/js'
    return

  console.log 'Compiling client-side CoffeeScript...'
  # Output for a deleted source would otherwise be served for ever.
  fs.rmSync 'static/js', recursive: true, force: true
  execSync "npx coffee -b -c -M -o static/js #{CLIENT_SOURCE}", stdio: 'inherit'
  console.log '✓ Client-side compilation complete\n'


# A rejection that escapes every handler used to take the process down with
# it (bug 50: a malformed request could throw inside asyncRoute's own catch,
# turning a 500 into a crash). Logging it is best-effort — a broken logger
# must not turn this into a second unhandled rejection.
handleUnhandledRejection = (reason) ->
  try
    logger.error 'process.unhandledRejection', (if reason instanceof Error then reason else new Error String reason)
  catch loggingErr
    console.error 'unhandledRejection: failed to log', loggingErr?.message


startServer = ->
  compileClient()

  await db.initialize()

  app    = express()
  server = null

  middleware.setup             app
  routing   .setup             app, -> server
  middleware.setupErrorHandler app

  server = app.listen config.PORT, ->
    console.log """
      Tenant Coordinator Service Started
      ==================================
      Port:        #{config.PORT}
      Environment: #{config.NODE_ENV or 'development'}
      Database:    #{config.DB_PATH}

      Timer API available at http://localhost:#{config.PORT}/
    """


    backupService = require './lib/services/backup.coffee'
    backupService.startIdleBackup()

    # Mark application as fully ready (for health checks)
    routing.markAppReady()
    console.log 'Application ready - health checks will pass'

  for signal in ['SIGINT', 'SIGTERM']
    process.on signal, ->
      console.log "\nShutting down gracefully..."
      server.close()
      process.exit 0


module.exports = { startServer, handleUnhandledRejection }

if require.main is module
  process.on 'unhandledRejection', handleUnhandledRejection

  startServer().catch (err) ->
    console.error 'Failed to start server:', err
    process.exit 1
