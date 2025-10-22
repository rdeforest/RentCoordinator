# Quick diagnostic - test if fetch works
console.log 'Testing fetch...'

try
  response = await fetch 'http://localhost:3999/health'
  console.log 'Response status:', response.status
  data = await response.json()
  console.log 'Response data:', data
  console.log '✓ Fetch works!'
catch err
  console.error '✗ Fetch failed:', err.message
  console.error '  Full error:', err

process.exit(0)
