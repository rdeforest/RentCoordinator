fs           = require 'fs'
path         = require 'path'
{ execSync } = require 'child_process'
{ waitForServer } = require './helper.coffee'


TEST_TMP_DIR      = '/tmp/rent-coordinator-tests'
DEFAULT_TEST_PORT = 3999
DEFAULT_TEST_DB   = path.join TEST_TMP_DIR, 'test-server.db'


prepareTestDirectory = ->
  if fs.existsSync TEST_TMP_DIR
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true
  fs.mkdirSync TEST_TMP_DIR, recursive: true

cleanupTestDirectory = ->
  try
    if fs.existsSync TEST_TMP_DIR
      fs.rmSync TEST_TMP_DIR, recursive: true, force: true


isPortFree = (port) ->
  try
    execSync "lsof -ti :#{port}", stdio: 'ignore'
    false
  catch
    true

findFreePort = (startPort = DEFAULT_TEST_PORT) ->
  port = startPort
  while port < startPort + 100
    return port if isPortFree port
    port++
  throw new Error "No free ports found in range #{startPort}-#{startPort + 100}"

# A refused shutdown used to be swallowed, so a suite that started its server
# outside test mode leaked it on every run.
shutdownServer = (baseUrl) ->
  response = await fetch "#{baseUrl}/v1/shutdown", method: 'POST'
  unless response.ok
    throw new Error "#{baseUrl} refused to shut down (#{response.status}); the server is still running"
  await new Promise (resolve) -> setTimeout resolve, 200


startTestServer = (options = {}) ->
  port    = findFreePort options.port or DEFAULT_TEST_PORT
  dbPath  = options.dbPath or path.join TEST_TMP_DIR, "test-#{port}.db"
  baseUrl = "http://localhost:#{port}"
  logPath = path.join TEST_TMP_DIR, "server-#{port}.log"

  prepareTestDirectory()

  execSync "PORT=#{port} DB_PATH=#{dbPath} NODE_ENV=test coffee main.coffee > #{logPath} 2>&1 &",
    stdio: 'ignore'
    shell: true

  await new Promise (resolve) -> setTimeout resolve, 1000
  await waitForServer "#{baseUrl}/health"

  { port, dbPath, baseUrl, logPath }

stopTestServer = (config) ->
  await shutdownServer config.baseUrl
  cleanupTestDirectory()


# Authenticate the way a real client does: request a code, read it out of the
# database, verify it, keep the cookie. requireAuth no longer has a NODE_ENV
# bypass (bug 23), so a suite that touches a protected route needs a real
# session — which is the point. While the bypass existed, deleting the auth
# gate outright left every integration suite green.
authenticate = (baseUrl, dbPath, email = 'robert@defore.st') ->
  { DatabaseSync } = require 'node:sqlite'

  send = (path, body) ->
    fetch "#{baseUrl}#{path}",
      method:  'POST'
      headers: 'Content-Type': 'application/json'
      body:    JSON.stringify body

  requested = await send '/auth/send-code', { email }
  unless requested.ok
    throw new Error "send-code failed: #{requested.status} #{await requested.text()}"

  db = new DatabaseSync dbPath
  stored = try
    db.prepare("""
      SELECT code FROM auth_sessions WHERE email = ? ORDER BY created_at DESC LIMIT 1
    """).get email
  finally
    db.close()

  throw new Error "no verification code stored for #{email}" unless stored?.code

  verified = await send '/auth/verify-code', { email, code: stored.code }
  unless verified.ok
    throw new Error "verify-code failed: #{verified.status} #{await verified.text()}"

  match = verified.headers.get('set-cookie')?.match /connect\.sid=([^;]+)/
  throw new Error 'verify-code returned no session cookie' unless match

  "connect.sid=#{match[1]}"


# A session-holding client. Suites call one of these instead of bare fetch, so
# the cookie lives in one place rather than on forty call sites.
authenticatedClient = (baseUrl, dbPath, email = 'robert@defore.st') ->
  cookie = await authenticate baseUrl, dbPath, email

  request = (method, path, body) ->
    headers = { Cookie: cookie }
    headers['Content-Type'] = 'application/json' if body?

    options = { method, headers }
    options.body = JSON.stringify body if body?

    fetch "#{baseUrl}#{path}", options

  {
    cookie
    request
    get:  (path)       -> request 'GET',    path
    post: (path, body) -> request 'POST',   path, body
    put:  (path, body) -> request 'PUT',    path, body
    del:  (path, body) -> request 'DELETE', path, body
    json: (path)       -> (await request 'GET', path).json()
  }


module.exports = {
  authenticate
  authenticatedClient
  TEST_TMP_DIR
  DEFAULT_TEST_PORT
  DEFAULT_TEST_DB
  prepareTestDirectory
  cleanupTestDirectory
  isPortFree
  findFreePort
  shutdownServer
  startTestServer
  stopTestServer
}
