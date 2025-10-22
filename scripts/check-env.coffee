# scripts/check-env.coffee
# Audits the development environment for known issues

{ execSync } = await import('child_process')
fs = await import('fs')
path = await import('path')

issues = []
warnings = []

# Check for processes on known ports
checkPort = (port, description) ->
  try
    output = execSync("lsof -ti :#{port}", encoding: 'utf8').trim()
    if output
      pids = output.split('\n')
      issues.push "Port #{port} (#{description}) is in use by PIDs: #{pids.join(', ')}"
      issues.push "  Fix: kill -9 #{pids.join(' ')}"
  catch err
    # Port is free (lsof returns non-zero if nothing found)

console.log 'Checking development environment...\n'

# Check development/test ports
checkPort 3000, 'dev server'
checkPort 3001, 'alternate dev'
checkPort 3999, 'test server'

# Check for stray test databases
try
  files = fs.readdirSync('.')
  testDbs = files.filter (f) -> f.match(/^test.*\.db$/)
  if testDbs.length > 0
    warnings.push "Found #{testDbs.length} test database(s): #{testDbs.join(', ')}"
    warnings.push "  Fix: rm -f test-*.db"
catch err
  # Directory read error

# Check for unexpected .js files in source directories
checkUnexpectedJs = (dir) ->
  return unless fs.existsSync(dir)
  try
    files = fs.readdirSync(dir, withFileTypes: true)
    for file in files
      if file.isDirectory()
        checkUnexpectedJs path.join(dir, file.name)
      else if file.name.endsWith('.js') and not file.name.endsWith('.test.js')
        # Check if there's a corresponding .coffee file
        coffeePath = path.join(dir, file.name.replace(/\.js$/, '.coffee'))
        if fs.existsSync(coffeePath)
          warnings.push "Stray .js file with .coffee source: #{path.join(dir, file.name)}"
  catch err
    # Ignore errors

checkUnexpectedJs 'lib'
checkUnexpectedJs 'scripts'
checkUnexpectedJs 'tests'

# Check for background bash processes from this project
try
  output = execSync('ps aux | grep -E "npm.*run.*(dev|start)|node.*main.js" | grep -v grep', encoding: 'utf8').trim()
  if output
    lines = output.split('\n').filter (l) -> l.trim()
    if lines.length > 0
      warnings.push "Found #{lines.length} Node.js process(es) that might be from this project:"
      for line in lines
        # Extract PID (second field)
        pid = line.split(/\s+/)[1]
        cmd = line.split(/\s+/).slice(10).join(' ').substring(0, 80)
        warnings.push "  PID #{pid}: #{cmd}"
catch err
  # No processes found or grep failed

# Report results
console.log '\n=== ISSUES (must fix) ==='
if issues.length is 0
  console.log '✓ No issues found'
else
  for issue in issues
    console.log "✗ #{issue}"

console.log '\n=== WARNINGS (should clean up) ==='
if warnings.length is 0
  console.log '✓ No warnings'
else
  for warning in warnings
    console.log "⚠ #{warning}"

console.log '\n=== SUMMARY ==='
console.log "Issues: #{issues.length}"
console.log "Warnings: #{warnings.length}"

if issues.length > 0
  console.log '\nEnvironment has issues that should be fixed before proceeding.'
  process.exit 1
else if warnings.length > 0
  console.log '\nEnvironment is usable but could be cleaner.'
  process.exit 0
else
  console.log '\n✓ Environment is clean!'
  process.exit 0
