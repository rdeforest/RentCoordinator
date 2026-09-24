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
#
# Each migration wraps its own work in a transaction, so one migration is
# already all-or-nothing. A *run* was not: migration seven of ten failing left
# the first six committed and recorded, on a schema no version of the code
# expects. So a run takes a snapshot first and restores it if anything fails.
#
# The snapshot is restored with copyFileSync, which writes into the existing
# file rather than replacing it, so a connection the application already holds
# follows the restored content. Renaming a new file over the path would be
# atomic and useless — an open handle tracks the inode, not the name.

{ DatabaseSync } = require 'node:sqlite'
fs               = require 'node:fs'
path             = require 'node:path'

DB_PATH        = process.env.DB_PATH or './tenant-coordinator.db'
# Overridable so the rollback path can be tested against throwaway migrations
# rather than by putting a deliberately broken one in the real directory.
MIGRATIONS_DIR = process.env.MIGRATIONS_DIR or path.join __dirname, '..', 'migrations'

# Every run with pending migrations leaves its pre-migration snapshot on disk,
# including a failed run's, which is the evidence a rollback happened. Pruning
# keeps the newest few by name regardless of outcome, so that evidence lasts
# three more deploys, not for ever. Nothing removed the old ones, so a database that had gone through
# several rounds of migrations was carrying a full VACUUM'd copy of itself
# for every single one of them (bug 52). Kept, not deleted outright: a recent
# snapshot is still useful if a bug shows up right after a deploy.
MAX_SNAPSHOTS_KEPT = 3


snapshotPath = (dbPath) ->
  stamp = new Date().toISOString().replace /[:.]/g, '-'
  "#{dbPath}.pre-migration-#{stamp}"


# Keeps the newest MAX_SNAPSHOTS_KEPT pre-migration snapshots for dbPath and
# removes the rest. Timestamped filenames sort chronologically as strings, so
# no parsing is needed.
pruneSnapshots = (dbPath) ->
  dir    = path.dirname dbPath
  prefix = "#{path.basename dbPath}.pre-migration-"

  snapshots = fs.readdirSync(dir)
    .filter (name) -> name.startsWith prefix
    .sort()

  stale = snapshots[0...-MAX_SNAPSHOTS_KEPT]
  fs.rmSync path.join(dir, name), force: true for name in stale
  stale.length


# SQLite's own consistent copy, rather than a file copy: the application may
# hold this database open, and copying the file behind a live connection can
# capture a state the journal has not finished describing.
takeSnapshot = (dbPath, target) ->
  fs.rmSync target, force: true

  db = new DatabaseSync dbPath
  try
    db.exec "VACUUM INTO '#{target.replace /'/g, "''"}'"
  finally
    db.close()

  target


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
  #
  # An earlier version of this runner recorded the full filename. A row is
  # therefore "applied" under any of the three spellings — without that, the
  # move to stems would have re-run every migration on every database the
  # previous version had already migrated, and one of them deletes every
  # stored verification code.
  isApplied = (stem) ->
    applied.has(stem) or applied.has("#{stem}.coffee") or applied.has("#{stem}.js")

  stems = new Map()
  for name in fs.readdirSync(MIGRATIONS_DIR).sort()
    [_, stem, ext] = name.match(/^(.*)\.(coffee|js)$/) ? []
    continue unless stem
    stems.set stem, name unless stems.has(stem) and ext is 'js'

  [stem, name] for [stem, name] from stems when not isApplied stem


# Each migration is a standalone script that opens its own connection, so this
# connection is closed around the run and the result recorded afterwards.
runMigrations = ->
  unless fs.existsSync DB_PATH
    # The application's own boot creates the schema before calling this, so a
    # missing file here means the caller is pointed somewhere wrong — which is
    # exactly the silent no-op this runner exists to stop. Say so; the CLI
    # turns it into a non-zero exit.
    throw new Error "No database at #{DB_PATH}. Set DB_PATH to the database you
                     mean to migrate."

  db      = new DatabaseSync DB_PATH
  pending = try pendingMigrations db finally db.close()

  if pending.length is 0
    console.log 'Migrations: already up to date'
    return []

  console.log "Migrations: #{pending.length} pending"

  snapshot = snapshotPath DB_PATH
  takeSnapshot DB_PATH, snapshot
  console.log "  pre-migration snapshot: #{snapshot}"

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

  try
    for [stem, name] in pending
      console.log "  applying #{name}"
      require path.join MIGRATIONS_DIR, name

      db = new DatabaseSync DB_PATH
      try
        db.prepare('INSERT OR REPLACE INTO schema_migrations (name) VALUES (?)').run stem
      finally
        db.close()

  catch err
    console.error "Migration failed: #{err.message}"
    console.error "Restoring the pre-migration database from #{snapshot}"
    fs.copyFileSync snapshot, DB_PATH
    console.error 'Restored. The database is as it was before this run.'
    finished = true
    throw err

  finished = true
  console.log "Migrations: applied #{pending.length}"

  pruned = pruneSnapshots DB_PATH
  console.log "  pruned #{pruned} old pre-migration snapshot(s)" if pruned > 0

  (stem for [stem] in pending)


# Apply the pending migrations to a throwaway copy and report, leaving the
# database alone. The point is to find out that a migration fails against real
# production data *before* the deploy that runs it for real — take a backup,
# point this at it, and you have tried the thing you are about to do.
#
# Migrations are required in-process and Node caches modules, so the check runs
# in a child: a migration required here would not run again in the same process
# afterwards.
checkMigrations = ->
  { execFileSync } = require 'node:child_process'

  unless fs.existsSync DB_PATH
    throw new Error "No database at #{DB_PATH}. Point DB_PATH at the backup you want to test."

  scratch = "#{DB_PATH}.check-#{process.pid}"
  takeSnapshot DB_PATH, scratch

  console.log "Checking migrations against a copy of #{DB_PATH}"

  # Invoked the way this file itself can be run: source is CoffeeScript, the
  # compiled artifact is plain JavaScript.
  [command, args] =
    if __filename.endsWith '.coffee'
    then ['npx', ['coffee', __filename]]
    else [process.execPath, [__filename]]

  try
    execFileSync command, args,
      env:   Object.assign {}, process.env, DB_PATH: scratch
      stdio: 'inherit'
    console.log 'Migrations apply cleanly. The real database was not touched.'
    true
  catch
    console.error 'Migrations FAILED against a copy. Do not deploy this yet.'
    false
  finally
    # The child takes its own snapshot of the scratch copy, so clear everything
    # named after it rather than just the copy itself.
    dir    = path.dirname scratch
    prefix = path.basename scratch
    for name in fs.readdirSync dir when name.startsWith prefix
      fs.rmSync path.join(dir, name), force: true


module.exports = { runMigrations, checkMigrations, pendingMigrations, takeSnapshot, pruneSnapshots }


# Run when invoked directly; stay quiet when required by schema.initialize().
if require.main is module
  try
    if process.argv.includes '--check'
      process.exit if checkMigrations() then 0 else 1
    else
      runMigrations()
  catch err
    console.error "Migration failed: #{err.message}"
    process.exit 1
