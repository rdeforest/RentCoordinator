# Regression tests for bugs 09 and 10.
#
# 09 — a Stripe `payment_intent.succeeded` webhook records the payment
#      (ACH settles days after the client poll gives up).
# 10 — recording is idempotent on the intent id: a replayed webhook (Stripe
#      delivers at-least-once) credits the month once, not twice.
#
# No network: the webhook carries the PaymentIntent object, recording reads
# the allocation from its metadata, and the signature is generated locally
# with Stripe's test helper. Only the HMAC secret has to match.

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
fs                              = require 'fs'
path                            = require 'path'
{ execSync }                    = require 'child_process'
Stripe                          = require 'stripe'
{ waitForServer }               = require '../helper.coffee'
{ findFreePort, shutdownServer }= require '../server.coffee'


TEST_TMP_DIR   = '/tmp/rent-coordinator-tests'
BASE_PORT      = 4300
WEBHOOK_SECRET = 'whsec_test_secret_for_integration'
testConfig     = null
stripe         = new Stripe 'sk_test_dummy', apiVersion: '2024-12-18.acacia'


prepareTestDirectory = ->
  if fs.existsSync TEST_TMP_DIR
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true
  fs.mkdirSync TEST_TMP_DIR, recursive: true

cleanupTestDirectory = ->
  try
    if fs.existsSync TEST_TMP_DIR
      fs.rmSync TEST_TMP_DIR, recursive: true, force: true


# A payment_intent.succeeded event whose PaymentIntent carries an allocation
# plan (what create-intent freezes into metadata).
succeededEvent = (intentId, allocation) ->
  total = allocation.reduce ((s, a) -> s + a.amount), 0
  JSON.stringify
    id:   'evt_test'
    type: 'payment_intent.succeeded'
    data:
      object:
        id:       intentId
        amount:   Math.round total * 100
        metadata: { allocation: JSON.stringify allocation }

postWebhook = (payload) ->
  signature = stripe.webhooks.generateTestHeaderString { payload, secret: WEBHOOK_SECRET }
  fetch "#{testConfig.baseUrl}/payment/webhook",
    method:  'POST'
    headers: { 'Content-Type': 'application/json', 'stripe-signature': signature }
    body:    payload

period = (year, month) ->
  res = await fetch "#{testConfig.baseUrl}/rent/period/#{year}/#{month}"
  await res.json()


describe 'Stripe webhook records payment (bugs 09/10)', ->
  before ->
    prepareTestDirectory()

    port    = findFreePort BASE_PORT
    dbPath  = path.join TEST_TMP_DIR, "test-webhook-#{port}.db"
    logPath = path.join TEST_TMP_DIR, "webhook-#{port}.log"
    baseUrl = "http://localhost:#{port}"

    env = "PORT=#{port} DB_PATH=#{dbPath} NODE_ENV=test " +
          "STRIPE_SECRET_KEY=sk_test_dummy STRIPE_PUBLISHABLE_KEY=pk_test_dummy " +
          "STRIPE_WEBHOOK_SECRET=#{WEBHOOK_SECRET}"

    execSync "#{env} coffee main.coffee > #{logPath} 2>&1 &",
      stdio: 'ignore'
      shell: true

    await new Promise (resolve) -> setTimeout resolve, 1000
    await waitForServer "#{baseUrl}/health"

    testConfig = { port, dbPath, baseUrl, logPath }

  after ->
    await shutdownServer testConfig.baseUrl if testConfig
    cleanupTestDirectory()


  it "credits every allocated month on payment_intent.succeeded", ->
    payload = succeededEvent 'pi_alloc', [
      { year: 2026, month: 5, amount: 950 }
      { year: 2026, month: 6, amount: 950 }
    ]

    res = await postWebhook payload
    assert.equal res.status, 200
    assert.deepEqual (await res.json()), { received: true }

    may = await period 2026, 5
    jun = await period 2026, 6
    assert.equal may.amount_paid, 950, 'May credited'
    assert.equal jun.amount_paid, 950, 'June credited'


  it "is idempotent — a replayed webhook does not double-credit", ->
    payload = succeededEvent 'pi_once', [ { year: 2026, month: 3, amount: 950 } ]

    await postWebhook payload
    replay = await postWebhook payload
    assert.equal replay.status, 200, 'replay still acknowledged'

    mar = await period 2026, 3
    assert.equal mar.amount_paid, 950, 'credited once, not 1900'


  it "rejects a bad signature with 400 and records nothing", ->
    payload = succeededEvent 'pi_forged', [ { year: 2026, month: 2, amount: 950 } ]

    res = await fetch "#{testConfig.baseUrl}/payment/webhook",
      method:  'POST'
      headers: { 'Content-Type': 'application/json', 'stripe-signature': 't=1,v1=forged' }
      body:    payload
    assert.equal res.status, 400

    feb = await period 2026, 2
    assert.equal feb.amount_paid, 0, 'forged event ignored'
