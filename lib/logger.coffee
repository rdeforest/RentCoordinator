# Error-focused structured logger with PII tokenization
# Zero dependencies - wraps console.error with JSON output

tokenService = null  # Lazy load to avoid circular dependency

# The one place a string is checked for PII. Everything that reaches the log —
# metadata values, error messages, stack frames — goes through here, so a
# tokenizer improvement lands everywhere at once. Only the address is
# replaced; the text around it survives, or the log stops being a log.
tokenizeString = (value) ->
  return value unless typeof value is 'string' and value.includes '@'

  try
    tokenService ?= require './services/tokenization.coffee'
    tokenService.tokenizeEmbedded value
  catch err
    # Tokenizing writes to SQLite, so logging a database failure can fail
    # here too. Losing the log entirely is the worse outcome; redact visibly
    # and say why, rather than letting the logger throw from inside the
    # error handler.
    value.replace /\S+@\S+/g, "[redacted: tokenizer failed: #{err.message}]"

# Recursively tokenize emails in metadata objects
tokenizeMetadata = (obj) ->
  return obj unless typeof obj is 'object' and obj?

  if Array.isArray obj
    return obj.map tokenizeMetadata

  result = {}
  for key, value of obj
    if typeof value is 'string'
      result[key] = tokenizeString value
    else if typeof value is 'object'
      result[key] = tokenizeMetadata value
    else
      result[key] = value
  result

# Log an error with structured format
error = (operation, errorObj, metadata = {}, requestId = null) ->
  log =
    timestamp: new Date().toISOString()
    level:     'error'
    operation: operation

  log.requestId = requestId if requestId
  log.error     = tokenizeString (if errorObj.message then errorObj.message else String(errorObj))
  log.metadata  = tokenizeMetadata metadata
  log.stack     = tokenizeString errorObj.stack if errorObj.stack

  console.error JSON.stringify log

# Log a warning (use sparingly - only for actual warnings)
warn = (operation, message, metadata = {}, requestId = null) ->
  log =
    timestamp: new Date().toISOString()
    level:     'warn'
    operation: operation
    message:   tokenizeString message

  log.requestId = requestId if requestId
  log.metadata  = tokenizeMetadata metadata

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
  log.metadata  = tokenizeMetadata info

  console.error JSON.stringify log

module.exports = { error, warn, clientError }
