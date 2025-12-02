{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
fs                              = require 'fs'
path                            = require 'node:path'
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


# Helper to extract session cookie from response headers
getSessionCookie = (response) ->
  setCookie = response.headers.get 'set-cookie'
  return null unless setCookie

  # Extract just the session cookie value
  match = setCookie.match /connect\.sid=([^;]+)/
  return match?[1]


describe 'Auth Integration Tests', ->
  before ->
    prepareTestDirectory()

    port    = findFreePort BASE_PORT
    dbPath  = path.join TEST_TMP_DIR, "test-auth-#{port}.db"
    logPath = path.join TEST_TMP_DIR, "auth-#{port}.log"
    baseUrl = "http://localhost:#{port}"

    execSync "PORT=#{port} DB_PATH=#{dbPath} NODE_ENV=development coffee main.coffee > #{logPath} 2>&1 &",
      stdio: 'ignore'
      shell: true

    await new Promise (resolve) -> setTimeout resolve, 1000
    await waitForServer "#{baseUrl}/health"

    testConfig = { port, dbPath, baseUrl, logPath }

  after ->
    await shutdownServer testConfig.baseUrl if testConfig
    cleanupTestDirectory()


  it 'should persist session immediately after verification', ->
    { baseUrl } = testConfig
    email = 'robert@defore.st'

    # Step 1: Request verification code
    response = await fetch "#{baseUrl}/auth/send-code",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify { email }

    assert.equal response.status, 200, 'Send code should succeed'

    # Step 2: Get the code from the database (in dev mode, also logged to console)
    # In a real test, you'd extract from dev logs or mock the email service
    # For now, we'll read from the DB directly
    { DatabaseSync } = require 'node:sqlite'
    db               = new DatabaseSync testConfig.dbPath
    stored           = db.prepare("""
      SELECT code FROM auth_sessions
      WHERE email = ? AND verified = 0
      ORDER BY created_at DESC
      LIMIT 1
    """).get email
    db.close()

    assert.ok stored?.code, 'Verification code should be stored'

    # Step 3: Verify the code and capture the session cookie
    verifyResponse = await fetch "#{baseUrl}/auth/verify-code",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify { email, code: stored.code }

    assert.equal verifyResponse.status, 200, 'Verify should succeed'

    verifyData = await verifyResponse.json()
    assert.equal verifyData.success, true, 'Verify response should indicate success'

    sessionCookie = getSessionCookie verifyResponse
    assert.ok sessionCookie, 'Session cookie should be set after verification'

    # Step 4: THE CRITICAL TEST - immediately check auth status with the session cookie
    # This would fail with the race condition because the session wasn't saved yet
    statusResponse = await fetch "#{baseUrl}/auth/status",
      headers:
        'Cookie': "connect.sid=#{sessionCookie}"

    assert.equal statusResponse.status, 200, 'Auth status check should succeed'

    statusData = await statusResponse.json()
    assert.equal statusData.authenticated, true,
      'Session should be authenticated immediately after verification'
    assert.equal statusData.email, email,
      'Session should contain correct email'


  it 'should handle rapid sequential requests without race conditions', ->
    { baseUrl } = testConfig
    email = 'robert@defore.st'

    # Send code
    await fetch "#{baseUrl}/auth/send-code",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify { email }

    # Get code from DB
    { DatabaseSync } = require 'node:sqlite'
    db               = new DatabaseSync testConfig.dbPath
    stored           = db.prepare("""
      SELECT code FROM auth_sessions
      WHERE email = ? AND verified = 0
      ORDER BY created_at DESC
      LIMIT 1
    """).get email
    db.close()

    # Verify code
    verifyResponse = await fetch "#{baseUrl}/auth/verify-code",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify { email, code: stored.code }

    sessionCookie = getSessionCookie verifyResponse

    # Make multiple rapid requests with the session
    # Without the fix, some of these might fail due to race conditions
    makeRequest = ->
      fetch "#{baseUrl}/auth/status",
        headers: 'Cookie': "connect.sid=#{sessionCookie}"

    requests = [1..10].map makeRequest

    responses = await Promise.all requests

    for response, i in responses
      data = await response.json()
      assert.equal data.authenticated, true,
        "Request #{i + 1} should see authenticated session"


  it 'should reject invalid verification codes', ->
    { baseUrl } = testConfig
    email = 'robert@defore.st'

    # Send code
    await fetch "#{baseUrl}/auth/send-code",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify { email }

    # Try with wrong code
    response = await fetch "#{baseUrl}/auth/verify-code",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify { email, code: '000000' }

    assert.equal response.status, 400, 'Should reject invalid code'

    data = await response.json()
    assert.equal data.success, false, 'Response should indicate failure'
    assert.match data.error, /invalid/i, 'Error should mention invalid code'


  it 'should not allow reusing a verification code', ->
    { baseUrl } = testConfig
    email = 'robert@defore.st'

    # Clean up any old codes first to avoid interference
    { DatabaseSync } = require 'node:sqlite'
    db = new DatabaseSync testConfig.dbPath
    db.prepare("DELETE FROM auth_sessions WHERE email = ?").run email
    db.close()

    # Send code
    await fetch "#{baseUrl}/auth/send-code",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify { email }

    # Get code
    db = new DatabaseSync testConfig.dbPath
    stored = db.prepare("""
      SELECT code FROM auth_sessions
      WHERE email = ? AND verified = 0
      ORDER BY created_at DESC
      LIMIT 1
    """).get email
    db.close()

    # Use code once
    firstResponse = await fetch "#{baseUrl}/auth/verify-code",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify { email, code: stored.code }

    firstData = await firstResponse.json()
    console.log 'First verification response:', firstResponse.status, firstData
    assert.equal firstResponse.status, 200, 'First verification should succeed'

    # Try to use the same code again
    secondResponse = await fetch "#{baseUrl}/auth/verify-code",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify { email, code: stored.code }

    secondData = await secondResponse.json()
    console.log 'Second verification response:', secondResponse.status, secondData
    assert.equal secondResponse.status, 400, 'Second verification should fail'

    assert.equal secondData.success, false, 'Response should indicate failure'
    # After using a code, it's marked verified=1, so subsequent attempts should fail
    # Either "No verification code found" (correct) or "Invalid" (if old unverified codes exist)
    assert.match secondData.error, /no verification code found|invalid/i,
      "Error should indicate code cannot be reused (got: '#{secondData.error}')"
