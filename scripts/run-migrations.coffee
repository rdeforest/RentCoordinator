#!/usr/bin/env coffee
#
# Applies every migration in migrations/ that has not run yet, in filename
# order, recording each in schema_migrations so a re-run is a no-op.
#
# This exists because there was no runner. migrations/README.md pointed at
# scripts/upgrade.sh, which was an empty file (bug 47), and the only code that
# actually ran migrations was a loop in the CloudFormation UserData — so it
# ran at instance launch and nowhere else. The documented in-place upgrade
# (git pull, restart) therefore started new code against an old schema, which
# is a silent outage of whatever the new code depends on.
#
# Deliberately standalone: it opens the database directly rather than going
# through lib/config.coffee, so it can run before the app is configured and
# cannot be stopped by an app-level boot check.

{ DatabaseSync } = require 'node:sqlite'
fs               = require 'node:fs'
path             = require 'node:path'

DB_PATH        = process.env.DB_PATH or './tenant-coordinator.db'
MIGRATIONS_DIR = path.join __dirname, '..', 'migrations'


pendingMigrations = (db) ->
  db.exec """
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name        TEXT PRIMARY KEY,
      applied_at  DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  """

  applied = new Set (row.name for row in db.prepare('SELECT name FROM schema_migrations').all())

  # Source runs against .coffee; the compiled artifact has the same migrations
  # as .js. Matching only .coffee made the runner find nothing in dist/ and
  # report "already up to date" against a completely unmigrated database.
  # Recorded under the stem so a database migrated from source is not migrated
  # again from the artifact, or the other way round.
  stems = new Map()
  for name in fs.readdirSync(MIGRATIONS_DIR).sort()
    [_, stem, ext] = name.match(/^(.*)\.(coffee|js)$/) ? []
    continue unless stem
    stems.set stem, name unless stems.has(stem) and ext is 'js'

  [stem, name] for [stem, name] from stems when not applied.has stem


# Each migration is a standalone script that opens its own connection, so this
# connection is closed around the run and the result recorded afterwards.
runMigrations = ->
  unless fs.existsSync DB_PATH
    console.log "No database at #{DB_PATH} yet; nothing to migrate."
    return []

  db      = new DatabaseSync DB_PATH
  pending = try pendingMigrations db finally db.close()

  if pending.length is 0
    console.log 'Migrations: already up to date'
    return []

  console.log "Migrations: #{pending.length} pending"

  # A migration is a script, and a script can call process.exit. One of them
  # did, as an "already applied, nothing to do" shortcut — which ended the
  # server's own boot, before app.listen, with status 0. Nothing downstream
  # could tell that from a clean shutdown. No migration gets to decide this
  # process's lifetime silently.
  # Only a *silent* exit is the failure this guards. A migration that throws
  # propagates normally and the caller already sees the error; complaining
  # about that too would just be noise on a real failure.
  finished = false
  process.on 'exit', (code) ->
    return if finished or code isnt 0
    console.error "FATAL: a migration ended the process before the run
                   completed. Migrations must return, not exit."
    process.exitCode = 1

  # Required in-process rather than spawned. Each migration is a script that
  # does its work at load time and opens its own connection, so requiring it
  # runs it — and a boot that shells out to `npx coffee` nine times takes long
  # enough to push startup past a health check.
  process.env.DB_PATH = DB_PATH

  for [stem, name] in pending
    console.log "  applying #{name}"
    require path.join MIGRATIONS_DIR, name

    db = new DatabaseSync DB_PATH
    try
      db.prepare('INSERT OR REPLACE INTO schema_migrations (name) VALUES (?)').run stem
    finally
      db.close()

  finished = true
  console.log "Migrations: applied #{pending.length}"
  (stem for [stem] in pending)


module.exports = { runMigrations, pendingMigrations }


# Run when invoked directly; stay quiet when required by schema.initialize().
if require.main is module
  try
    runMigrations()
  catch err
    console.error "Migration failed: #{err.message}"
    process.exit 1
