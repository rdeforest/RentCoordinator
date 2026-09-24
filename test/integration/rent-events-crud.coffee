# Bugs 14 / 15 / 16 / 18 / 20 — the rent event write path, end to end.
#
# Each of these was a case where the route accepted input and quietly filed it
# as something else: an adjustment became an absolute pin, an unrecognized
# type became a payment, an undelete became a second delete, a cleared
# override amount became no change at all, and the summary disagreed with the
# rows under it.

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
fs                              = require 'fs'
path                            = require 'path'
{ execSync }                    = require 'child_process'
{ waitForServer }               = require '../helper.coffee'
{ findFreePort, shutdownServer, authenticatedClient } = require '../server.coffee'


TEST_TMP_DIR = '/tmp/rent-coordinator-tests'
BASE_PORT    = 4700
PAST         = { year: 2026, month: 3 }
testConfig   = null

# One funnel, one session: requireAuth no longer has a NODE_ENV bypass (bug 23).
req = (method, p, body) -> testConfig.client.request method, p, body

get    = (p)    -> (await req 'GET',    p).json()
post   = (p, b) ->  req 'POST',   p, b
put    = (p, b) ->  req 'PUT',    p, b
del    = (p, b) ->  req 'DELETE', p, b

periodOf = (y, m) -> get "/rent/period/#{y}/#{m}"


describe 'Rent event write path (bugs 14/15/16/18/20)', ->
  before ->
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true if fs.existsSync TEST_TMP_DIR
    fs.mkdirSync TEST_TMP_DIR, recursive: true

    port   = findFreePort BASE_PORT
    dbPath = path.join TEST_TMP_DIR, "test-events-crud-#{port}.db"
    log    = path.join TEST_TMP_DIR, "events-crud-#{port}.log"

    execSync "PORT=#{port} DB_PATH=#{dbPath} NODE_ENV=test coffee main.coffee > #{log} 2>&1 &",
      stdio: 'ignore', shell: true

    await new Promise (resolve) -> setTimeout resolve, 1000
    await waitForServer "http://localhost:#{port}/health"
    baseUrl = "http://localhost:#{port}"
    testConfig = { baseUrl, client: (await authenticatedClient baseUrl, dbPath), dbPath }

    # One past month with no work, so its calculated amount is the full base
    # rent and every assertion below is against a known number.
    await post '/rent/payment', { PAST..., amount: 0, notes: 'seed the month' }

  after ->
    await shutdownServer testConfig.baseUrl if testConfig
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true


  it 'an adjustment adds to the amount due (bug 14)', ->
    before = (await periodOf PAST.year, PAST.month).amount_due

    response = await post '/rent/events',
      { PAST..., type: 'adjustment', amount: 100, description: 'Late fee' }
    assert.equal response.status, 200

    after = await periodOf PAST.year, PAST.month
    assert.equal after.amount_due, before + 100,
      'a $100 late fee should add $100, not replace the month with $100'
    assert.equal after.amount_due_manual, 0,
      'and must not mark the month as manually pinned'


  it 'a non-numeric amount is a 400, not a 500 (bug 57)', ->
    response = await post '/rent/events',
      { PAST..., type: 'adjustment', amount: 'abc', description: 'Typo' }
    assert.equal response.status, 400
    assert.match (await response.json()).error, /finite number/


  it 'a manual entry still pins the amount due absolutely', ->
    await post '/rent/events',
      { year: 2026, month: 4, type: 'manual', amount: 42, description: 'Pinned' }

    period = await periodOf 2026, 4
    assert.equal period.amount_due,        42
    assert.equal period.amount_due_manual, 1


  it 'an unknown event type is rejected, not filed as a payment (bug 15)', ->
    before = (await periodOf 2026, 5).amount_paid

    response = await post '/rent/events',
      { year: 2026, month: 5, type: 'work_value_change', amount: 200, description: 'Rate change' }

    assert.equal response.status, 400, 'an unhandled type must be a client error'
    body = await response.json()
    assert.match body.error, /unknown event type/i
    assert.ok 'payment' in body.known, 'and the error should say what is accepted'

    assert.equal (await periodOf 2026, 5).amount_paid, before,
      'nothing should have been recorded as paid'


  it 'undelete restores an event to the ledger and the list (bug 16)', ->
    await post '/rent/payment', { year: 2026, month: 6, amount: 400, notes: 'June' }

    events  = await get '/rent/events?year=2026&month=6'
    payment = events.find (e) -> e.type is 'payment'
    assert.ok payment, 'the payment should be listed'
    assert.equal (await periodOf 2026, 6).amount_paid, 400

    await del "/rent/events/#{payment.id}"
    assert.equal (await periodOf 2026, 6).amount_paid, 0, 'deleted, so it stops counting'

    undelete = await post "/rent/events/#{payment.id}/undelete"
    assert.equal undelete.status, 200

    assert.equal (await periodOf 2026, 6).amount_paid, 400,
      'the undelete must put the payment back — previously a silent no-op'

    restored = (await get '/rent/events?year=2026&month=6').find (e) -> e.id is payment.id
    assert.ok restored, 'and it should be listed again'
    assert.equal restored.deleted, false,
      'no longer flagged deleted — the list used to disagree with the ledger'


  it 'undeleting something that is not deleted is refused', ->
    await post '/rent/payment', { year: 2026, month: 8, amount: 100, notes: 'Aug' }
    live = (await get '/rent/events?year=2026&month=8').find (e) -> e.type is 'payment'

    response = await post "/rent/events/#{live.id}/undelete"
    assert.equal response.status, 400
    assert.match (await response.json()).error, /not deleted/i


  it 'the summary agrees with the rows beneath it (bug 18)', ->
    summary = await get '/rent/summary'

    expectedDue = summary.periods.reduce ((s, p) -> s + p.display_amount_due), 0
    expectedOut = summary.periods.reduce ((s, p) -> s + Math.max 0, p.display_amount_due - p.amount_paid), 0

    assert.equal summary.total_amount_due, expectedDue,
      'total_amount_due must sum the value the rows display, not the raw one'
    assert.equal summary.outstanding_balance, expectedOut,
      'and outstanding must clamp each month at zero'

    outstanding = await get '/rent/outstanding'
    assert.ok Math.abs(outstanding.total_outstanding - summary.outstanding_balance) < 0.01,
      "/rent/summary and /rent/outstanding must not disagree about what is owed
       (#{summary.outstanding_balance} vs #{outstanding.total_outstanding})"


  it 'the current month before the due date contributes nothing to the balance (bug 18)', (t) ->
    now = new Date()

    # After the 15th there is nothing to mask, and the route reads the real
    # clock. Say so rather than reporting a green test that never ran; the
    # deterministic coverage lives in test/services/period.coffee.
    return t.skip "only meaningful before day #{15} of the month" if now.getDate() >= 15

    await post '/rent/payment',
      { year: now.getFullYear(), month: now.getMonth() + 1, amount: 0, notes: 'touch current month' }

    summary = await get '/rent/summary'
    current = summary.periods.find (p) ->
      p.year is now.getFullYear() and p.month is (now.getMonth() + 1)

    assert.ok current, 'the current month should be in the summary'
    assert.equal current.display_amount_due, 0
    assert.ok summary.total_amount_due < 1600 * summary.total_periods,
      'the full base rent must not be counted for a month that is not due yet'


  it 'a cleared temporary rent amount stays cleared (bug 20)', ->
    await put '/rent/configuration', { temporary_rent_amount: 1200, apply_override: true }
    assert.equal (await get '/rent/configuration').temporary_rent_amount, 1200

    await put '/rent/configuration', { temporary_rent_amount: null }
    assert.equal (await get '/rent/configuration').temporary_rent_amount, null,
      'an explicit null means clear it; it used to be discarded as "absent"'

    await put '/rent/configuration', { apply_override: true }
    assert.equal (await get '/rent/configuration').temporary_rent_amount, null,
      're-enabling the override must not resurrect the old amount'


  it 'omitting the field still leaves it alone', ->
    await put '/rent/configuration', { temporary_rent_amount: 1300 }
    await put '/rent/configuration', { apply_override: false }

    assert.equal (await get '/rent/configuration').temporary_rent_amount, 1300,
      'a request that does not mention the amount must not change it'
