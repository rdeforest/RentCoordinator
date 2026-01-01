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
    if typeof value is 'string' and value.startsWith 'token:'
      result[key] = detokenize value
    else if typeof value is 'object'
      result[key] = detokenizeObject value
    else
      result[key] = value
  result

module.exports = { tokenize, detokenize, detokenizeObject }
