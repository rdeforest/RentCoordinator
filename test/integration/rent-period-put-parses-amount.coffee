# Bug 57 (second half) — PUT /rent/period/:year/:month wrote req.body's
# amount_due/amount_paid straight into the override event's payload.
# buildEventPayload (used by POST /rent/events) always parseFloats the
# incoming amount; this path didn't, so a string value — which is what a
# plain HTML form field or a JSON-string-typed client sends — failed
# validateAmounts' typeof check every time, even for a perfectly sensible
# number like "1200".

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
fs                              = require 'fs'
path                            = require 'path'
{ execSync }                    = require 'child_process'
{ waitForServer }               = require '../helper.coffee'
{ findFreePort, shutdownServer, authenticatedClient } = require '../server.coffee'

TEST_TMP_DIR = '/tmp/rent-coordinator-tests'
BASE_PORT    = 4960
testConfig   = null


describe 'PUT /rent/period parses amount_due/amount_paid like buildEventPayload (bug 57)', ->
  before ->
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true if fs.existsSync TEST_TMP_DIR
    fs.mkdirSync TEST_TMP_DIR, recursive: true

    port    = findFreePort BASE_PORT
    dbPath  = path.join TEST_TMP_DIR, "period-put-#{port}.db"
    logPath = path.join TEST_TMP_DIR, "period-put-#{port}.log"
    baseUrl = "http://localhost:#{port}"

    execSync "PORT=#{port} DB_PATH=#{dbPath} NODE_ENV=test coffee main.coffee > #{logPath} 2>&1 &",
      stdio: 'ignore', shell: true

    await new Promise (resolve) -> setTimeout resolve, 1000
    await waitForServer "#{baseUrl}/health"
    testConfig = { port, dbPath, baseUrl, logPath }
    testConfig.client = await authenticatedClient baseUrl, dbPath

  after ->
    await shutdownServer testConfig.baseUrl if testConfig
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true if fs.existsSync TEST_TMP_DIR


  it "a string-typed amount_due is parsed, not rejected as non-numeric", ->
    r = await testConfig.client.put '/rent/period/2026/8', { amount_due: '1234.50' }
    assert.equal r.status, 200, "a string amount that parses cleanly must be accepted"

    body = await r.json()
    assert.equal body.amount_due, 1234.5
