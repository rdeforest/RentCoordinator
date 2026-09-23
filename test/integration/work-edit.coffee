# Bug 49 — editing a work log did not move the rent credit.
#
# `updateWorkLog` wrote the row and emitted nothing, so the work-reported event
# still carried the original hours. The legacy `createOrUpdateRentPeriod` call
# in the route papered over it for the old model; the dashboard reads the fold.

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
fs                              = require 'fs'
path                            = require 'path'
{ execSync }                    = require 'child_process'
{ waitForServer }               = require '../helper.coffee'
{ findFreePort, shutdownServer }= require '../server.coffee'

TEST_TMP_DIR = '/tmp/rent-coordinator-tests'
BASE_PORT    = 4900
testConfig   = null

req = (method, p, body) ->
  options = method: method, headers: 'Content-Type': 'application/json'
  options.body = JSON.stringify body if body
  fetch "#{testConfig.baseUrl}#{p}", options

get  = (p)    -> (await req 'GET',  p).json()
post = (p, b) ->  req 'POST', p, b
put  = (p, b) ->  req 'PUT',  p, b

creditFor = (year, month) -> (await get "/rent/period/#{year}/#{month}").discount_applied
hoursFor  = (year, month) -> (await get "/rent/period/#{year}/#{month}").hours_worked

logWork = (body) -> (await post '/work-logs', body).json()


describe 'Editing a work log moves the rent credit (bug 49)', ->
  before ->
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true if fs.existsSync TEST_TMP_DIR
    fs.mkdirSync TEST_TMP_DIR, recursive: true

    port = findFreePort BASE_PORT
    db   = path.join TEST_TMP_DIR, "work-edit-#{port}.db"
    log  = path.join TEST_TMP_DIR, "work-edit-#{port}.log"

    execSync "PORT=#{port} DB_PATH=#{db} NODE_ENV=test coffee main.coffee > #{log} 2>&1 &",
      stdio: 'ignore', shell: true
    await new Promise (resolve) -> setTimeout resolve, 1000
    await waitForServer "http://localhost:#{port}/health"
    testConfig = { baseUrl: "http://localhost:#{port}" }

  after ->
    await shutdownServer testConfig.baseUrl if testConfig
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true


  it 'a corrected duration changes the credit', ->
    entry = await logWork
      worker: 'lyndzie', start_time: '2026-02-10T09:00:00Z', end_time: '2026-02-10T11:00:00Z'
      duration: 120, description: 'Yard work', billable: true

    assert.equal await hoursFor(2026, 2),  2,   'two hours logged'
    assert.equal await creditFor(2026, 2), 100, 'at $50/hour'

    # Recorded 2 hours, actually worked 5.
    response = await put "/work-logs/#{entry.id}",
      { start_time: '2026-02-10T09:00:00Z', end_time: '2026-02-10T14:00:00Z', duration: 300 }
    assert.equal response.status, 200

    assert.equal await hoursFor(2026, 2),  5,   'the correction has to reach the fold'
    assert.equal await creditFor(2026, 2), 250, 'and the credit with it'


  it 'does not double-count the original hours', ->
    hours = await hoursFor 2026, 2
    assert.equal hours, 5, "expected the corrected figure, not 2 + 5 (got #{hours})"


  it 'a corrected date moves the credit to the right month', ->
    entry = await logWork
      worker: 'lyndzie', start_time: '2026-04-05T09:00:00Z', end_time: '2026-04-05T12:00:00Z'
      duration: 180, description: 'Filed under the wrong month', billable: true

    assert.equal await hoursFor(2026, 4), 3
    assert.equal await hoursFor(2026, 5), 0

    await put "/work-logs/#{entry.id}",
      { start_time: '2026-05-05T09:00:00Z', end_time: '2026-05-05T12:00:00Z', duration: 180 }

    assert.equal await hoursFor(2026, 4), 0, 'April gives the hours up'
    assert.equal await hoursFor(2026, 5), 3, 'and May takes them'


  it 'reassigning work to the landlord stops it crediting rent', ->
    entry = await logWork
      worker: 'lyndzie', start_time: '2026-06-05T09:00:00Z', end_time: '2026-06-05T13:00:00Z'
      duration: 240, description: 'Actually robert did this', billable: true

    assert.equal await hoursFor(2026, 6), 4

    await put "/work-logs/#{entry.id}", { worker: 'robert' }

    assert.equal await hoursFor(2026, 6), 0,
      'only the tenant\'s work credits rent, and the edit has to say so'


  it 'an edit that changes nothing measurable leaves the credit alone', ->
    entry = await logWork
      worker: 'lyndzie', start_time: '2026-07-05T09:00:00Z', end_time: '2026-07-05T11:00:00Z'
      duration: 120, description: 'Before', billable: true

    await put "/work-logs/#{entry.id}", { description: 'After' }

    assert.equal await hoursFor(2026, 7),  2
    assert.equal await creditFor(2026, 7), 100
