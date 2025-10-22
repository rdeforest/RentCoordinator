# tests/test-server.coffee
# Reusable test server setup and teardown

fs = await import('fs')
{ execSync } = await import('child_process')
{ waitForServer } = await import('./test-helper.js')

# Default test configuration
export DEFAULT_TEST_PORT = 3999
export DEFAULT_TEST_DB = './test-server.db'

# Kill any process on a given port
export killPort = (port) ->
  try
    execSync("lsof -ti :#{port} | xargs -r kill -9", stdio: 'ignore')
    # Small delay to ensure port is released
    await new Promise (resolve) -> setTimeout(resolve, 100)
  catch err
    # No process was using the port, which is fine

# Clean up all test databases
export cleanTestDatabases = ->
  try
    files = fs.readdirSync('.')
    for file in files when file.match(/^test.*\.db$/)
      fs.unlinkSync(file)
      console.log "Cleaned up: #{file}"
  catch err
    # Ignore cleanup errors

# Start test server with given configuration
export startTestServer = (options = {}) ->
  port = options.port or DEFAULT_TEST_PORT
  dbPath = options.dbPath or DEFAULT_TEST_DB
  baseUrl = "http://localhost:#{port}"

  # Ensure clean environment
  await killPort(port)
  cleanTestDatabases()

  # Set test environment
  process.env.PORT = port
  process.env.DB_PATH = dbPath
  process.env.NODE_ENV = 'test'

  # Import server module to start it
  main = await import('../main.js')

  # Wait for server to be ready
  await waitForServer("#{baseUrl}/health")

  return { port, dbPath, baseUrl }

# Stop test server and clean up
export stopTestServer = (options = {}) ->
  port = options.port or DEFAULT_TEST_PORT

  # Kill test server
  await killPort(port)

  # Clean up databases
  cleanTestDatabases()

# Force exit (for use in after() hooks since server doesn't have clean shutdown)
export forceExit = (delayMs = 100) ->
  setTimeout ->
    process.exit(0)
  , delayMs
