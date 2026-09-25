# Bug 65 — express-session with no `store` option defaults to MemoryStore,
# which express-session's own docs say is not for production: sessions die
# with the process and are never evicted. This is the SQLite-backed
# replacement, in the same database the rest of the app already uses (bug 42:
# never open a second connection).
#
# express-session/README.md ("Session Store Implementation") lists get, set
# and destroy as required. touch is deliberately absent: express-session calls
# it on every request, and with rolling off it would only rewrite a row the
# cookie's own expiry already bounds - a database write per page view, which
# keeps the idle backup from ever seeing the database idle.

{ Store } = require 'express-session'
{ db }    = require '../db/schema.coffee'
config    = require '../config.coffee'

# Mirrors the verification-code sweep cadence (lib/models/auth.coffee), just
# on a timer instead of "whenever a new one is issued" — a session has no
# equivalent write-heavy moment to piggyback on.
SWEEP_INTERVAL_MS = 60 * 60 * 1000

# A session with no cookie.expires (a non-persistent cookie) still has to
# leave the table eventually; SESSION_MAX_AGE is the same fallback express
# itself uses to compute that cookie's lifetime.
expiryOf = (sess) ->
  expires = sess.cookie?.expires
  if expires then new Date(expires).getTime() else Date.now() + config.SESSION_MAX_AGE


sweepExpired = ->
  db.prepare('DELETE FROM sessions WHERE expires < ?').run Date.now()


startSweep = (intervalMs = SWEEP_INTERVAL_MS) ->
  timer = setInterval ->
    try
      deleted = sweepExpired().changes
      console.log "Session sweep: removed #{deleted} expired session(s)" if deleted
    catch err
      console.error 'Session sweep failed:', err.message
  , intervalMs

  timer.unref()
  timer


class SQLiteSessionStore extends Store
  get: (sid, callback) ->
    try
      row = db.prepare('SELECT sess, expires FROM sessions WHERE sid = ?').get sid
      return callback null, null unless row
      return callback null, null if row.expires < Date.now()
      callback null, JSON.parse row.sess
    catch err
      callback err

  set: (sid, sess, callback) ->
    try
      db.prepare("""
        INSERT INTO sessions (sid, sess, expires) VALUES (?, ?, ?)
        ON CONFLICT(sid) DO UPDATE SET sess = excluded.sess, expires = excluded.expires
      """).run sid, JSON.stringify(sess), expiryOf(sess)
      callback null
    catch err
      callback err

  destroy: (sid, callback) ->
    try
      db.prepare('DELETE FROM sessions WHERE sid = ?').run sid
      callback null
    catch err
      callback err


module.exports = { SQLiteSessionStore, sweepExpired, startSweep }
