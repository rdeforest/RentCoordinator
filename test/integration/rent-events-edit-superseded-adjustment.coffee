# Bug 66 (item 2 in docs/bugs/66-amount-paid-override-and-edits.md) —
# editing an adjustment that a later amount_due override has already
# superseded used to return 200 and change nothing: the edit keeps the
# adjustment's original occurred_at, so it stays before the pin however its
# amount changes. PUT /rent/events/:id now refuses (400) instead.

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
fs                              = require 'fs'
path                            = require 'path'
{ execSync }                    = require 'child_process'
{ waitForServer }               = require '../helper.coffee'
{ findFreePort, shutdownServer, authenticatedClient } = require '../server.coffee'

TEST_TMP_DIR = '/tmp/rent-coordinator-tests'
BASE_PORT    = 5110
testConfig   = null


describe 'Editing an adjustment superseded by a later amount_due override', ->
  before ->
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true if fs.existsSync TEST_TMP_DIR
    fs.mkdirSync TEST_TMP_DIR, recursive: true

    port    = findFreePort BASE_PORT
    dbPath  = path.join TEST_TMP_DIR, "adj-superseded-#{port}.db"
    logPath = path.join TEST_TMP_DIR, "adj-superseded-#{port}.log"
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


  it 'refuses the edit with a 400 naming the override, and leaves the event unchanged', ->
    createRes = await testConfig.client.post '/rent/events',
      type:        'adjustment'
      year:        2026
      month:       9
      amount:      100
      description: 'Late fee'
    assert.equal createRes.status, 200
    event = await createRes.json()

    # Pin the month after the adjustment was recorded — the adjustment is
    # now superseded by the pin (bug 56's rule).
    pinRes = await testConfig.client.put '/rent/period/2026/9', amount_due: 500
    assert.equal pinRes.status, 200

    before = await (await testConfig.client.get '/rent/period/2026/9').json()
    assert.equal before.amount_due, 500, 'the pin wins; the earlier adjustment is superseded'

    editRes  = await testConfig.client.put "/rent/events/#{event.id}", { amount: 250 }
    assert.equal editRes.status, 400
    body = await editRes.json()
    assert.match body.error, /superseded/i
    assert.match body.error, /amount_due override/i

    after = await (await testConfig.client.get '/rent/period/2026/9').json()
    assert.equal after.amount_due, 500, 'the refused edit must not move the pinned amount'

    unchanged = await (await testConfig.client.get "/rent/events/#{event.id}").json()
    assert.equal unchanged.payload.delta, 100, 'the original adjustment amount is untouched'
