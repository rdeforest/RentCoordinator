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

shutdownServer = (baseUrl) ->
  try
    response = await fetch "#{baseUrl}/v1/shutdown", method: 'POST'
    await new Promise (resolve) -> setTimeout resolve, 200
    true
  catch err
    false


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


module.exports = {
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
