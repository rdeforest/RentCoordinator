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

  run = (session) ->
    new Promise (resolve) ->
      req = session: session
      res =
        status: (code) ->
          statusCode: code
          json: (body) -> resolve { status: code, body }
      middleware.requireAdmin req, res, -> resolve status: 200

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
