# test/integration/timer.coffee
# Integration tests for the timer workflow

{ describe, it, before, after } = require 'node:test'
assert = require 'node:assert/strict'
fs   = require 'fs'
path = require 'path'
{ execSync } = require 'child_process'
{ waitForServer } = require '../helper.coffee'

# Test configuration
TEST_TMP_DIR = '/tmp/rent-coordinator-tests'
TEST_PORT = 3999
TEST_DB = path.join(TEST_TMP_DIR, 'test-timer-integration.db')
TEST_LOG = path.join(TEST_TMP_DIR, 'integration.log')
BASE_URL = "http://localhost:#{TEST_PORT}"

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

# Helper to kill any process on the test port
killTestPort = ->
  try
    # Find and kill any process on TEST_PORT
    execSync("lsof -ti :#{TEST_PORT} | xargs -r kill -9", stdio: 'ignore')
    # Small delay to ensure port is released
    await new Promise (resolve) -> setTimeout(resolve, 100)
  catch err
    # No process was using the port, which is fine

describe 'Timer Integration Tests', ->
  before ->
    # Ensure clean environment before starting
    prepareTestDirectory()
    await killTestPort()

    # Start server as a background process using coffee directly
    # Log to tmp directory for debugging
    execSync "PORT=#{TEST_PORT} DB_PATH=#{TEST_DB} NODE_ENV=test coffee main.coffee > #{TEST_LOG} 2>&1 &",
      stdio: 'ignore'
      shell: true

    # Give server a moment to start
    await new Promise (resolve) -> setTimeout(resolve, 1000)

    # Wait for server to be ready
    await waitForServer("#{BASE_URL}/health")

  after ->
    # Kill test server
    await killTestPort()

    # Clean up test directory
    cleanupTestDirectory()

  it 'should complete a full work session workflow', ->
    worker = 'robert'

    # 1. Start a timer
    requestBody = { worker }
    console.log "Sending request:", JSON.stringify(requestBody)

    startResponse = await fetch "#{BASE_URL}/timer/start",
      method: 'POST'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify requestBody

    if startResponse.status isnt 200
      errorBody = await startResponse.text()
      console.log "Error response (#{startResponse.status}):", errorBody
      assert.equal startResponse.status, 200, "Expected 200, got #{startResponse.status}: #{errorBody}"

    startData = await startResponse.json()
    assert.ok startData.id, 'Should return session ID'
    assert.equal startData.status, 'active'
    sessionId = startData.id

    # 2. Wait a moment for duration to accumulate
    await new Promise (resolve) -> setTimeout(resolve, 1100)

    # 3. Check status shows elapsed time
    statusResponse = await fetch "#{BASE_URL}/timer/status?worker=#{worker}"
    assert.equal statusResponse.status, 200
    statusData = await statusResponse.json()
    assert.ok statusData.current_session, 'Should have current session'
    assert.ok statusData.elapsed >= 1, 'Should have at least 1 second elapsed'

    # 4. Update description
    descResponse = await fetch "#{BASE_URL}/timer/description",
      method: 'PUT'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify
        worker: worker
        description: 'Test work session'

    assert.equal descResponse.status, 200

    # 5. Pause the timer
    pauseResponse = await fetch "#{BASE_URL}/timer/pause",
      method: 'POST'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify { worker }

    assert.equal pauseResponse.status, 200
    pauseData = await pauseResponse.json()
    assert.equal pauseData.status, 'paused'

    # 6. Resume the timer
    resumeResponse = await fetch "#{BASE_URL}/timer/resume",
      method: 'POST'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify { worker, session_id: sessionId }

    assert.equal resumeResponse.status, 200
    resumeData = await resumeResponse.json()
    assert.equal resumeData.status, 'active'

    # 7. Stop (Done) - This was failing with "parameter 10" error
    stopResponse = await fetch "#{BASE_URL}/timer/stop",
      method: 'POST'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify
        worker: worker
        completed: true

    assert.equal stopResponse.status, 200
    stopData = await stopResponse.json()
    assert.ok stopData.work_log, 'Should create work log'
    assert.ok stopData.duration >= 1, 'Should have duration'

    # 8. Verify work log was created
    logsResponse = await fetch "#{BASE_URL}/work-logs?worker=#{worker}&limit=1"
    assert.equal logsResponse.status, 200
    logsData = await logsResponse.json()
    assert.equal logsData.length, 1
    assert.equal logsData[0].description, 'Test work session'

  it 'should handle cancellation without creating work log', ->
    worker = 'lyndzie'

    # Start a timer
    startResponse = await fetch "#{BASE_URL}/timer/start",
      method: 'POST'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify { worker }

    assert.equal startResponse.status, 200

    # Wait a moment
    await new Promise (resolve) -> setTimeout(resolve, 100)

    # Cancel (not completed)
    stopResponse = await fetch "#{BASE_URL}/timer/stop",
      method: 'POST'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify
        worker: worker
        completed: false

    assert.equal stopResponse.status, 200
    stopData = await stopResponse.json()
    assert.equal stopData.event, 'cancelled'
    assert.equal stopData.work_log, undefined, 'Should not create work log on cancel'

  it 'should handle sessions under minimum duration', ->
    worker = 'robert'

    # Start a timer
    startResponse = await fetch "#{BASE_URL}/timer/start",
      method: 'POST'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify { worker }

    assert.equal startResponse.status, 200

    # Stop immediately (under minimum threshold - 1 second in test mode)
    stopResponse = await fetch "#{BASE_URL}/timer/stop",
      method: 'POST'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify
        worker: worker
        completed: true

    assert.equal stopResponse.status, 200
    stopData = await stopResponse.json()
    assert.equal stopData.event, 'completed_too_short'
    assert.equal stopData.work_log, undefined, 'Should not create work log for short sessions'
