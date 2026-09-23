# Bug 23 — the gate in front of every route.
#
# While requireAuth short-circuited on NODE_ENV=test, none of this was
# observable: deleting `app.use middleware.requireAuth` from routing.coffee,
# or making requireAuth call next() unconditionally, left every integration
# suite green. Ten of the twelve booted with NODE_ENV=test, and the two that
# did not only called /auth/* routes, which register before the gate.
#
# These tests fail if the gate is removed, weakened, or mounted in the wrong
# place — which is the whole point of them.

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
fs                              = require 'fs'
path                            = require 'path'
{ execSync }                    = require 'child_process'
{ waitForServer }               = require '../helper.coffee'
{ findFreePort, shutdownServer, authenticatedClient } = require '../server.coffee'

TEST_TMP_DIR = '/tmp/rent-coordinator-tests'
BASE_PORT    = 4950
testConfig   = null

# One from each router, so a gate mounted after any of them shows up here.
PROTECTED = [
  '/rent/periods'
  '/rent/summary'
  '/work-logs'
  '/timer/status?worker=robert'
  '/v1/api/payments'
  '/admin/logs'
  '/api/backup/list'
]

OPEN = ['/health', '/health/ready', '/login.html']

anonymous = (path, options = {}) ->
  fetch "#{testConfig.baseUrl}#{path}",
    Object.assign {}, options,
      headers: Object.assign {}, (options.headers ? {}), { Accept: 'application/json' }


describe 'The auth gate (bug 23)', ->
  before ->
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true if fs.existsSync TEST_TMP_DIR
    fs.mkdirSync TEST_TMP_DIR, recursive: true

    port   = findFreePort BASE_PORT
    dbPath = path.join TEST_TMP_DIR, "auth-gate-#{port}.db"
    log    = path.join TEST_TMP_DIR, "auth-gate-#{port}.log"

    execSync "PORT=#{port} DB_PATH=#{dbPath} NODE_ENV=test coffee main.coffee > #{log} 2>&1 &",
      stdio: 'ignore', shell: true
    await new Promise (resolve) -> setTimeout resolve, 1000
    await waitForServer "http://localhost:#{port}/health"

    baseUrl = "http://localhost:#{port}"
    testConfig = { baseUrl, dbPath, client: await authenticatedClient baseUrl, dbPath }

  after ->
    await shutdownServer testConfig.baseUrl if testConfig
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true


  it 'refuses every protected route without a session', ->
    for route in PROTECTED
      response = await anonymous route
      assert.equal response.status, 401,
        "#{route} answered #{response.status} with no session"


  it 'refuses a write without a session', ->
    response = await anonymous '/work-logs',
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify
        worker: 'lyndzie', start_time: '2026-02-10T09:00:00Z', end_time: '2026-02-10T10:00:00Z'
        duration: 60, description: 'should never be written'

    assert.equal response.status, 401

    # And nothing was written, which a 401 alone would not prove.
    logs = await testConfig.client.json '/work-logs'
    assert.equal logs.length, 0


  it 'refuses a forged session cookie', ->
    response = await fetch "#{testConfig.baseUrl}/rent/periods",
      headers: { Accept: 'application/json', Cookie: 'connect.sid=s%3Anot-a-real-session.forged' }

    assert.equal response.status, 401,
      'a cookie is only as good as its signature'


  it 'sends a browser to the login page rather than a JSON body', ->
    response = await fetch "#{testConfig.baseUrl}/rent",
      headers:  { Accept: 'text/html,application/xhtml+xml' }
      redirect: 'manual'

    assert.equal response.status, 302
    assert.equal response.headers.get('location'), '/login.html'


  it 'lets the unauthenticated routes through', ->
    for route in OPEN
      response = await anonymous route
      assert.notEqual response.status, 401, "#{route} must stay reachable"


  it 'admits a real session', ->
    for route in PROTECTED when route isnt '/admin/logs' and not route.startsWith '/api/backup'
      response = await testConfig.client.get route
      assert.notEqual response.status, 401,
        "#{route} refused a valid session"


  it 'still distinguishes the landlord from the tenant', ->
    # The session is real either way; requireAdmin is a second question.
    tenant = await authenticatedClient testConfig.baseUrl, testConfig.dbPath, 'lynz57@hotmail.com'

    assert.equal (await tenant.get '/api/backup/list').status, 403,
      'an authenticated tenant is not an admin'
    assert.notEqual (await testConfig.client.get '/api/backup/list').status, 403,
      'and the landlord is'
