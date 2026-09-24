# Bugs 12 / 22 / 38 — the login path.
#
# Each assertion here fails against the pre-fix code: unlimited guesses,
# case-sensitive lookups, and spent codes left in the table forever.

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
fs                              = require 'fs'
path                            = require 'node:path'
{ execSync }                    = require 'child_process'
{ DatabaseSync }                = require 'node:sqlite'
{ waitForServer }               = require '../helper.coffee'
{ findFreePort, shutdownServer }= require '../server.coffee'


TEST_TMP_DIR = '/tmp/rent-coordinator-tests'
BASE_PORT    = 4300
TENANT       = 'lynz57@hotmail.com'
LANDLORD     = 'robert@defore.st'
testConfig   = null


post = (path, body) ->
  fetch "#{testConfig.baseUrl}#{path}",
    method:  'POST'
    headers: 'Content-Type': 'application/json'
    body:    JSON.stringify body


withDb = (fn) ->
  db = new DatabaseSync testConfig.dbPath
  try fn db finally db.close()


storedCodeFor = (email) ->
  withDb (db) ->
    db.prepare("""
      SELECT * FROM auth_sessions WHERE email = ? ORDER BY created_at DESC LIMIT 1
    """).get email


describe 'Auth hardening (bugs 12/22/38)', ->
  before ->
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true if fs.existsSync TEST_TMP_DIR
    fs.mkdirSync TEST_TMP_DIR, recursive: true

    port    = findFreePort BASE_PORT
    dbPath  = path.join TEST_TMP_DIR, "test-auth-hardening-#{port}.db"
    logPath = path.join TEST_TMP_DIR, "auth-hardening-#{port}.log"

    # development, not test: NODE_ENV=test bypasses requireAuth entirely
    # (bug 23), which would make every assertion here vacuous.
    execSync "PORT=#{port} DB_PATH=#{dbPath} NODE_ENV=development coffee main.coffee > #{logPath} 2>&1 &",
      stdio: 'ignore'
      shell: true

    await new Promise (resolve) -> setTimeout resolve, 1000
    await waitForServer "http://localhost:#{port}/health"

    testConfig = { port, dbPath, baseUrl: "http://localhost:#{port}", logPath }

  after ->
    await shutdownServer testConfig.baseUrl if testConfig
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true


  it 'burns the code after five wrong guesses, so the real one no longer works', ->
    await post '/auth/send-code', email: TENANT
    real = storedCodeFor(TENANT).code

    wrong = if real is '000000' then '111111' else '000000'

    for attempt in [1..4]
      response = await post '/auth/verify-code', email: TENANT, code: wrong
      body     = await response.json()
      assert.equal response.status, 400, "guess #{attempt} should be rejected"
      assert.match body.error, /invalid/i, "guess #{attempt} should read as invalid"

    fifth = await post '/auth/verify-code', email: TENANT, code: wrong
    assert.equal fifth.status, 400
    assert.match (await fifth.json()).error, /too many/i,
      'the fifth miss should report the lockout, not another plain rejection'

    assert.equal storedCodeFor(TENANT), undefined,
      'the burned code should be gone from the table, not merely flagged'

    afterLockout = await post '/auth/verify-code', email: TENANT, code: real
    assert.equal afterLockout.status, 400,
      'the genuine code must not work once the attempt budget is spent'


  it 'counts attempts per code, so a fresh code starts over', ->
    await post '/auth/send-code', email: TENANT
    first = storedCodeFor TENANT
    assert.equal first.attempts, 0, 'a newly issued code starts with no attempts'

    await post '/auth/verify-code', email: TENANT, code: '000000'
    assert.equal storedCodeFor(TENANT).attempts, 1,
      'a wrong guess must be persisted, or the lockout can never trigger'


  it 'verifies a code requested under different casing (bug 22)', ->
    mixed = 'Robert@Defore.ST'

    response = await post '/auth/send-code', email: mixed
    assert.equal response.status, 200

    assert.ok storedCodeFor(LANDLORD),
      'the code must be stored under the normalized address'
    assert.equal storedCodeFor(mixed), undefined,
      'nothing should be stored under the raw casing'

    verified = await post '/auth/verify-code', email: LANDLORD, code: storedCodeFor(LANDLORD).code
    assert.equal verified.status, 200,
      'a code requested as Robert@Defore.ST must verify as robert@defore.st'
    assert.equal (await verified.json()).email, LANDLORD,
      'the session should carry the normalized address'


  it 'deletes the code row once it has been used (bug 38)', ->
    await post '/auth/send-code', email: LANDLORD
    code = storedCodeFor(LANDLORD).code

    assert.equal (await post '/auth/verify-code', email: LANDLORD, code: code).status, 200

    assert.equal storedCodeFor(LANDLORD), undefined,
      'a spent code is a plaintext secret with no remaining use'


  it 'purges expired codes when the next one is issued (bug 38)', ->
    await post '/auth/send-code', email: TENANT

    withDb (db) ->
      db.prepare("""
        UPDATE auth_sessions SET expires_at = ? WHERE email = ?
      """).run new Date(Date.now() - 60000).toISOString(), TENANT

    await post '/auth/send-code', email: LANDLORD

    remaining = withDb (db) ->
      db.prepare("SELECT COUNT(*) AS n FROM auth_sessions WHERE email = ?").get TENANT

    assert.equal remaining.n, 0,
      'issuing a code should sweep the expired rows still holding plaintext'


  it 'throttles repeated code requests for one address', ->
    responses = for attempt in [1..8]
      await post '/auth/send-code', email: TENANT

    statuses = (r.status for r in responses)

    assert.ok 429 in statuses,
      "repeated requests should eventually be throttled (got #{statuses.join ', '})"

    throttled = responses.find (r) -> r.status is 429
    assert.ok throttled.headers.get('retry-after'),
      'a 429 should tell the caller when to come back'


  it 'refuses to send a code to an address that is not on the list', ->
    # The only thing making this a two-user app. Nothing covered it: making
    # `unless isEmailAllowed email` unconditional left every suite green.
    for stranger in ['stranger@example.com', 'robert@defore.st.evil.com', 'lynz57@gmail.com']
      response = await post '/auth/send-code', email: stranger

      assert.equal response.status, 400, "#{stranger} should be refused"
      assert.match (await response.json()).error, /not authorized/i

      assert.equal storedCodeFor(stranger), undefined,
        "no code may be stored for #{stranger}"


  it 'does not log a refused address into the permanent PII store (bug 60)', ->
    stranger = "never-a-user-#{Date.now()}@example.com"

    response = await post '/auth/send-code', email: stranger
    assert.equal response.status, 400

    log = fs.readFileSync testConfig.logPath, 'utf8'

    assert.ok not log.includes(stranger),
      'a refused address is not a user — it must not appear in the log at all, ' +
      'tokenized or not, since logger.error would tokenize it into pii_tokens forever'

    rejectionLines = log.split('\n').filter (l) -> l.includes 'auth.sendCode.rejected'
    assert.ok rejectionLines.length > 0, 'the refusal should still be logged, at warn level'

    for line in rejectionLines
      record = JSON.parse line
      assert.equal record.level, 'warn', 'a routine refusal is not an error'
      assert.equal record.stack, undefined, 'no stack trace for an expected rejection'


  it 'does not leak whether an address is on the list by timing out or hanging', ->
    # A refusal and an acceptance should both be prompt; a stranger learning
    # they are a stranger is unavoidable here (the app has two users and says
    # so), but it should not cost a request that never returns.
    started  = Date.now()
    response = await post '/auth/send-code', email: 'stranger@example.com'

    assert.equal response.status, 400
    assert.ok Date.now() - started < 3000, 'a refusal should be immediate'


  it 'still refuses a stranger who supplies a real code', ->
    # Verification must not be a way around the allowlist.
    await post '/auth/send-code', email: LANDLORD
    real = storedCodeFor(LANDLORD).code

    response = await post '/auth/verify-code', email: 'stranger@example.com', code: real

    assert.equal response.status, 400
    assert.equal (await response.json()).success, false
