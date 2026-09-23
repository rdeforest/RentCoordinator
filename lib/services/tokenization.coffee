# PII Tokenization Service
# Converts sensitive strings (emails) to deterministic tokens
# Stores mapping in database with in-memory cache for performance

crypto = require 'crypto'

# Lazy load to avoid circular dependency
db = null

# In-memory caches for performance
tokenCache = new Map()  # value → token
valueCache = new Map()  # token → value

# Generate deterministic token from value using SHA-256
generateToken = (value) ->
  hash = crypto.createHash('sha256').update(value).digest('hex')
  "token:#{hash.substring(0, 16)}"

# Convert sensitive value to token
tokenize = (value) ->
  return value unless value  # Skip null/undefined

  # Lazy load database
  unless db
    schema = require '../db/schema.coffee'
    db = schema.db

  normalized = value.toLowerCase().trim()

  # Check cache first
  if tokenCache.has normalized
    return tokenCache.get normalized

  # Check database
  existing = db.prepare("""
    SELECT token FROM pii_tokens WHERE value = ?
  """).get normalized

  if existing
    token = existing.token
    tokenCache.set normalized, token
    valueCache.set token, normalized

    # Update access tracking
    db.prepare("""
      UPDATE pii_tokens
      SET last_accessed = CURRENT_TIMESTAMP,
          access_count = access_count + 1
      WHERE token = ?
    """).run token

    return token

  # Create new token
  token = generateToken normalized
  db.prepare("""
    INSERT INTO pii_tokens (token, value) VALUES (?, ?)
  """).run token, normalized

  tokenCache.set normalized, token
  valueCache.set token, normalized
  token

# The ordinary email shape, and nothing else. Anchoring the local part to
# address characters is what keeps a stack frame naming a scoped package —
# node_modules/@aws-sdk/client-s3/index.js — from matching: the character
# before its `@` is a slash, so there is no local part. The looser
# <non-space>@<non-space>.<letters> form replaced that whole frame with a
# token and filed the filesystem path in the PII store as somebody's address.
# @aws-sdk/client-s3 is a direct dependency, so it hit the traces that matter.
EMAIL_PATTERN = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g

# Tokenize every address *inside* a string, leaving the rest of the text
# alone. `tokenize` replaces the whole value, which is right for a metadata
# field that is an address and wrong for free text — a stack trace reduced to
# one token is unreadable, which is a different way of losing the log.
# Every match is a synchronous SQLite insert and two permanent cache entries,
# and this runs on the unauthenticated login path, where the input is
# whatever was posted. One request carrying a 50 kB field of addresses wrote
# three thousand rows, blocked the event loop long enough for other
# connections to see "database is locked", and produced a 73 kB log line.
# Free text gets a length cap and a match cap; a real address is far inside
# both, and the caps are visible in the output rather than silent.
MAX_TOKENIZE_LENGTH = 4096
MAX_TOKENIZE_MATCHES = 20

tokenizeEmbedded = (text) ->
  return text unless typeof text is 'string' and text.includes '@'

  if text.length > MAX_TOKENIZE_LENGTH
    text = text[0...MAX_TOKENIZE_LENGTH] + "…[truncated from #{text.length} chars]"

  matches = 0
  text.replace EMAIL_PATTERN, (match) ->
    matches += 1
    return '[redacted: too many addresses]' if matches > MAX_TOKENIZE_MATCHES
    tokenize match


TOKEN_PATTERN = /token:[0-9a-f]{16}/g

# Reverse of tokenizeEmbedded: restores every token found in a string.
detokenizeEmbedded = (text) ->
  return text unless typeof text is 'string' and text.includes 'token:'
  text.replace TOKEN_PATTERN, (match) -> detokenize match


# Convert token back to original value
detokenize = (token) ->
  return token unless token?.startsWith 'token:'

  # Lazy load database
  unless db
    schema = require '../db/schema.coffee'
    db = schema.db

  # Check cache first
  if valueCache.has token
    return valueCache.get token

  # Query database
  result = db.prepare("""
    SELECT value FROM pii_tokens WHERE token = ?
  """).get token

  if result
    valueCache.set token, result.value
    result.value
  else
    token  # Return as-is if not found

# Recursively detokenize all tokens in an object
detokenizeObject = (obj) ->
  return obj unless typeof obj is 'object' and obj?

  if Array.isArray obj
    return obj.map detokenizeObject

  result = {}
  for key, value of obj
    if typeof value is 'string'
      result[key] = detokenizeEmbedded value
    else if typeof value is 'object'
      result[key] = detokenizeObject value
    else
      result[key] = value
  result

module.exports = { tokenize, tokenizeEmbedded, detokenize, detokenizeEmbedded, detokenizeObject,
                   MAX_TOKENIZE_LENGTH, MAX_TOKENIZE_MATCHES }
