# Bug 51 — a payment the landlord enters through POST /rent/events never
# counted. That route stamps actor: 'landlord' (actorFromRequest's fallback),
# and computeMonth in lib/services/period.coffee summed payment-made only
# when actor is 'tenant', so /rent/payment (actor: 'tenant') and
# POST /rent/events (actor: 'landlord') disagreed about the same action.

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
fs                              = require 'fs'
path                            = require 'path'
{ execSync }                    = require 'child_process'
{ waitForServer }               = require '../helper.coffee'
{ findFreePort, shutdownServer, authenticatedClient } = require '../server.coffee'

TEST_TMP_DIR = '/tmp/rent-coordinator-tests'
BASE_PORT    = 4950
testConfig   = null


describe 'A landlord-entered payment counts toward amount_paid (bug 51)', ->
  before ->
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true if fs.existsSync TEST_TMP_DIR
    fs.mkdirSync TEST_TMP_DIR, recursive: true

    port    = findFreePort BASE_PORT
    dbPath  = path.join TEST_TMP_DIR, "landlord-payment-#{port}.db"
    logPath = path.join TEST_TMP_DIR, "landlord-payment-#{port}.log"
    baseUrl = "http://localhost:#{port}"

    execSync "PORT=#{port} DB_PATH=#{dbPath} NODE_ENV=test coffee main.coffee > #{logPath} 2>&1 &",
      stdio: 'ignore', shell: true

    await new Promise (resolve) -> setTimeout resolve, 1000
    await waitForServer "#{baseUrl}/health"
    testConfig = { port, dbPath, baseUrl, logPath }
    # robert@defore.st is the landlord — the default identity for this client.
    testConfig.client = await authenticatedClient baseUrl, dbPath

  after ->
    await shutdownServer testConfig.baseUrl if testConfig
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true if fs.existsSync TEST_TMP_DIR


  it "as the landlord, POST /rent/events type=payment shows up in amount_paid", ->
    r = await testConfig.client.post '/rent/events',
      type:        'payment'
      year:        2026
      month:       5
      amount:      950
      description: 'Rent paid in person'
    assert.equal r.status, 200

    period = await (await testConfig.client.get '/rent/period/2026/5').json()
    assert.equal period.amount_paid, 950, 'the landlord-recorded payment counts'
