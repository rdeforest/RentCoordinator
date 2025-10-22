#!/usr/bin/env coffee

# scripts/test-integration.coffee
# Integration test runner with environment checking and cleanup

{ execSync } = await import('child_process')
fs = await import('fs')
path = await import('path')

console.log 'Integration Test Runner'
console.log '======================='
console.log ''

# Test directory configuration
TEST_TMP_DIR = '/tmp/rent-coordinator-tests'

# Ensure test tmp directory exists and is clean
prepareTestDirectory = ->
  try
    # Remove entire test directory if it exists
    if fs.existsSync(TEST_TMP_DIR)
      fileCount = fs.readdirSync(TEST_TMP_DIR).length
      if fileCount > 0
        console.log "Cleaning test directory (#{fileCount} file(s))..."
      fs.rmSync(TEST_TMP_DIR, recursive: true, force: true)

    # Create fresh test directory
    fs.mkdirSync(TEST_TMP_DIR, recursive: true)
    console.log "Prepared test directory: #{TEST_TMP_DIR}"
    console.log ''
  catch err
    console.error "Error preparing test directory: #{err.message}"
    process.exit 1

# Clean up test directory
cleanupTestDirectory = ->
  try
    if fs.existsSync(TEST_TMP_DIR)
      fs.rmSync(TEST_TMP_DIR, recursive: true, force: true)
      console.log "Cleaned up test directory"
  catch err
    console.error "Warning: Failed to clean up test directory: #{err.message}"

# Check for port conflicts
checkPort = (port) ->
  try
    output = execSync("lsof -ti :#{port}", encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore']).trim()
    if output
      pids = output.split('\n')
      console.error "ERROR: Port #{port} is in use by PIDs: #{pids.join(', ')}"
      console.error "Fix: kill -9 #{pids.join(' ')}"
      return false
  catch err
    # Port is free (lsof returns non-zero if nothing found)
  return true

# Pre-flight checks
console.log 'Pre-flight checks...'
prepareTestDirectory()

unless checkPort(3999)
  console.error ''
  console.error 'Environment check failed. Please fix issues above.'
  process.exit 1

console.log '✓ Environment is clean'
console.log ''

# Build client-side JavaScript only
console.log 'Building client-side JavaScript...'
try
  execSync 'coffee -b -c -o static/js static/coffee', stdio: 'inherit'
catch err
  console.error 'Build failed!'
  process.exit 1

console.log ''

# Find integration test files
findTestFiles = ->
  testFiles = []
  searchDir = (dir) ->
    return unless fs.existsSync(dir)
    files = fs.readdirSync(dir, withFileTypes: true)
    for file in files
      fullPath = "#{dir}/#{file.name}"
      if file.isDirectory()
        searchDir fullPath
      else if file.name.endsWith('.coffee') and not file.name.match(/^(helper|server|fetch)\.coffee$/)
        testFiles.push fullPath
  searchDir 'test/integration'
  testFiles

testFiles = findTestFiles()

if testFiles.length is 0
  console.error 'No integration test files found!'
  process.exit 1

console.log "Found #{testFiles.length} integration test file(s):"
for file in testFiles
  console.log "  - #{file}"
console.log ''

# Run integration tests
console.log 'Running integration tests...'
console.log ''

try
  # Run tests sequentially with coffee
  for testFile in testFiles
    console.log "Running: #{testFile}"
    console.log '─'.repeat(60)
    execSync "coffee #{testFile}", stdio: 'inherit'
    console.log '─'.repeat(60)
    console.log ''

  console.log '✓ All integration tests passed!'
  exitCode = 0

catch err
  console.log ''
  console.error '✗ Integration tests failed'
  exitCode = 1

# Cleanup after tests
console.log ''
console.log 'Post-test cleanup...'
cleanupTestDirectory()
console.log ''

process.exit exitCode
