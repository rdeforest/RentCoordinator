# Test gap — PUT /rent/events/:id edits an adjustment's amount, and the
# period's amount_due must move with it.
#
# The route (lib/routes/rent.coffee ~395-406) picks which payload key to
# write based on the target event's action (AMOUNT_FIELD: payment-made →
# amount, adjustment → delta, override → new_value) rather than writing
# `amount` unconditionally onto every edit. Nothing exercised that an edit
# to an adjustment specifically reaches the fold and changes amount_due —
# this closes that gap.

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
fs                              = require 'fs'
path                            = require 'path'
{ execSync }                    = require 'child_process'
{ waitForServer }               = require '../helper.coffee'
{ findFreePort, shutdownServer, authenticatedClient } = require '../server.coffee'

TEST_TMP_DIR = require('../server.coffee').TEST_TMP_DIR
BASE_PORT    = 4940
testConfig   = null


describe "Editing an adjustment's amount moves the period's amount_due", ->
  before ->
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true if fs.existsSync TEST_TMP_DIR
    fs.mkdirSync TEST_TMP_DIR, recursive: true

    port    = findFreePort BASE_PORT
    dbPath  = path.join TEST_TMP_DIR, "adj-edit-#{port}.db"
    logPath = path.join TEST_TMP_DIR, "adj-edit-#{port}.log"
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


  it "an edit to an adjustment's amount changes amount_due, not amount_paid or nothing", ->
    createRes = await testConfig.client.post '/rent/events',
      type:        'adjustment'
      year:        2026
      month:       9
      amount:      100
      description: 'Late fee'
    assert.equal createRes.status, 200
    event = await createRes.json()

    before = await (await testConfig.client.get '/rent/period/2026/9').json()
    assert.equal before.amount_due, 1700, '$1600 base + $100 adjustment'

    editRes = await testConfig.client.put "/rent/events/#{event.id}", { amount: 250 }
    assert.equal editRes.status, 200

    after = await (await testConfig.client.get '/rent/period/2026/9').json()
    assert.equal after.amount_due, 1850, 'the edited $250 delta replaces the original $100'
