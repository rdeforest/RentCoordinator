# migrations/2026-09-23_100000_auth_code_attempts.coffee
#
# Bug 12 — verification codes were brute-forceable: nothing counted failed
# guesses, so the full six-digit space was reachable inside the code's
# ten-minute window. Adds the attempts counter verifyCode now increments,
# burning the code after config.MAX_VERIFY_ATTEMPTS misses.
#
# Bug 38 — spent and expired codes were never removed. Clears the table:
# every row is a plaintext secret with at most ten minutes of life, so
# dropping them costs a user at worst one re-request.
#
# Also drops `verified`. verifyCode now deletes the row on success instead of
# flagging it, so nothing ever writes 1 and every `WHERE verified = 0` was a
# condition that could not exclude anything.
#
# Idempotent: each column change is skipped if it has already happened.

{ DatabaseSync } = require 'node:sqlite'

DB_PATH = process.env.DB_PATH or './tenant-coordinator.db'
db      = new DatabaseSync DB_PATH

console.log "Running migration: auth_code_attempts against #{DB_PATH}"


hasColumn = (table, column) ->
  db.prepare("PRAGMA table_info(#{table})").all().some (c) -> c.name is column


try
  db.exec 'BEGIN TRANSACTION'

  if hasColumn 'auth_sessions', 'attempts'
    console.log '  auth_sessions.attempts already present — skipping'
  else
    console.log '  Adding auth_sessions.attempts...'
    db.exec 'ALTER TABLE auth_sessions ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0'

  cleared = db.prepare('DELETE FROM auth_sessions').run().changes
  console.log "  Cleared #{cleared} stored verification code(s)"

  if hasColumn 'auth_sessions', 'verified'
    console.log '  Dropping auth_sessions.verified (nothing writes it any more)...'
    db.exec 'ALTER TABLE auth_sessions DROP COLUMN verified'
  else
    console.log '  auth_sessions.verified already dropped — skipping'

  db.exec 'COMMIT'
  console.log 'Migration completed successfully'

catch err
  console.error 'Migration failed:', err.message
  try
    db.exec 'ROLLBACK'
  catch rollbackErr
    console.error 'Rollback ALSO failed — the database may be mid-transaction:',
      rollbackErr.message
  throw err

finally
  db.close()
