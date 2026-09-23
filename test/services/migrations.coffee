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

# Created at load, not in a hook: a suite's `after` would pull the directory
# out from under the suites declared below it.
tmpDir = fs.mkdtempSync path.join os.tmpdir(), 'rc-migrations-'
process.on 'exit', -> fs.rmSync tmpDir, recursive: true, force: true


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


  it 'treats a migration recorded under its old filename as applied', ->
    # An earlier version of this runner wrote `name` with the extension. The
    # move to stems compared against the bare stem, so every one of those rows
    # matched nothing and every migration became pending again — re-running,
    # among others, the one that deletes every stored verification code.
    dbPath = path.join tmpDir, 'legacy-names.db'
    bootDatabase dbPath

    withDb dbPath, (db) ->
      db.exec 'DELETE FROM schema_migrations'
      insert = db.prepare 'INSERT INTO schema_migrations (name) VALUES (?)'
      insert.run name for name in fs.readdirSync(path.join ROOT, 'migrations') when name.endsWith '.coffee'

    result = runMigrations dbPath

    assert.match result.output, /already up to date/,
      "rows written under the old convention must count as applied:\n#{result.output}"

    names = withDb dbPath, (db) ->
      (row.name for row in db.prepare('SELECT name FROM schema_migrations').all())

    assert.equal names.length, MIGRATION_COUNT,
      "the table must not end up holding both spellings (got #{names.length})"


  it 'refuses a database path that does not exist', ->
    # Reporting success against a database that is not there is how the
    # documented upgrade came to do nothing at all.
    result = runMigrations path.join tmpDir, 'no-such.db'

    assert.equal result.ok, false, 'a missing database must be an error, not an empty result'
    assert.match result.output, /No database at/


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


# --- rollback ----------------------------------------------------------------
#
# Each migration already wraps its own work in a transaction, so one migration
# is all-or-nothing. A *run* was not: migration seven of ten failing left the
# first six committed, on a schema no version of the code expects.

describe 'A failed run leaves the database as it was', ->
  migrationsDir = null

  # Migrations are ordinary scripts, so a throwaway directory of them exercises
  # the real path without a deliberately broken file living in migrations/.
  writeMigrations = (specs) ->
    migrationsDir = fs.mkdtempSync path.join tmpDir, 'migrations-'
    for [name, body] in specs
      fs.writeFileSync path.join(migrationsDir, name), """
        { DatabaseSync } = require 'node:sqlite'
        db = new DatabaseSync process.env.DB_PATH
        try
        #{body.split('\n').map((l) -> '  ' + l).join '\n'}
        finally
          db.close()
      """
    migrationsDir

  runAgainst = (dbPath, dir, args = '') ->
    script = "require('./scripts/run-migrations.coffee').runMigrations(); console.log('SENTINEL-REACHED')"
    try
      output = execFileSync 'coffee', ['-e', script],
        cwd:      ROOT
        env:      Object.assign {}, process.env, DB_PATH: dbPath, NODE_ENV: 'test', MIGRATIONS_DIR: dir
        encoding: 'utf8'
        stdio:    ['ignore', 'pipe', 'pipe']
      { ok: true, output }
    catch err
      { ok: false, output: "#{err.stdout ? ''}#{err.stderr ? ''}" }

  seedDb = (name) ->
    dbPath = path.join tmpDir, name
    withDb dbPath, (db) ->
      db.exec 'CREATE TABLE keepsake (v TEXT)'
      db.prepare('INSERT INTO keepsake VALUES (?)').run 'original'
    dbPath


  it 'undoes a migration that committed before it failed', ->
    # The case a per-migration transaction cannot cover: the work is committed,
    # and only then does something go wrong.
    dir = writeMigrations [
      ['001-ok.coffee',     "db.exec 'CREATE TABLE first_one (x INTEGER)'"]
      ['002-broken.coffee', """
        db.exec 'CREATE TABLE committed_then_failed (x INTEGER)'
        throw new Error 'simulated failure after a committed step'
      """]
    ]
    dbPath = seedDb 'rollback.db'

    result = runAgainst dbPath, dir

    assert.equal result.ok, false, 'the run must fail'
    assert.match result.output, /Restored\. The database is as it was/

    withDb dbPath, (db) ->
      exists = (table) ->
        db.prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE type='table' AND name = ?").get(table).n > 0

      assert.equal db.prepare('SELECT v FROM keepsake').get().v, 'original',
        'existing data survives'
      assert.ok not exists('committed_then_failed'),
        'the committed table from the failed migration is gone'
      assert.ok not exists('first_one'),
        'and so is the one from the migration that succeeded before it — a run is all or nothing'
      assert.equal db.prepare('SELECT COUNT(*) AS n FROM schema_migrations').get().n, 0,
        'nothing is recorded as applied'


  it 'keeps the snapshot it restored from', ->
    dir    = writeMigrations [['001-broken.coffee', "throw new Error 'nope'"]]
    dbPath = seedDb 'snapshot-kept.db'

    runAgainst dbPath, dir

    snapshots = fs.readdirSync(tmpDir).filter (n) -> n.startsWith 'snapshot-kept.db.pre-migration-'
    assert.equal snapshots.length, 1, 'the evidence is left on disk, not silently discarded'


  it 'records everything when the run succeeds', ->
    dir    = writeMigrations [
      ['001-ok.coffee', "db.exec 'CREATE TABLE a (x INTEGER)'"]
      ['002-ok.coffee', "db.exec 'CREATE TABLE b (x INTEGER)'"]
    ]
    dbPath = seedDb 'success.db'

    result = runAgainst dbPath, dir

    assert.ok result.ok, "the run should succeed:\n#{result.output}"
    withDb dbPath, (db) ->
      assert.equal db.prepare('SELECT COUNT(*) AS n FROM schema_migrations').get().n, 2
