# Bugs 11 / 21 / 33 — boot-time and middleware-stack behavior that no
# integration test can reach, because two of the three are about what the
# process does before it serves anything.

{ describe, it } = require 'node:test'
assert           = require 'node:assert/strict'
express          = require 'express'
{ execFileSync } = require 'node:child_process'


loadConfig = (env) ->
  childEnv = Object.assign {}, process.env, env, SESSION_SECRET: env.SESSION_SECRET ? ''
  delete childEnv.NODE_ENV if env.UNSET_NODE_ENV
  delete childEnv.UNSET_NODE_ENV

  try
    execFileSync 'coffee', ['-e', "require('./lib/config.coffee')"],
      env:      childEnv
      encoding: 'utf8'
      stdio:    ['ignore', 'pipe', 'pipe']
    ok: true, output: ''
  catch err
    ok: false, output: "#{err.stdout ? ''}#{err.stderr ? ''}"


listen = (app) ->
  new Promise (resolve) ->
    server = app.listen 0, -> resolve { server, port: server.address().port }


describe 'Config refuses an unsafe session secret (bug 11)', ->
  it 'refuses to load in production without SESSION_SECRET', ->
    result = loadConfig NODE_ENV: 'production'

    assert.equal result.ok, false,
      'an unset secret in production must stop the process, not fall back'
    assert.match result.output, /SESSION_SECRET/,
      'the failure must name the missing variable'

  it 'loads in production when SESSION_SECRET is provided', ->
    result = loadConfig NODE_ENV: 'production', SESSION_SECRET: 'a-real-secret'
    assert.equal result.ok, true, "production with a secret should load: #{result.output}"

  it 'still starts for development and test', ->
    for env in ['development', 'test']
      assert.equal loadConfig(NODE_ENV: env).ok, true,
        "#{env} should keep working without a configured secret"

  it 'refuses when NODE_ENV is not set at all', ->
    # The guard used to read the *defaulted* NODE_ENV, which is
    # 'development' — so a production box with a dropped env line took the
    # safe-looking branch and ran on a secret that is in the public repo.
    result = loadConfig UNSET_NODE_ENV: true

    assert.equal result.ok, false,
      'an absent NODE_ENV is a misconfiguration, not a declaration of dev'
    assert.match result.output, /SESSION_SECRET/


describe 'Error handler placement (bug 21)', ->
  # Express selects a 4-argument handler only if it was registered after the
  # route that failed. Both orderings are built here so the test proves the
  # mechanism rather than just asserting the fixed one works.
  buildApp = (registerHandlerFirst) ->
    app = express()
    app.set 'env', 'test'   # keeps Express's own handler from printing the stack

    errorHandler = (err, req, res, next) ->
      res.status(500).json error: 'Internal server error', handled: true

    app.use errorHandler if registerHandlerFirst
    app.get '/boom', (req, res) -> throw new Error 'kaboom'
    app.use errorHandler unless registerHandlerFirst

    app

  it 'a handler registered after the routes catches a thrown error', ->
    { server, port } = await listen buildApp false
    try
      response = await fetch "http://localhost:#{port}/boom"
      assert.equal response.status, 500
      assert.equal (await response.json()).handled, true,
        'the structured handler should have produced this body'
    finally
      server.close()

  it 'a handler registered before the routes never runs — the bug', ->
    { server, port } = await listen buildApp true
    try
      response = await fetch "http://localhost:#{port}/boom"
      assert.equal response.status, 500
      assert.match response.headers.get('content-type'), /html/,
        'Express fell through to its own HTML handler, which is the defect'
    finally
      server.close()

  it 'middleware exposes the handler separately so it can be mounted last', ->
    middleware = require '../../lib/middleware.coffee'
    assert.equal typeof middleware.setupErrorHandler, 'function',
      'setupErrorHandler must be callable after routing.setup'


describe 'Admin gate (bug 33)', ->
  middleware = require '../../lib/middleware.coffee'

  # requireAuth is what proves a session is real; requireAdmin's job is only
  # to say which of the two real users this is. It still checks
  # `authenticated`, because reading `email` off an unauthenticated session
  # would make the gate sound by coincidence rather than by construction.
  authed = (email) -> { email, authenticated: true }

  # A real request object, through a real Express app, because the previous
  # version of this test hand-stubbed `accepts` and `xhr` — and hard-coded the
  # one combination Express never produces, so it passed against a gate that
  # redirected every API caller into an HTML page.
  serve = (gate, session) ->
    app = express()
    app.set 'env', 'test'
    app.use (req, res, next) -> req.session = session; next()
    app.get '/gated', middleware[gate], (req, res) -> res.json ok: true
    app.get '/',      (req, res) -> res.send '<html>home</html>'
    app

  call = (gate, session, headers = {}) ->
    { server, port } = await listen serve gate, session
    try
      response = await fetch "http://localhost:#{port}/gated", { headers, redirect: 'manual' }
      body = try await response.json() catch then null
      { status: response.status, location: response.headers.get('location'), body }
    finally
      server.close()

  run = (session) -> call 'requireAdmin', session

  it 'lets the landlord through', ->
    assert.equal (await run authed 'robert@defore.st').status, 200

  it 'is case-insensitive about the landlord address', ->
    assert.equal (await run authed 'Robert@Defore.st').status, 200

  it 'rejects the tenant, who is authenticated but not an admin', ->
    result = await run authed 'lynz57@hotmail.com'
    assert.equal result.status, 403
    assert.match result.body.error, /admin/i

  it 'rejects an unauthenticated session even if it names the landlord', ->
    assert.equal (await run email: 'robert@defore.st').status, 403

  it 'rejects a request with no session at all', ->
    assert.equal (await run undefined).status, 403

  it 'answers an ordinary fetch with 403 JSON, not a redirect', ->
    # Accept: */* is what fetch and curl send by default, and Express reports
    # that as accepting html. A gate that keyed off it redirected every API
    # caller into a 200 HTML page, where response.json() throws on the doctype.
    for accept in ['*/*', 'application/json', undefined]
      headers = if accept then { Accept: accept } else {}
      result  = await call 'requireAdmin', authed('lynz57@hotmail.com'), headers

      assert.equal result.status, 403, "Accept: #{accept ? '(none)'} should get 403"
      assert.match result.body.error, /admin/i

  it 'sends a browser asking for the admin page somewhere usable', ->
    result = await call 'requireAdminPage', authed('lynz57@hotmail.com'),
      Accept: 'text/html,application/xhtml+xml'

    assert.equal result.status,   302
    assert.equal result.location, '/',
      'a JSON body rendered as a document is not a useful answer to a person'

  it 'still lets the landlord reach the page', ->
    assert.equal (await call 'requireAdminPage', authed 'robert@defore.st').status, 200


# Bug 50 — a handler error must always reach the client with a response, even
# when logging that error is itself what fails, and a validation error that
# already knows its status must not be flattened to a message-sniffed guess.
describe 'asyncRoute (bug 50)', ->
  middleware = require '../../lib/middleware.coffee'
  logger     = require '../../lib/logger.coffee'

  serve = (handler) ->
    app = express()
    app.set 'env', 'test'
    app.get '/route', middleware.asyncRoute 'test.route', handler
    app

  call = (handler) ->
    { server, port } = await listen serve handler
    try
      response = await fetch "http://localhost:#{port}/route"
      body = try await response.json() catch then null
      { status: response.status, body }
    finally
      server.close()

  it 'honours a 4xx err.status set by the handler', ->
    result = await call (req, res) ->
      err = new Error 'amount must be positive'
      err.status = 400
      throw err

    assert.equal result.status, 400
    assert.equal result.body.error, 'amount must be positive'

  it 'falls back to message-sniffing when err.status is absent', ->
    result = await call (req, res) -> throw new Error 'widget not found'
    assert.equal result.status, 404

  it 'does not let err.status claim a 5xx or an out-of-range value', ->
    result = await call (req, res) ->
      err = new Error 'boom'
      err.status = 599
      throw err

    assert.equal result.status, 500,
      'only 4xx is a handler-asserted status; anything else falls back to the default'

  it 'still responds when logging the error itself throws', ->
    original = logger.error
    logger.error = -> throw new Error 'logger exploded'
    try
      result = await call (req, res) -> throw new Error 'widget not found'
    finally
      logger.error = original

    assert.equal result.status, 404,
      'a broken logger must not swallow the response asyncRoute was about to send'


# Bug 50, belt and braces: nothing upstream of asyncRoute is guaranteed to
# catch every rejection, so the process itself must survive one. Run in a
# child — testing "does the process die" from inside the process under test
# would take this suite down with it if the fix regressed.
describe 'main.coffee survives an unhandled rejection (bug 50)', ->
  it 'logs the rejection and keeps running rather than exiting', ->
    script = """
      main = require './main.coffee'
      process.on 'unhandledRejection', main.handleUnhandledRejection
      Promise.reject new Error 'nobody caught this'
      setTimeout (-> console.log 'SENTINEL-REACHED'), 100
    """

    result = execFileSync 'coffee', ['-e', script],
      env:      Object.assign {}, process.env, NODE_ENV: 'test'
      encoding: 'utf8'
      stdio:    ['ignore', 'pipe', 'pipe']

    assert.match result, /SENTINEL-REACHED/,
      'the process must still be running after the rejection'
