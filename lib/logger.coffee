# Error-focused structured logger with PII tokenization
# Zero dependencies - wraps console.error with JSON output

tokenService = null  # Lazy load to avoid circular dependency

# A single log record must not be able to grow without bound: asyncRoute logs
# req.body, which body-parser will happily fill with 100 kB.
MAX_LOGGED_STRING = 4096

# tokenizeMetadata recurses one stack frame per level of nesting. A posted
# body can nest arrays far deeper than the call stack allows — a ~45,000-deep
# array crashed the process with a RangeError raised *inside* asyncRoute's own
# catch, which turned a request error into an unhandled rejection (bug 50).
# Nothing legitimate nests this deep; beyond it we stop descending and say so.
MAX_METADATA_DEPTH = 20


# The one place a string is checked for PII. Everything that reaches the log —
# metadata values, error messages, stack frames — goes through here, so a
# tokenizer improvement lands everywhere at once. Only the address is
# replaced; the text around it survives, or the log stops being a log.
#
# The budget is per log record. Passing it in is what keeps a thousand short
# strings from each costing the full per-string cap.
# Tokenize first, truncate second. Truncating first (the previous order) could
# cut a matched address in half, leaving a partial string — e.g.
# 'alice@example.co' out of 'alice@example.com' — that tokenizes as a real but
# wrong row in pii_tokens (bug 61). The match budget already bounds the cost
# of tokenizing the untruncated string; truncation here only bounds the
# record's size on the way out.
tokenizeString = (value, budget) ->
  return value unless typeof value is 'string'

  value = if value.includes '@'
    try
      tokenService ?= require './services/tokenization.coffee'
      tokenService.tokenizeEmbedded value, budget
    catch err
      # Tokenizing writes to SQLite, so logging a database failure can fail
      # here too. Losing the log entirely is the worse outcome; redact
      # visibly and say why, rather than letting the logger throw from
      # inside the error handler.
      value.replace /\S+@\S+/g, "[redacted: tokenizer failed: #{err.message}]"
  else
    value

  if value.length > MAX_LOGGED_STRING
    value = value[0...MAX_LOGGED_STRING] + "…[#{value.length - MAX_LOGGED_STRING} more chars]"

  value

# Recursively tokenize emails in metadata objects, spending one shared budget.
# Bounded in depth — see MAX_METADATA_DEPTH — so pathologically nested input
# is redacted rather than blowing the call stack.
tokenizeMetadata = (obj, budget, depth = 0) ->
  return obj unless typeof obj is 'object' and obj?

  if depth >= MAX_METADATA_DEPTH
    return '[redacted: max nesting depth exceeded]'

  if Array.isArray obj
    return obj.map (v) -> tokenizeMetadata v, budget, depth + 1

  result = {}
  for key, value of obj
    result[key] =
      if      typeof value is 'string' then tokenizeString   value, budget
      else if typeof value is 'object' then tokenizeMetadata value, budget, depth + 1
      else                                  value
  result


newBudget = ->
  tokenService ?= require './services/tokenization.coffee'
  tokenService.newBudget()

# Log an error with structured format
error = (operation, errorObj, metadata = {}, requestId = null) ->
  log =
    timestamp: new Date().toISOString()
    level:     'error'
    operation: operation

  budget = newBudget()

  log.requestId = requestId if requestId
  log.error     = tokenizeString (if errorObj.message then errorObj.message else String(errorObj)), budget
  log.metadata  = tokenizeMetadata metadata, budget
  log.stack     = tokenizeString errorObj.stack, budget if errorObj.stack

  console.error JSON.stringify log

# Log a warning (use sparingly - only for actual warnings)
warn = (operation, message, metadata = {}, requestId = null) ->
  budget = newBudget()

  log =
    timestamp: new Date().toISOString()
    level:     'warn'
    operation: operation
    message:   tokenizeString message, budget

  log.requestId = requestId if requestId
  log.metadata  = tokenizeMetadata metadata, budget

  console.error JSON.stringify log

# Log a client-reported error (from the browser beacon). Same JSON shape as
# server errors but tagged source:'client' so it's easy to grep/filter.
clientError = (info = {}, requestId = null) ->
  log =
    timestamp: new Date().toISOString()
    level:     'error'
    operation: 'client'
    source:    'client'

  log.requestId = requestId if requestId
  log.metadata  = tokenizeMetadata info, newBudget()

  console.error JSON.stringify log

module.exports = { error, warn, clientError }
