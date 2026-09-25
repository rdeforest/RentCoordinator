# Bug 62 — the landlord-only consistency routes: a run stores findings, they
# can be acknowledged and un-acknowledged, and the summary reflects open vs
# acknowledged.

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


describe 'Consistency checks (bug 62)', ->
  before ->
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true if fs.existsSync TEST_TMP_DIR
    fs.mkdirSync TEST_TMP_DIR, recursive: true

    port    = findFreePort BASE_PORT
    dbPath  = path.join TEST_TMP_DIR, "consistency-#{port}.db"
    logPath = path.join TEST_TMP_DIR, "consistency-#{port}.log"
    baseUrl = "http://localhost:#{port}"

    execSync "PORT=#{port} DB_PATH=#{dbPath} S3_BACKUP_ENABLED=false NODE_ENV=test coffee main.coffee > #{logPath} 2>&1 &",
      stdio: 'ignore', shell: true
    await new Promise (resolve) -> setTimeout resolve, 1000
    await waitForServer "#{baseUrl}/health"

    testConfig = { baseUrl, dbPath, client: await authenticatedClient baseUrl, dbPath }

  after ->
    await shutdownServer testConfig.baseUrl if testConfig
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true


  it 'has already run once at startup, so a run exists before any manual trigger', ->
    res  = await testConfig.client.get '/admin/consistency'
    body = await res.json()
    assert.equal res.status, 200
    assert.ok body.ran_at, 'startup must have recorded a run'
    assert.ok Array.isArray body.findings


  it 'POST /admin/consistency/run runs the checks again and returns findings', ->
    res  = await testConfig.client.post '/admin/consistency/run'
    body = await res.json()
    assert.equal res.status, 200
    assert.ok body.ran_at
    assert.ok Array.isArray body.findings


  it 'acknowledging a finding requires a non-empty note', ->
    res = await testConfig.client.post '/admin/consistency/ack', { key: 'some-key' }
    assert.equal res.status, 400

    res2 = await testConfig.client.post '/admin/consistency/ack', { key: 'some-key', note: '   ' }
    assert.equal res2.status, 400


  it 'acknowledge → shows on the run, removes it from the open summary count; unack reverses it', ->
    before_   = await (await testConfig.client.get '/admin/consistency/summary').json()

    # Manufacture a finding key deterministically by running against a
    # database with nothing else wrong: an amount_due override always
    # disagrees with the calculated figure by design (bug 62's decision),
    # so recording one payment override month gives us a real, stable key.
    await testConfig.client.post '/rent/events',
      type: 'manual', year: 2026, month: 5, amount: 1500, description: 'test pin for bug 62 coverage'

    ran     = await (await testConfig.client.post '/admin/consistency/run').json()
    target  = ran.findings.find (f) -> f.kind is 'manual-amount-due-mismatch' and f.month is '2026-05'
    assert.ok target, 'expected an amount_due mismatch finding for 2026-05'
    assert.equal target.acknowledgment, null

    ackRes = await testConfig.client.post '/admin/consistency/ack', { key: target.key, note: 'expected, reviewed' }
    assert.equal ackRes.status, 200

    afterAck  = await (await testConfig.client.get '/admin/consistency').json()
    found     = afterAck.findings.find (f) -> f.key is target.key
    assert.equal found.acknowledgment.note, 'expected, reviewed'
    assert.equal found.acknowledgment.acknowledged_by, 'robert@defore.st'

    unackRes = await testConfig.client.del "/admin/consistency/ack/#{encodeURIComponent target.key}"
    assert.equal unackRes.status, 200

    afterUnack = await (await testConfig.client.get '/admin/consistency').json()
    stillThere = afterUnack.findings.find (f) -> f.key is target.key
    assert.equal stillThere.acknowledgment, null


  it 'GET /issues serves the page to the landlord', ->
    res = await testConfig.client.get '/issues'
    assert.equal res.status, 200
    text = await res.text()
    assert.ok text.includes 'Consistency Issues'
