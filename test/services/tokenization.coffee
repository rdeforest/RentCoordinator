# lib/services/tokenization.coffee — the PII path.
#
# This runs on the unauthenticated login path and on every error the app logs,
# so it has two jobs that pull against each other: never emit an address, and
# never destroy the log it is protecting.

{ describe, it } = require 'node:test'
assert           = require 'node:assert/strict'

process.env.DB_PATH  ?= require('node:path').join require('node:os').tmpdir(), "rc-tok-#{process.pid}.db"
process.env.NODE_ENV ?= 'test'

schema = require '../../lib/db/schema.coffee'
tok    = require '../../lib/services/tokenization.coffee'
logger = require '../../lib/logger.coffee'

schema.db.exec """
  CREATE TABLE IF NOT EXISTS pii_tokens (
    token TEXT PRIMARY KEY, value TEXT NOT NULL UNIQUE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_accessed DATETIME DEFAULT CURRENT_TIMESTAMP,
    access_count INTEGER DEFAULT 0
  )
"""

tokenCount = -> schema.db.prepare('SELECT COUNT(*) AS n FROM pii_tokens').get().n
capture = (fn) ->
  lines = []
  original = console.error
  console.error = (line) -> lines.push line
  try fn() finally console.error = original
  lines.map JSON.parse


describe 'Tokenizing free text', ->
  it 'replaces the address and keeps the text around it', ->
    out = tok.tokenizeEmbedded 'UNIQUE constraint failed for robert@defore.st on insert'

    assert.match out, /^UNIQUE constraint failed for token:[0-9a-f]{16} on insert$/


  it 'leaves a scoped-package stack frame alone', ->
    # The pattern was widened once and matched node_modules/@aws-sdk/..., which
    # replaced the frame with a token and filed the path as somebody's address.
    frame = 'at Object.send (/srv/app/node_modules/@aws-sdk/client-s3/dist-cjs/index.js:12:9)'

    assert.equal tok.tokenizeEmbedded(frame), frame


  it 'does not shorten a long trace that holds no address', ->
    # Truncating before matching destroyed exactly the traces the pattern was
    # narrowed to protect — every frame through a scoped package contains '@'.
    trace = ("    at f#{i} (/app/node_modules/@scope/pkg/lib/x.js:#{i}:1)" for i in [1..400]).join '\n'

    assert.equal tok.tokenizeEmbedded(trace), trace
    assert.ok trace.length > 10000, 'and it really is long'


  it 'never leaves a partial address behind', ->
    # A byte-offset cut through 'example.com' still matched the pattern, so a
    # shortened address was tokenized and stored as though it were real.
    long = ('x' for _ in [1..5000]).join('') + ' alice@example.com'
    out  = tok.tokenizeEmbedded long

    assert.ok not out.includes('alice@example.c'), 'no truncated address survives'
    assert.equal tok.detokenize(out.match(/token:[0-9a-f]{16}/)[0]), 'alice@example.com'


describe 'The match budget', ->
  it 'bounds what one string can write', ->
    before  = tokenCount()
    payload = ("u#{i}@ex.com" for i in [0...500]).join ' '

    tok.tokenizeEmbedded payload, tok.newBudget()

    assert.ok tokenCount() - before <= tok.MAX_TOKENIZE_MATCHES,
      "500 addresses in one string wrote #{tokenCount() - before} rows"


  it 'is spent across a whole log record, not reset per field', ->
    # The cap was per string, so an object of a thousand short values cost a
    # thousand times the cap — the write amplification it was added to stop.
    before   = tokenCount()
    metadata = {}
    metadata["field#{i}"] = "contact m#{i}@ex.org please" for i in [0...200]

    capture -> logger.error 'test.budget', new Error('boom'), metadata

    assert.ok tokenCount() - before <= tok.MAX_TOKENIZE_MATCHES,
      "200 fields wrote #{tokenCount() - before} rows; the budget is per record"


  it 'still redacts visibly once the budget is gone', ->
    [record] = capture -> logger.error 'test.redact', new Error('x'),
      note: ("z#{i}@ex.net" for i in [0...40]).join ' '

    assert.match record.metadata.note, /redacted/
    assert.ok not record.metadata.note.includes('@ex.net'),
      'an address past the budget must not reach the log in clear'


describe 'Log record size', ->
  it 'caps a single value without needing an address to be present', ->
    [record] = capture -> logger.error 'test.size', new Error('x'), body: ('q' for _ in [1..50000]).join('')

    assert.ok record.metadata.body.length < 5000,
      "asyncRoute logs req.body, which body-parser will fill with 100 kB (got #{record.metadata.body.length})"
    assert.match record.metadata.body, /more chars/, 'and says it was cut'
