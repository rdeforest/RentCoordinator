# scripts/run-migrations.coffee
#
# The runner applies migrations inside the server's own process at boot, which
# makes a migration's control flow the server's control flow. The suite missed
# that: every other test starts from a fresh database, where the one migration
# that used to call `process.exit 0` never took that branch.
#
# These run the runner in a child process so "did the host survive?" is an
# assertion rather than a way for the test to disappear.

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
fs                              = require 'node:fs'
os                              = require 'node:os'
path                            = require 'node:path'
{ execFileSync }                = require 'node:child_process'
{ DatabaseSync }                = require 'node:sqlite'

ROOT      = path.join __dirname, '..', '..'
MIGRATION_COUNT = fs.readdirSync(path.join ROOT, 'migrations')
  .filter((n) -> n.endsWith '.coffee').length

tmpDir = null


# Runs something in a child and reports whether the process got to the end on
# its own. A migration that exits takes the child with it, so the sentinel is
# the evidence that nothing did.
inChild = (dbPath, script) ->
  script = "#{script}; console.log('SENTINEL-REACHED')"

  try
    output = execFileSync 'coffee', ['-e', script],
      cwd:      ROOT
      env:      Object.assign {}, process.env, DB_PATH: dbPath, NODE_ENV: 'test'
      encoding: 'utf8'
      stdio:    ['ignore', 'pipe', 'pipe']
    { ok: true, survived: output.includes('SENTINEL-REACHED'), output }
  catch err
    { ok: false, survived: false, output: "#{err.stdout ? ''}#{err.stderr ? ''}" }


# The real boot path: create the schema, then apply pending migrations.
bootDatabase = (dbPath) ->
  inChild dbPath, "require('./lib/db/schema.coffee').initialize()"


# The runner on its own, the way scripts/upgrade.sh calls it.
runMigrations = (dbPath) ->
  inChild dbPath, "require('./scripts/run-migrations.coffee').runMigrations()"


withDb = (dbPath, fn) ->
  db = new DatabaseSync dbPath
  try fn db finally db.close()


applied = (dbPath) ->
  withDb dbPath, (db) ->
    try
      db.prepare('SELECT COUNT(*) AS n FROM schema_migrations').get().n
    catch
      0


describe 'Migration runner', ->
  before -> tmpDir = fs.mkdtempSync path.join os.tmpdir(), 'rc-migrations-'
  after  -> fs.rmSync tmpDir, recursive: true, force: true


  it 'applies every migration to a fresh database', ->
    dbPath = path.join tmpDir, 'fresh.db'

    result = bootDatabase dbPath

    assert.ok result.ok, "runner failed: #{result.output}"
    assert.ok result.survived, 'the runner must return, not end the process'
    assert.equal applied(dbPath), MIGRATION_COUNT


  it 'survives a database that has already been seeded', ->
    # The blocking case. An existing install has rows in `events` and no
    # `schema_migrations`, so every migration is pending and the seed
    # migration takes its "already seeded" branch. That branch used to be
    # `process.exit 0`, which ended the server mid-boot — before app.listen,
    # with status 0, so nothing downstream could tell it from a clean stop.
    dbPath = path.join tmpDir, 'seeded.db'
    bootDatabase dbPath

    withDb dbPath, (db) ->
      db.prepare("""
        INSERT INTO events (id, occurred_at, actor, actor_user, action, payload)
        VALUES ('seeded-row', ?, 'tenant', 'lynz57@hotmail.com', 'payment-made', '{"amount":1}')
      """).run new Date().toISOString()
      db.exec 'DROP TABLE schema_migrations'

    result = bootDatabase dbPath

    assert.ok result.survived,
      "boot ended the host process instead of returning:\n#{result.output}"
    assert.equal applied(dbPath), MIGRATION_COUNT,
      'every migration must be recorded, including the one that had nothing to do'

    withDb dbPath, (db) ->
      assert.equal db.prepare("SELECT COUNT(*) AS n FROM events").get().n, 1,
        'and the existing events must be left alone'


  it 'is a no-op the second time', ->
    dbPath = path.join tmpDir, 'twice.db'

    bootDatabase dbPath
    result = runMigrations dbPath

    assert.match result.output, /already up to date/
    assert.equal applied(dbPath), MIGRATION_COUNT


  it 'leaves the schema the running code expects', ->
    dbPath = path.join tmpDir, 'schema.db'
    bootDatabase dbPath

    withDb dbPath, (db) ->
      hasColumn = (table, column) ->
        db.prepare("PRAGMA table_info(#{table})").all().some (c) -> c.name is column

      assert.ok hasColumn('auth_sessions', 'attempts'),
        'verifyCode writes this column on every failed guess'
      assert.ok hasColumn('recurring_event_logs', 'status'),
        'createProcessingLog writes this column'
      assert.ok db.prepare("SELECT sql FROM sqlite_master WHERE name = 'work_logs'").get().sql.includes 'ON DELETE'


  it 'records a migration once, whether it ran from source or from the build', ->
    # dist/ ships the same migrations compiled to .js. Recording the filename
    # rather than the stem would have re-run all ten the first time the
    # artifact touched a database migrated from source.
    dbPath = path.join tmpDir, 'stems.db'
    bootDatabase dbPath

    names = withDb dbPath, (db) ->
      (row.name for row in db.prepare('SELECT name FROM schema_migrations').all())

    assert.ok names.every((n) -> not n.endsWith('.coffee') and not n.endsWith('.js')),
      "recorded names must be extension-free stems, got: #{names[0]}"
