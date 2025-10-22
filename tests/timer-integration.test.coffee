# tests/timer-integration.test.coffee
# Integration tests for the timer workflow

{ describe, it, before, after } = await import('node:test')
assert = await import('node:assert/strict')
fs = await import('fs')
{ waitForServer } = await import('./test-helper.js')

# Test configuration
TEST_PORT = 3999
TEST_DB = './test-timer-integration.db'
BASE_URL = "http://localhost:#{TEST_PORT}"

# Server instance
server = null
serverProcess = null

describe 'Timer Integration Tests', ->
  before ->
    # Clean up test database
    if fs.existsSync(TEST_DB)
      fs.unlinkSync(TEST_DB)

    # Set test environment
    process.env.PORT = TEST_PORT
    process.env.DB_PATH = TEST_DB
    process.env.NODE_ENV = 'test'

    # Import server module to start it
    main = await import('../main.js')

    # Wait for server to be ready
    await waitForServer("#{BASE_URL}/health")

  after ->
    # Clean up database
    if fs.existsSync(TEST_DB)
      fs.unlinkSync(TEST_DB)

    # Force exit after cleanup (server doesn't have clean shutdown yet)
    setTimeout ->
      process.exit(0)
    , 100

  it 'should complete a full work session workflow', ->
    worker = 'robert'

    # 1. Start a timer
    startResponse = await fetch "#{BASE_URL}/timer/start",
      method: 'POST'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify { worker }

    assert.equal startResponse.status, 200, "Expected 200, got #{startResponse.status}"
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

  it 'should handle sessions under 1 minute', ->
    worker = 'robert'

    # Start a timer
    startResponse = await fetch "#{BASE_URL}/timer/start",
      method: 'POST'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify { worker }

    assert.equal startResponse.status, 200

    # Stop immediately (under 60 seconds)
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
