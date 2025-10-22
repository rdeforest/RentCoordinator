# tests/test-helper.coffee
# Helper to wait for server to be ready

export waitForServer = (url, maxAttempts = 30, delayMs = 100) ->
  for attempt in [1..maxAttempts]
    try
      response = await fetch url
      if response.ok
        console.log "✓ Server ready after #{attempt} attempts"
        return true
    catch err
      # Connection refused - server not ready yet
      if attempt < maxAttempts
        await new Promise (resolve) -> setTimeout(resolve, delayMs)
      else
        throw new Error "Server did not become ready after #{maxAttempts} attempts"

  return false
