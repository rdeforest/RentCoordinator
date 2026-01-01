# Error-focused structured logger with PII tokenization
# Zero dependencies - wraps console.error with JSON output

tokenService = null  # Lazy load to avoid circular dependency

# Recursively tokenize emails in metadata objects
tokenizeMetadata = (obj) ->
  return obj unless typeof obj is 'object' and obj?

  # Lazy load tokenization service
  tokenService ?= require './services/tokenization.coffee'

  if Array.isArray obj
    return obj.map tokenizeMetadata

  result = {}
  for key, value of obj
    if typeof value is 'string' and value.includes '@'
      result[key] = tokenService.tokenize value
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
  log.error     = if errorObj.message then errorObj.message else String(errorObj)
  log.metadata  = tokenizeMetadata metadata
  log.stack     = errorObj.stack if errorObj.stack

  console.error JSON.stringify log

# Log a warning (use sparingly - only for actual warnings)
warn = (operation, message, metadata = {}, requestId = null) ->
  log =
    timestamp: new Date().toISOString()
    level:     'warn'
    operation: operation
    message:   message

  log.requestId = requestId if requestId
  log.metadata  = tokenizeMetadata metadata

  console.error JSON.stringify log

module.exports = { error, warn }
