# Bug 65 — express-session with no `store` defaults to MemoryStore, which
# dies with the process. This is the test that actually exercises the bug:
# log in, kill the server, start a fresh process against the *same* database,
# and check the cookie issued by the first process still authenticates
# against the second. Against MemoryStore this fails outright — the second
# process has never heard of the session id.

{ describe, it } = require 'node:test'
assert            = require 'node:assert/strict'
fs                = require 'node:fs'
path              = require 'node:path'
{ execSync }      = require 'child_process'
{ waitForServer } = require '../helper.coffee'
{ findFreePort, shutdownServer, authenticate, TEST_TMP_DIR } = require '../server.coffee'


# config.coffee mints a fresh ephemeral SESSION_SECRET per process when none
# is set, so a cookie signed by the first process would fail signature
# verification against the second regardless of the store — that's a
# separate, already-documented tradeoff (lib/config.coffee), not what this
# test is about. Pinning SESSION_SECRET here isolates the one variable this
# test exists to check: does the *store* survive the restart.
SESSION_SECRET = 'session-persistence-test-secret'

startOn = (port, dbPath, label) ->
  logPath = path.join TEST_TMP_DIR, "session-persist-#{label}-#{port}.log"
  baseUrl = "http://localhost:#{port}"

  execSync "PORT=#{port} DB_PATH=#{dbPath} NODE_ENV=test SESSION_SECRET=#{SESSION_SECRET} coffee main.coffee > #{logPath} 2>&1 &",
    stdio: 'ignore'
    shell: true

  await new Promise (resolve) -> setTimeout resolve, 1000
  await waitForServer "#{baseUrl}/health"

  baseUrl


describe 'Session survives a server restart (bug 65)', ->
  it 'a cookie issued before a restart still authenticates against a fresh process on the same DB', ->
    if fs.existsSync TEST_TMP_DIR
      fs.rmSync TEST_TMP_DIR, recursive: true, force: true
    fs.mkdirSync TEST_TMP_DIR, recursive: true

    port   = findFreePort 4200
    dbPath = path.join TEST_TMP_DIR, "session-persist-#{port}.db"

    firstUrl = await startOn port, dbPath, 'first'
    cookie   = await authenticate firstUrl, dbPath

    # Confirm it actually works before tearing anything down.
    statusBefore = await fetch "#{firstUrl}/auth/status", headers: Cookie: cookie
    assert.equal (await statusBefore.json()).authenticated, true,
      'sanity check: the session must be good before the restart'

    await shutdownServer firstUrl

    secondUrl = await startOn port, dbPath, 'second'
    try
      statusAfter = await fetch "#{secondUrl}/auth/status", headers: Cookie: cookie
      assert.equal statusAfter.status, 200

      data = await statusAfter.json()
      assert.equal data.authenticated, true,
        'the session written by the first process must be readable by the second — ' +
        'MemoryStore fails this because it keeps sessions only in that process RAM'
    finally
      await shutdownServer secondUrl
      fs.rmSync TEST_TMP_DIR, recursive: true, force: true
