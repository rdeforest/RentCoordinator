# Bug 58 — PUT /work-logs/:id accepted duration 0 or '' (`Number ''` is 0,
# and `0?` is true in CoffeeScript, so the presence check let it through) and
# wrote it straight through, zeroing the work-reported event's hours and the
# rent credit with it. POST /work-logs already required at least a minute.
# Both routes now share one validator.

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
fs                              = require 'fs'
path                            = require 'path'
{ execSync }                    = require 'child_process'
{ waitForServer }               = require '../helper.coffee'
{ findFreePort, shutdownServer, authenticatedClient } = require '../server.coffee'

TEST_TMP_DIR = require('../server.coffee').TEST_TMP_DIR
BASE_PORT    = 4980
testConfig   = null


describe "PUT /work-logs rejects a zero or empty duration, same as POST (bug 58)", ->
  before ->
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true if fs.existsSync TEST_TMP_DIR
    fs.mkdirSync TEST_TMP_DIR, recursive: true

    port    = findFreePort BASE_PORT
    dbPath  = path.join TEST_TMP_DIR, "work-duration-#{port}.db"
    logPath = path.join TEST_TMP_DIR, "work-duration-#{port}.log"
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


  it "creates a work log to edit", ->
    r = await testConfig.client.post '/work-logs',
      worker:      'lyndzie'
      start_time:  '2026-04-10T10:00:00Z'
      end_time:    '2026-04-10T12:00:00Z'
      duration:    120
      description: 'Two hours of yard work'
      billable:    true
    assert.equal r.status, 200
    testConfig.logId = (await r.json()).id


  it "rejects duration: 0 on edit", ->
    r = await testConfig.client.put "/work-logs/#{testConfig.logId}", { duration: 0 }
    assert.equal r.status, 400

    period = await (await testConfig.client.get '/rent/period/2026/4').json()
    assert.equal period.hours_worked, 2, 'the original credit must be untouched'


  it "rejects duration: '' on edit", ->
    r = await testConfig.client.put "/work-logs/#{testConfig.logId}", { duration: '' }
    assert.equal r.status, 400

    period = await (await testConfig.client.get '/rent/period/2026/4').json()
    assert.equal period.hours_worked, 2, 'the original credit must still be untouched'


  it "still accepts a legitimate edit", ->
    r = await testConfig.client.put "/work-logs/#{testConfig.logId}", { duration: 180 }
    assert.equal r.status, 200

    period = await (await testConfig.client.get '/rent/period/2026/4').json()
    assert.equal period.hours_worked, 3
