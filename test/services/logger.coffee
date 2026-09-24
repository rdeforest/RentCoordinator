# Bugs 50 / 61 — the error logger itself must not be a way to crash the
# process or corrupt the PII store.
#
# The depth-bound cases run out-of-process (via `coffee -e`) where a run
# against a deeply nested object would actually crash: this file's own
# process must not go down proving that logger.error doesn't throw.

{ describe, it }  = require 'node:test'
assert            = require 'node:assert/strict'
{ spawnSync }     = require 'node:child_process'
fs                = require 'node:fs'
path              = require 'node:path'

ROOT = path.join __dirname, '..', '..'

process.on 'exit', ->
  for name in fs.readdirSync __dirname when name.startsWith '.logger-tok-'
    fs.rmSync path.join(__dirname, name), force: true

# execFileSync only returns stdout; console.error (what logger writes to)
# goes to stderr, so the child's output has to be captured explicitly.
runChild = (script) ->
  result = spawnSync 'coffee', ['-e', "#{script}; console.log('SENTINEL-REACHED')"],
    cwd:      ROOT
    env:      Object.assign {}, process.env, NODE_ENV: 'test'
    encoding: 'utf8'

  "#{result.stdout}#{result.stderr}"


describe 'logger.error survives pathological input (bug 50)', ->
  it 'does not crash on a deeply nested array in metadata', ->
    # Mirrors the real report: a ~45,000-deep nested array posted as req.body,
    # logged from inside asyncRoute's catch. Before the depth bound, this blew
    # the call stack with a RangeError raised from *inside* the error
    # handler's own catch block — the thing this test proves cannot happen
    # again.
    script = """
      logger = require './lib/logger.coffee'
      deep = node = []
      for i in [0...45000]
        node.push []
        node = node[0]
      logger.error 'test.deepNesting', new Error('boom'), { body: deep }
    """

    output = runChild script
    assert.match output, /SENTINEL-REACHED/,
      "the process must survive logging deeply nested metadata:\n#{output}"

  it 'redacts nesting beyond the depth bound rather than reproducing it', ->
    script = """
      logger = require './lib/logger.coffee'
      marker = node = {}
      for i in [0...30]
        node.next = {}
        node = node.next
      logger.error 'test.depthMarker', new Error('boom'), { chain: marker }
    """

    output = runChild script
    assert.match output, /max nesting depth exceeded/,
      'metadata beyond the bound should be replaced with a marker, not omitted silently'


describe 'logger tokenizes before truncating (bug 61)', ->
  scratchDbCount = 0

  # Computed once per call, entirely in this (parent) process — no need for
  # the child to interpolate its own pid, which single-quoting it here
  # previously defeated anyway, leaving a literal "#{process.pid}" filename
  # on disk instead of a real one.
  dbScript = (body) ->
    scratchDbCount += 1
    dbPath = path.join ROOT, 'test', 'services',
      ".logger-tok-#{process.pid}-#{scratchDbCount}.db"

    """
    process.env.DB_PATH = '#{dbPath}'
    schema = require './lib/db/schema.coffee'
    schema.db.exec \"\"\"
      CREATE TABLE IF NOT EXISTS pii_tokens (
        token TEXT PRIMARY KEY, value TEXT NOT NULL UNIQUE,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        last_accessed DATETIME DEFAULT CURRENT_TIMESTAMP,
        access_count INTEGER DEFAULT 0
      )
    \"\"\"
    tokenization = require './lib/services/tokenization.coffee'
    logger       = require './lib/logger.coffee'
    #{body}
  """

  logLineFrom = (output) ->
    line = output.split('\n').find (l) -> (try JSON.parse(l).error catch then null)?
    JSON.parse line if line

  it 'does not tokenize a fragment left by truncating first, at the exact boundary that used to produce one', ->
    # Padding chosen so truncate-then-tokenize (the bug) leaves exactly
    # 'alice@example.co' — one character short of the real address, but a
    # complete-looking one (the TLD is still 2+ letters) — so the old order
    # tokenized it as a real, distinct, wrong row. This is the boundary case;
    # the token substituted here can itself land right at the truncation
    # cutoff, so this case only checks the fragment is absent, not that the
    # replacement token survives whole (the next test covers that).
    output = runChild dbScript """
      padding = 'x'.repeat 4079
      message = padding + ' ' + 'alice@example.com'
      logger.error 'test.tokenizeBeforeTruncate', new Error(message)
      console.log 'PARTIAL:' + tokenization.tokenize('alice@example.co')
    """

    record       = logLineFrom output
    partialToken = (output.split('\n').find (l) -> l.startsWith 'PARTIAL:')?.slice 8

    assert.ok record, "expected a JSON log line in output:\n#{output}"
    assert.ok partialToken

    assert.ok not record.error.includes('alice@example.com'),
      'the real address must not appear in the log line'
    assert.ok not record.error.includes(partialToken),
      'truncating first would have tokenized a one-character-short fragment ' +
      'as if it were a different, real address — a wrong row in pii_tokens'

  it 'tokenizes the whole address, unmutilated, away from the size boundary', ->
    output = runChild dbScript """
      message = 'contact alice@example.com for details'
      logger.error 'test.tokenizeWhole', new Error(message)
      console.log 'FULL:' + tokenization.tokenize('alice@example.com')
    """

    record    = logLineFrom output
    fullToken = (output.split('\n').find (l) -> l.startsWith 'FULL:')?.slice 5

    assert.ok record, "expected a JSON log line in output:\n#{output}"
    assert.ok fullToken

    assert.ok not record.error.includes('alice@example.com'),
      'the real address must not appear in the log line'
    assert.ok record.error.includes(fullToken),
      'the whole address must have been tokenized as one match, not split by an earlier truncation'
