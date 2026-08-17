# Regression test for bug 06 — a created work log must credit the month's
# rent. Before the fix, work logging wrote only to the legacy tables and the
# event-sourced dashboard never heard about it, so hours_worked stayed 0.

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
fs                              = require 'fs'
path                            = require 'path'
{ execSync }                    = require 'child_process'
{ waitForServer }               = require '../helper.coffee'
{ findFreePort, shutdownServer }= require '../server.coffee'


TEST_TMP_DIR = '/tmp/rent-coordinator-tests'
BASE_PORT    = 4100
testConfig   = null


prepareTestDirectory = ->
  if fs.existsSync TEST_TMP_DIR
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true
  fs.mkdirSync TEST_TMP_DIR, recursive: true

cleanupTestDirectory = ->
  try
    if fs.existsSync TEST_TMP_DIR
      fs.rmSync TEST_TMP_DIR, recursive: true, force: true


describe 'Work log credits rent (bug 06)', ->
  before ->
    prepareTestDirectory()

    port    = findFreePort BASE_PORT
    dbPath  = path.join TEST_TMP_DIR, "test-workcredit-#{port}.db"
    logPath = path.join TEST_TMP_DIR, "workcredit-#{port}.log"
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


  it "a tenant work log credits the month and emits one work-reported event", ->
    # 5 hours in a past month keeps the assertion deterministic — no
    # current-month display mask to reason about.
    body =
      worker:      'lyndzie'
      start_time:  '2026-07-10T10:00:00Z'
      end_time:    '2026-07-10T15:00:00Z'
      duration:    300            # minutes
      description: 'Yard work'
      billable:    true

    postRes = await fetch "#{testConfig.baseUrl}/work-logs",
      method:  'POST'
      headers: { 'Content-Type': 'application/json' }
      body:    JSON.stringify body
    assert.equal postRes.status, 200, 'work log created'

    periodRes = await fetch "#{testConfig.baseUrl}/rent/period/2026/7"
    assert.equal periodRes.status, 200
    period = await periodRes.json()

    assert.equal period.hours_worked,          5,    'hours credited'
    assert.equal period.discount_applied,      250,  '5h × $50'
    assert.equal period.amount_due_calculated, 1350, '$1600 − $250'

    eventsRes = await fetch "#{testConfig.baseUrl}/rent/events?year=2026&month=7"
    events    = await eventsRes.json()
    reported  = events.filter (e) -> e.action is 'work-reported'

    assert.equal reported.length,           1,        'exactly one event'
    assert.equal reported[0].actor,         'tenant', 'lyndzie is the tenant'
    assert.equal reported[0].payload.hours, 5


  it "a landlord (robert) work log does not credit rent", ->
    body =
      worker:      'robert'
      start_time:  '2026-07-12T10:00:00Z'
      end_time:    '2026-07-12T12:00:00Z'
      duration:    120
      description: 'Fixed the sink'
      billable:    true

    postRes = await fetch "#{testConfig.baseUrl}/work-logs",
      method:  'POST'
      headers: { 'Content-Type': 'application/json' }
      body:    JSON.stringify body
    assert.equal postRes.status, 200

    periodRes = await fetch "#{testConfig.baseUrl}/rent/period/2026/7"
    period    = await periodRes.json()

    # Still only Lyndzie's 5 hours credit — Robert's 2 don't move the math.
    assert.equal period.hours_worked,     5
    assert.equal period.discount_applied, 250
