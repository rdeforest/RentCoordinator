# Contract smoke test for the rent dashboard. The $NaN (bug 19) and empty
# events table (bug 17) were client/server field drift: the server response
# didn't carry what the client reads. This asserts the endpoints the dashboard
# consumes provide every field it uses, and that currency values are finite
# (formatCurrency of a non-finite value is what produced "$NaN").
#
# Boundary: this checks the server side of the contract, not the actual DOM
# render — a client-side typo would need a browser (Playwright) to catch;
# the formatCurrency canary + beacon cover that at runtime instead.

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
fs                              = require 'fs'
path                            = require 'path'
{ execSync }                    = require 'child_process'
{ waitForServer }               = require '../helper.coffee'
{ findFreePort, shutdownServer }= require '../server.coffee'


TEST_TMP_DIR = '/tmp/rent-coordinator-tests'
BASE_PORT    = 4500
testConfig   = null

# Fields the client reads (static/coffee/rent.coffee). Keep in sync with it.
# `money` fields go through formatCurrency and must be finite; `num` fields
# go through toFixed and must be numbers.
SUMMARY = { money: ['outstanding_balance', 'total_discount', 'total_amount_paid'], num: ['total_periods'] }
PERIOD  =
  money: ['display_amount_due', 'discount_applied', 'amount_paid', 'amount_due']
  num:   ['hours_worked', 'hours_from_previous', 'effective_agreed_payment']

finite = (v) -> typeof v is 'number' and Number.isFinite v
clientShows = (e) -> e.type? and e.date? and e.year? and e.month? and e.amount? and e.description? and e.id?

get  = (p) -> (await fetch "#{testConfig.baseUrl}#{p}").json()
post = (p, b) -> fetch "#{testConfig.baseUrl}#{p}", method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(b)


describe 'Rent dashboard data contract (bugs 17/19)', ->
  before ->
    if fs.existsSync TEST_TMP_DIR then fs.rmSync TEST_TMP_DIR, recursive: true, force: true
    fs.mkdirSync TEST_TMP_DIR, recursive: true
    port    = findFreePort BASE_PORT
    dbPath  = path.join TEST_TMP_DIR, "test-contract-#{port}.db"
    baseUrl = "http://localhost:#{port}"
    execSync "PORT=#{port} DB_PATH=#{dbPath} NODE_ENV=test coffee main.coffee > #{path.join TEST_TMP_DIR, "contract-#{port}.log"} 2>&1 &",
      stdio: 'ignore', shell: true
    await new Promise (resolve) -> setTimeout resolve, 1000
    await waitForServer "#{baseUrl}/health"
    testConfig = { baseUrl }

    # Seed real activity: a tenant work log + a payment for a past month.
    await post '/work-logs',
      worker: 'lyndzie', start_time: '2026-07-10T10:00:00Z', end_time: '2026-07-10T15:00:00Z'
      duration: 300, description: 'Yard work', billable: true
    await post '/rent/payment', { year: 2026, month: 7, amount: 950, notes: 'July' }

  after ->
    await shutdownServer testConfig.baseUrl if testConfig
    if fs.existsSync TEST_TMP_DIR then fs.rmSync TEST_TMP_DIR, recursive: true, force: true


  it "/rent/summary carries every field the client reads, currencies finite", ->
    s = await get '/rent/summary'
    for f in SUMMARY.money
      assert.ok finite(s[f]), "summary.#{f} must be a finite number (was #{s[f]})"
    for f in SUMMARY.num
      assert.equal typeof(s[f]), 'number', "summary.#{f} must be a number"

  it "/rent/period carries every field the client reads, currencies finite", ->
    p = await get '/rent/period/2026/7'
    for f in PERIOD.money
      assert.ok finite(p[f]), "period.#{f} must be a finite number (was #{p[f]})"
    for f in PERIOD.num
      assert.ok finite(p[f]), "period.#{f} must be a finite number (was #{p[f]})"

  it "/rent/events financial rows are renderable with finite amounts", ->
    visible = (await get '/rent/events').filter clientShows
    assert.ok visible.length >= 1, 'at least the payment renders'
    for e in visible
      assert.ok finite(e.amount), "event #{e.type} amount must be finite (was #{e.amount})"

  it "client-error beacon endpoint accepts a report", ->
    res = await post '/client-errors', { kind: 'test', message: 'hello', url: '/rent' }
    assert.equal res.status, 200
    assert.deepEqual (await res.json()), { ok: true }
