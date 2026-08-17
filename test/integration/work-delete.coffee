# Regression test for bug 08 — DELETE /work-logs/:id used to 500 because the
# model had no deleteWorkLog. Now it deletes the row AND retracts the rent
# credit (a `deleted` event targeting the work-reported event).

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
fs                              = require 'fs'
path                            = require 'path'
{ execSync }                    = require 'child_process'
{ waitForServer }               = require '../helper.coffee'
{ findFreePort, shutdownServer }= require '../server.coffee'


TEST_TMP_DIR = '/tmp/rent-coordinator-tests'
BASE_PORT    = 4200
testConfig   = null


prepareTestDirectory = ->
  if fs.existsSync TEST_TMP_DIR
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true
  fs.mkdirSync TEST_TMP_DIR, recursive: true

cleanupTestDirectory = ->
  try
    if fs.existsSync TEST_TMP_DIR
      fs.rmSync TEST_TMP_DIR, recursive: true, force: true


postLog = (baseUrl) ->
  res = await fetch "#{baseUrl}/work-logs",
    method:  'POST'
    headers: { 'Content-Type': 'application/json' }
    body:    JSON.stringify
      worker:      'lyndzie'
      start_time:  '2026-07-10T10:00:00Z'
      end_time:    '2026-07-10T15:00:00Z'
      duration:    300
      description: 'Yard work'
      billable:    true
  await res.json()

getPeriod = (baseUrl) ->
  res = await fetch "#{baseUrl}/rent/period/2026/7"
  await res.json()


describe 'Delete work log retracts credit (bug 08)', ->
  before ->
    prepareTestDirectory()

    port    = findFreePort BASE_PORT
    dbPath  = path.join TEST_TMP_DIR, "test-workdelete-#{port}.db"
    logPath = path.join TEST_TMP_DIR, "workdelete-#{port}.log"
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


  it "deletes the log and backs the hours out of the rent", ->
    { baseUrl } = testConfig

    log = await postLog baseUrl
    assert.ok log.id, 'log created'

    credited = await getPeriod baseUrl
    assert.equal credited.discount_applied, 250, 'credited before delete'

    delRes = await fetch "#{baseUrl}/work-logs/#{log.id}", method: 'DELETE'
    assert.equal delRes.status, 200, 'delete succeeds (was 500 before fix)'
    assert.deepEqual (await delRes.json()), { success: true, deleted: log.id }

    after = await getPeriod baseUrl
    assert.equal after.hours_worked,          0,    'hours retracted'
    assert.equal after.discount_applied,      0,    'credit retracted'
    assert.equal after.amount_due_calculated, 1600, 'back to full rent'


  it "a second delete of the same id 404s and does not retract twice", ->
    { baseUrl } = testConfig

    log = await postLog baseUrl
    firstDel = await fetch "#{baseUrl}/work-logs/#{log.id}", method: 'DELETE'
    assert.equal firstDel.status, 200

    secondDel = await fetch "#{baseUrl}/work-logs/#{log.id}", method: 'DELETE'
    assert.equal secondDel.status, 404, 'already gone'

    after = await getPeriod baseUrl
    assert.equal after.discount_applied, 0, 'still zero, no double retract'
