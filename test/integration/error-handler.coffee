# Bug 21 — the real error handler, mounted last, against a real server.
#
# test/services/middleware.coffee already proves the *mechanism* (a handler
# registered after routes catches errors; one registered before them does
# not) with a hand-built express app. What that can't prove is that
# main.coffee actually wires it up that way — deleting the
# `middleware.setupErrorHandler app` line from main.coffee is a real
# regression these tests exist to catch, and no unit test touches main.coffee
# at all.

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
fs                              = require 'fs'
path                            = require 'path'
{ execSync }                    = require 'child_process'
{ waitForServer }               = require '../helper.coffee'
{ findFreePort, shutdownServer } = require '../server.coffee'


TEST_TMP_DIR = '/tmp/rent-coordinator-tests'
BASE_PORT    = 5100
testConfig   = null


describe 'The real error handler (bug 21)', ->
  before ->
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true if fs.existsSync TEST_TMP_DIR
    fs.mkdirSync TEST_TMP_DIR, recursive: true

    port   = findFreePort BASE_PORT
    dbPath = path.join TEST_TMP_DIR, "error-handler-#{port}.db"
    log    = path.join TEST_TMP_DIR, "error-handler-#{port}.log"

    execSync "PORT=#{port} DB_PATH=#{dbPath} NODE_ENV=test coffee main.coffee > #{log} 2>&1 &",
      stdio: 'ignore', shell: true
    await new Promise (resolve) -> setTimeout resolve, 1000
    await waitForServer "http://localhost:#{port}/health"

    testConfig = { baseUrl: "http://localhost:#{port}", dbPath }

  after ->
    await shutdownServer testConfig.baseUrl if testConfig
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true


  it 'answers malformed JSON with 400 JSON, not an HTML stack trace', ->
    response = await fetch "#{testConfig.baseUrl}/auth/send-code",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    '{'

    assert.equal response.status, 400
    assert.match response.headers.get('content-type'), /json/,
      'a handler registered before the routes (the bug) falls through to Express\'s own HTML page'

    body = await response.json()
    assert.ok body.error, 'the body must carry an error field'


  it 'answers an uncaught route error with a sanitized 500, not the internal message', ->
    response = await fetch "#{testConfig.baseUrl}/v1/throw"

    assert.equal response.status, 500
    assert.match response.headers.get('content-type'), /json/

    body = await response.json()
    assert.deepEqual Object.keys(body).sort(), ['error'],
      'outside development, only error should be present — no internal message field'
    assert.equal body.error, 'Internal server error',
      'the real exception message must not reach the client outside development'
