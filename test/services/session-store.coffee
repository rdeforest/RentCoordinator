# Bug 65 — unit coverage for the SQLite-backed session store. The
# integration test (test/integration/session-persistence.coffee) proves the
# thing this is actually for (a session survives a restart); these prove the
# store's own contract against express-session's Store interface.

fs   = require 'node:fs'
os   = require 'node:os'
path = require 'node:path'

DB_PATH = path.join fs.mkdtempSync(path.join os.tmpdir(), 'rc-session-store-'), 'test.db'
process.env.DB_PATH  = DB_PATH
process.env.NODE_ENV = 'test'

{ describe, it, before, after } = require 'node:test'
assert                          = require 'node:assert/strict'
schema                          = require '../../lib/db/schema.coffee'
{ SQLiteSessionStore, sweepExpired } = require '../../lib/services/session-store.coffee'

{ db } = schema

before -> await schema.initialize()
after  -> fs.rmSync path.dirname(DB_PATH), recursive: true, force: true

# Store methods take Node-style (err, result) callbacks; wrap them so tests
# can await instead.
call = (fn, args...) ->
  new Promise (resolve, reject) ->
    fn args..., (err, result) ->
      if err then reject err else resolve result


makeSession = (maxAgeMs) ->
  cookie: { expires: new Date(Date.now() + maxAgeMs).toISOString() }
  authenticated: true
  email: 'robert@defore.st'


describe 'SQLiteSessionStore', ->
  store = null

  before -> store = new SQLiteSessionStore()

  it 'set then get round-trips the session', ->
    sess = makeSession 60_000
    await call store.set.bind(store), 'sid-roundtrip', sess

    got = await call store.get.bind(store), 'sid-roundtrip'
    assert.equal got.authenticated, true
    assert.equal got.email, 'robert@defore.st'

  it 'get returns null for a session that was never stored', ->
    got = await call store.get.bind(store), 'sid-never-existed'
    assert.equal got, null

  it 'get does not return an expired session', ->
    sess = makeSession -1000  # already expired
    await call store.set.bind(store), 'sid-expired', sess

    got = await call store.get.bind(store), 'sid-expired'
    assert.equal got, null, 'an expired row must read back as absent'

  it 'touch extends a session past its original expiry', ->
    sess = makeSession 1000
    await call store.set.bind(store), 'sid-touch', sess

    extended = makeSession 60_000
    await call store.touch.bind(store), 'sid-touch', extended

    row = db.prepare('SELECT expires FROM sessions WHERE sid = ?').get 'sid-touch'
    assert.ok row.expires > Date.now() + 30_000,
      'touch should have pushed expires out to the extended cookie'

  it 'destroy removes the row', ->
    sess = makeSession 60_000
    await call store.set.bind(store), 'sid-destroy', sess
    await call store.destroy.bind(store), 'sid-destroy'

    row = db.prepare('SELECT sid FROM sessions WHERE sid = ?').get 'sid-destroy'
    assert.equal row, undefined

  it 'a session with no cookie.expires falls back to SESSION_MAX_AGE, not an immediate expiry', ->
    config = require '../../lib/config.coffee'
    await call store.set.bind(store), 'sid-no-expires', { authenticated: true, cookie: {} }

    row = db.prepare('SELECT expires FROM sessions WHERE sid = ?').get 'sid-no-expires'
    assert.ok row.expires > Date.now() + config.SESSION_MAX_AGE - 5000,
      'no cookie.expires should fall back to now + SESSION_MAX_AGE'


describe 'sweepExpired', ->
  it 'deletes only expired rows, leaving live ones alone', ->
    live    = { sid: 'sid-sweep-live',    sess: '{}', expires: Date.now() + 60_000 }
    expired = { sid: 'sid-sweep-expired', sess: '{}', expires: Date.now() - 60_000 }

    insert = db.prepare 'INSERT INTO sessions (sid, sess, expires) VALUES (?, ?, ?)'
    insert.run live.sid, live.sess, live.expires
    insert.run expired.sid, expired.sess, expired.expires

    result = sweepExpired()
    assert.ok result.changes >= 1, 'sweep should have removed at least the expired row'

    assert.ok db.prepare('SELECT sid FROM sessions WHERE sid = ?').get(live.sid),
      'a live row must survive the sweep'
    assert.equal db.prepare('SELECT sid FROM sessions WHERE sid = ?').get(expired.sid), undefined,
      'an expired row must not survive the sweep'
