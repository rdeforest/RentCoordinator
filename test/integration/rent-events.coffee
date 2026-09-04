# Regression test for bug 17 — the Rent Events table was always empty because
# GET /rent/events returned the folded event shape (action/payload/occurred_at)
# but the client filters/renders on the flat legacy shape (type/amount/year/…).
# The route now projects events onto that flat shape.

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
fs                              = require 'fs'
path                            = require 'path'
{ execSync }                    = require 'child_process'
{ waitForServer }               = require '../helper.coffee'
{ findFreePort, shutdownServer }= require '../server.coffee'


TEST_TMP_DIR = '/tmp/rent-coordinator-tests'
BASE_PORT    = 4400
testConfig   = null

# The exact guard the client applies before rendering a row
# (static/coffee/rent.coffee). An event only shows if it passes.
clientShows = (e) ->
  e.type? and e.date? and e.year? and e.month? and e.amount? and e.description? and e.id?

post = (p, body) ->
  res = await fetch "#{testConfig.baseUrl}#{p}",
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify body
  res

put = (p, body) ->
  await fetch "#{testConfig.baseUrl}#{p}",
    method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify body

getEvents = ->
  res = await fetch "#{testConfig.baseUrl}/rent/events"
  await res.json()


describe 'Rent events table renders (bug 17)', ->
  before ->
    if fs.existsSync TEST_TMP_DIR then fs.rmSync TEST_TMP_DIR, recursive: true, force: true
    fs.mkdirSync TEST_TMP_DIR, recursive: true

    port    = findFreePort BASE_PORT
    dbPath  = path.join TEST_TMP_DIR, "test-events-#{port}.db"
    logPath = path.join TEST_TMP_DIR, "events-#{port}.log"
    baseUrl = "http://localhost:#{port}"

    execSync "PORT=#{port} DB_PATH=#{dbPath} NODE_ENV=test coffee main.coffee > #{logPath} 2>&1 &",
      stdio: 'ignore', shell: true

    await new Promise (resolve) -> setTimeout resolve, 1000
    await waitForServer "#{baseUrl}/health"
    testConfig = { port, dbPath, baseUrl, logPath }

  after ->
    await shutdownServer testConfig.baseUrl if testConfig
    if fs.existsSync TEST_TMP_DIR then fs.rmSync TEST_TMP_DIR, recursive: true, force: true


  it "a payment event shows with the flat fields the table needs", ->
    r = await post '/rent/payment', { year: 2026, month: 5, amount: 950, notes: 'May rent' }
    assert.equal r.status, 200

    events  = await getEvents()
    visible = events.filter clientShows
    assert.equal visible.length, 1, 'exactly the payment is renderable'

    p = visible[0]
    assert.equal p.type,        'payment'
    assert.equal p.amount,      950
    assert.equal p.year,        2026
    assert.equal p.month,       5
    assert.equal p.description, 'May rent'
    assert.ok p.date and p.id, 'date and id present'


  it "an override shows as an adjustment; a work log stays hidden", ->
    await put  '/rent/period/2026/5', { amount_due: 1234 }
    await post '/work-logs',
      worker: 'lyndzie', start_time: '2026-05-10T10:00:00Z', end_time: '2026-05-10T15:00:00Z'
      duration: 300, description: 'Yard work', billable: true

    visible = (await getEvents()).filter clientShows
    types   = visible.map (e) -> e.type

    assert.ok 'adjustment' in types, 'override shows as adjustment'
    adj = visible.find (e) -> e.type is 'adjustment'
    assert.equal adj.amount, 1234
    # work-reported has no currency amount → filtered out, as before.
    assert.equal (visible.filter (e) -> e.type is 'work-reported').length, 0
    assert.equal visible.length, 2, 'payment + adjustment only'
