{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
fs                              = require 'fs'
path                            = require 'path'
{ execSync }                    = require 'child_process'
{ waitForServer }               = require '../helper.coffee'
{ findFreePort, shutdownServer }= require '../server.coffee'


TEST_TMP_DIR = '/tmp/rent-coordinator-tests'
BASE_PORT    = 4000
testConfig   = null


prepareTestDirectory = ->
  if fs.existsSync TEST_TMP_DIR
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true
  fs.mkdirSync TEST_TMP_DIR, recursive: true

cleanupTestDirectory = ->
  try
    if fs.existsSync TEST_TMP_DIR
      fs.rmSync TEST_TMP_DIR, recursive: true, force: true


describe 'Timer Integration Tests', ->
  before ->
    prepareTestDirectory()

    port    = findFreePort BASE_PORT
    dbPath  = path.join TEST_TMP_DIR, "test-timer-#{port}.db"
    logPath = path.join TEST_TMP_DIR, "timer-#{port}.log"
    baseUrl = "http://localhost:#{port}"

    execSync "PORT=#{port} DB_PATH=#{dbPath} NODE_ENV=test coffee main.coffee > #{logPath} 2>&1 &",
      stdio: 'ignore'
      shell: true

    await new Promise (resolve) -> setTimeout resolve, 1000
    await waitForServer "#{baseUrl}/health"

    testConfig = { port, dbPath, baseUrl, logPath }

  after ->
    await shutdownServer testConfig.baseUrl if testConfig
    cleanupTestDirectory()


  it 'should complete a full work session workflow', ->
    worker      = 'robert'
    requestBody = { worker }
    console.log "Sending request:", JSON.stringify requestBody

    startResponse = await fetch "#{testConfig.baseUrl}/timer/start",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify requestBody

    if startResponse.status isnt 200
      errorBody = await startResponse.text()
      console.log "Error response (#{startResponse.status}):", errorBody
      assert.equal startResponse.status, 200, "Expected 200, got #{startResponse.status}: #{errorBody}"

    startData = await startResponse.json()
    sessionId = startData.id
    assert.ok    startData.id
    assert.equal startData.status, 'active'

    await new Promise (resolve) -> setTimeout resolve, 1100

    statusResponse = await fetch "#{testConfig.baseUrl}/timer/status?worker=#{worker}"
    statusData     = await statusResponse.json()
    assert.equal statusResponse.status, 200
    assert.ok    statusData.current_session
    assert.ok    statusData.elapsed >= 1

    descResponse = await fetch "#{testConfig.baseUrl}/timer/description",
      method:  'PUT'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify
        worker:      worker
        description: 'Test work session'
    assert.equal descResponse.status, 200

    pauseResponse = await fetch "#{testConfig.baseUrl}/timer/pause",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify { worker }

    pauseData = await pauseResponse.json()
    assert.equal pauseResponse.status, 200
    assert.equal pauseData.status, 'paused'

    resumeResponse = await fetch "#{testConfig.baseUrl}/timer/resume",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify { worker, session_id: sessionId }

    resumeData = await resumeResponse.json()
    assert.equal resumeResponse.status, 200
    assert.equal resumeData.status, 'active'

    stopResponse = await fetch "#{testConfig.baseUrl}/timer/stop",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify
        worker:    worker
        completed: true

    stopData = await stopResponse.json()
    assert.equal stopResponse.status, 200
    assert.ok    stopData.work_log
    assert.ok    stopData.duration >= 1

    logsResponse = await fetch "#{testConfig.baseUrl}/work-logs?worker=#{worker}&limit=1"
    logsData     = await logsResponse.json()
    assert.equal logsResponse.status, 200
    assert.equal logsData.length, 1
    assert.equal logsData[0].description, 'Test work session'


  it 'should handle cancellation without creating work log', ->
    worker = 'lyndzie'

    startResponse = await fetch "#{testConfig.baseUrl}/timer/start",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify { worker }
    assert.equal startResponse.status, 200

    await new Promise (resolve) -> setTimeout resolve, 100

    stopResponse = await fetch "#{testConfig.baseUrl}/timer/stop",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify
        worker:    worker
        completed: false

    stopData = await stopResponse.json()
    assert.equal stopResponse.status, 200
    assert.equal stopData.event, 'cancelled'
    assert.equal stopData.work_log, undefined


  it 'should handle sessions under minimum duration', ->
    worker = 'robert'

    startResponse = await fetch "#{testConfig.baseUrl}/timer/start",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify { worker }
    assert.equal startResponse.status, 200

    stopResponse = await fetch "#{testConfig.baseUrl}/timer/stop",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify
        worker:    worker
        completed: true

    stopData = await stopResponse.json()
    assert.equal stopResponse.status, 200
    assert.equal stopData.event, 'completed_too_short'
    assert.equal stopData.work_log, undefined
