{ execSync } = await import 'child_process'
fs           = await import 'fs'
path         = await import 'path'


pattern = process.argv[2]

unless pattern
  console.log 'Usage: npm run test-focus <pattern>'
  console.log ''
  console.log 'Examples:'
  console.log '  npm run test-focus timer        # Runs tests matching "timer"'
  console.log '  npm run test-focus rent_test    # Runs tests/rent_test.coffee'
  console.log '  npm run test-focus timer-start  # Runs tests/timer-start.test.coffee'
  console.log ''
  process.exit 1

findTests = (pattern) ->
  tests = []

  searchDir = (dir) ->
    return unless fs.existsSync dir

    files = fs.readdirSync dir, withFileTypes: true
    for file in files
      fullPath = path.join dir, file.name

      if file.isDirectory()
        searchDir fullPath
      else if file.name.endsWith('.test.coffee') or file.name.endsWith('_test.coffee')
        if file.name.includes(pattern) or fullPath.includes(pattern)
          tests.push fullPath

  searchDir 'tests'
  tests


matchingTests = findTests pattern


if matchingTests.length is 0
  console.log "No tests found matching pattern: #{pattern}"
  console.log ''
  console.log 'Available test files:'

  allTests = findTests ''
  for test in allTests
    console.log "  - #{test}"

  process.exit 1


console.log "Found #{matchingTests.length} test(s):"
for test in matchingTests
  console.log "  - #{test}"
console.log ''


console.log 'Building project...'
try
  execSync 'npm run build', stdio: 'inherit'
catch err
  console.error 'Build failed!'
  process.exit 1

console.log ''


for testFile in matchingTests
  compiledPath = testFile.replace(/^tests\//, 'dist/tests/').replace /\.coffee$/, '.js'

  console.log "Running: #{testFile}"
  console.log "Compiled: #{compiledPath}"
  console.log '─'.repeat 60

  try
    execSync "node --test #{compiledPath}", stdio: 'inherit'
    console.log '─'.repeat 60
    console.log "✓ #{testFile} passed"
    console.log ''

  catch err
    console.log '─'.repeat 60
    console.error "✗ #{testFile} failed"
    console.log ''
    process.exit 1


console.log "All tests passed! (#{matchingTests.length} file(s))"
