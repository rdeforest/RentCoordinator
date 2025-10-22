# test/server.coffee
# Reusable test server setup and teardown

fs   = require 'fs'
path = require 'path'
{ execSync } = require 'child_process'
{ waitForServer } = require './helper.coffee'

# Test directory configuration
TEST_TMP_DIR = '/tmp/rent-coordinator-tests'
DEFAULT_TEST_PORT = 3999
DEFAULT_TEST_DB = path.join(TEST_TMP_DIR, 'test-server.db')

# Ensure test tmp directory exists and is clean
prepareTestDirectory = ->
  try
    # Remove entire test directory if it exists
    if fs.existsSync(TEST_TMP_DIR)
      fs.rmSync(TEST_TMP_DIR, recursive: true, force: true)

    # Create fresh test directory
    fs.mkdirSync(TEST_TMP_DIR, recursive: true)
  catch err
    console.error "Failed to prepare test directory: #{err.message}"
    throw err

# Clean up test directory
cleanupTestDirectory = ->
  try
    if fs.existsSync(TEST_TMP_DIR)
      fs.rmSync(TEST_TMP_DIR, recursive: true, force: true)
  catch err
    # Ignore cleanup errors

# Kill any process on a given port
killPort = (port) ->
  try
    execSync("lsof -ti :#{port} | xargs -r kill -9", stdio: 'ignore')
    # Small delay to ensure port is released
    await new Promise (resolve) -> setTimeout(resolve, 100)
  catch err
    # No process was using the port, which is fine

# Start test server with given configuration
startTestServer = (options = {}) ->
  port = options.port or DEFAULT_TEST_PORT
  dbPath = options.dbPath or DEFAULT_TEST_DB
  baseUrl = "http://localhost:#{port}"
  logPath = path.join(TEST_TMP_DIR, 'server.log')

  # Ensure clean environment
  prepareTestDirectory()
  await killPort(port)

  # Start server as a background process using coffee directly
  # Log to tmp directory for debugging
  execSync "PORT=#{port} DB_PATH=#{dbPath} NODE_ENV=test coffee main.coffee > #{logPath} 2>&1 &",
    stdio: 'ignore'
    shell: true

  # Give server a moment to start
  await new Promise (resolve) -> setTimeout(resolve, 1000)

  # Wait for server to be ready
  await waitForServer("#{baseUrl}/health")

  return { port, dbPath, baseUrl, logPath }

# Stop test server and clean up
stopTestServer = (options = {}) ->
  port = options.port or DEFAULT_TEST_PORT

  # Kill test server
  await killPort(port)

  # Clean up test directory
  cleanupTestDirectory()

# Force exit (for use in after() hooks since server doesn't have clean shutdown)
forceExit = (delayMs = 100) ->
  setTimeout ->
    process.exit(0)
  , delayMs

module.exports = {
  TEST_TMP_DIR
  DEFAULT_TEST_PORT
  DEFAULT_TEST_DB
  prepareTestDirectory
  cleanupTestDirectory
  killPort
  startTestServer
  stopTestServer
  forceExit
}
