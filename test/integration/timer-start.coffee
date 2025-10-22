# test/integration/timer-start.coffee
# Focused test for timer start functionality

{ describe, it, before, after } = require 'node:test'
assert = require 'node:assert/strict'
{ startTestServer, stopTestServer, forceExit, DEFAULT_TEST_PORT } = require '../server.coffee'

BASE_URL = "http://localhost:#{DEFAULT_TEST_PORT}"
serverConfig = null

describe 'Timer Start', ->
  before ->
    serverConfig = await startTestServer()
    console.log "Test server started on port #{serverConfig.port}"

  after ->
    await stopTestServer(serverConfig)
    forceExit()

  it 'should start a timer for robert', ->
    console.log '\n=== Testing /timer/start ==='

    response = await fetch "#{BASE_URL}/timer/start",
      method: 'POST'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify { worker: 'robert' }

    console.log "Response status: #{response.status}"

    if response.status isnt 200
      errorText = await response.text()
      console.log "Error response: #{errorText}"

    assert.equal response.status, 200, "Expected 200 but got #{response.status}"

    data = await response.json()
    console.log "Response data:", JSON.stringify(data, null, 2)

    assert.ok data.id, 'Should return session ID'
    assert.equal data.worker, 'robert'
    assert.equal data.status, 'active'
    assert.equal data.event, 'started'

    console.log '✓ Timer started successfully'

  it 'should start a timer for lyndzie', ->
    console.log '\n=== Testing /timer/start for lyndzie ==='

    response = await fetch "#{BASE_URL}/timer/start",
      method: 'POST'
      headers: 'Content-Type': 'application/json'
      body: JSON.stringify { worker: 'lyndzie' }

    assert.equal response.status, 200

    data = await response.json()
    assert.ok data.id
    assert.equal data.worker, 'lyndzie'
    assert.equal data.status, 'active'

    console.log '✓ Timer started for lyndzie'
