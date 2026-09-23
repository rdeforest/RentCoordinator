{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
{ startTestServer, stopTestServer, DEFAULT_TEST_PORT, authenticatedClient } = require '../server.coffee'


serverConfig = null


# Every request carries the session. requireAuth no longer has a NODE_ENV
# bypass (bug 23), so these routes need one.
api = (path, options = {}) ->
  fetch "#{serverConfig.baseUrl}#{path}", Object.assign {}, options,
    headers: Object.assign {}, (options.headers ? {}), { Cookie: serverConfig.cookie }


describe 'Timer Start', ->
  before ->
    serverConfig = await startTestServer()
    serverConfig.cookie = (await authenticatedClient serverConfig.baseUrl, serverConfig.dbPath).cookie
    console.log "Test server started on port #{serverConfig.port}"

  after ->
    await stopTestServer serverConfig


  it 'should start a timer for robert', ->
    console.log '\n=== Testing /timer/start ==='

    response = await api "/timer/start",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify { worker: 'robert' }

    console.log "Response status: #{response.status}"

    if response.status isnt 200
      errorText = await response.text()
      console.log "Error response: #{errorText}"

    assert.equal response.status, 200, "Expected 200 but got #{response.status}"

    data = await response.json()
    console.log "Response data:", JSON.stringify data, null, 2

    assert.ok    data.id
    assert.equal data.worker, 'robert'
    assert.equal data.status, 'active'
    assert.equal data.event, 'started'

    console.log '✓ Timer started successfully'


  it 'should start a timer for lyndzie', ->
    console.log '\n=== Testing /timer/start for lyndzie ==='

    response = await api "/timer/start",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify { worker: 'lyndzie' }

    data = await response.json()

    assert.equal response.status, 200
    assert.ok    data.id
    assert.equal data.worker, 'lyndzie'
    assert.equal data.status, 'active'

    console.log '✓ Timer started for lyndzie'
