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

  fs.readdirSync MIGRATIONS_DIR
    .filter (name) -> name.endsWith '.coffee'
    .sort()
    .filter (name) -> not applied.has name


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

  # Required in-process rather than spawned. Each migration is a script that
  # does its work at load time and opens its own connection, so requiring it
  # runs it — and a boot that shells out to `npx coffee` nine times takes long
  # enough to push startup past a health check.
  process.env.DB_PATH = DB_PATH

  for name in pending
    console.log "  applying #{name}"
    require path.join MIGRATIONS_DIR, name

    db = new DatabaseSync DB_PATH
    try
      db.prepare('INSERT OR REPLACE INTO schema_migrations (name) VALUES (?)').run name
    finally
      db.close()

  console.log "Migrations: applied #{pending.length}"
  pending


module.exports = { runMigrations, pendingMigrations }


# Run when invoked directly; stay quiet when required by schema.initialize().
if require.main is module
  try
    runMigrations()
  catch err
    console.error "Migration failed: #{err.message}"
    process.exit 1
