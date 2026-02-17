#!/usr/bin/env coffee
# Pre-deployment validation script
# Catches common errors before they reach production

fs   = require 'fs'
path = require 'path'

errors   = []
warnings = []

# ANSI colors
RED    = '\x1b[31m'
YELLOW = '\x1b[33m'
GREEN  = '\x1b[32m'
RESET  = '\x1b[0m'

log = (msg) -> console.log msg
error = (msg) -> errors.push msg
warn = (msg) -> warnings.push msg


# Extract table schemas from schema.coffee
extractSchema = ->
  schemaFile = fs.readFileSync 'lib/db/schema.coffee', 'utf8'
  tables = {}

  # Find CREATE TABLE statements
  tableRegex = /CREATE TABLE[^(]*\(([^;]+)\)/g
  tableNameRegex = /CREATE TABLE[^(]*\s+(\w+)\s*\(/

  matches = schemaFile.match /CREATE TABLE[^;]+;/g
  return tables unless matches

  for match in matches
    tableName = match.match(tableNameRegex)?[1]
    continue unless tableName

    # Extract column names
    columns = []
    columnLines = match.split('\n').filter (line) ->
      line.trim() and not line.includes('CREATE TABLE') and not line.includes('UNIQUE')

    for line in columnLines
      # Match column name (first word after whitespace)
      columnMatch = line.trim().match /^(\w+)\s+/
      columns.push columnMatch[1] if columnMatch?[1]

    tables[tableName] = columns

  return tables


# Find all SQL queries in a file
findSQLQueries = (filepath) ->
  return [] unless fs.existsSync filepath
  content = fs.readFileSync filepath, 'utf8'
  queries = []

  # Find SQL in prepare() and exec() calls
  sqlRegex = /(?:prepare|exec)\s*\(?(?:"""|\"|')\s*(SELECT|INSERT|UPDATE|DELETE)[^"']*/gi

  match = sqlRegex.exec content
  while match
    queries.push
      sql:  match[0]
      line: content.substring(0, match.index).split('\n').length
      type: match[1]
    match = sqlRegex.exec content

  return queries


# Extract table and column references from SQL
extractReferences = (sql) ->
  refs = {}

  # Extract FROM/JOIN table references
  tableMatches = sql.match /(?:FROM|JOIN)\s+(\w+)/gi
  if tableMatches
    for match in tableMatches
      tableName = match.replace(/(?:FROM|JOIN)\s+/i, '').trim()
      refs[tableName] ?= []

  # Extract column references (word.word pattern or SELECT word)
  columnMatches = sql.match /(?:SELECT|WHERE|SET|ON)\s+[^(]*?\b(\w+)\.(\w+)/gi
  if columnMatches
    for match in columnMatches
      parts = match.match /(\w+)\.(\w+)/
      if parts
        table = parts[1]
        column = parts[2]
        refs[table] ?= []
        refs[table].push column unless column in refs[table] or column is '*'

  # Extract UPDATE table references
  updateMatch = sql.match /UPDATE\s+(\w+)/i
  if updateMatch
    tableName = updateMatch[1]
    refs[tableName] ?= []

    # Extract SET columns
    setMatch = sql.match /SET\s+([^WHERE]+)/i
    if setMatch
      setColumns = setMatch[1].match /(\w+)\s*=/g
      if setColumns
        for col in setColumns
          columnName = col.replace(/\s*=\s*/, '').trim()
          refs[tableName].push columnName unless columnName in refs[tableName]

  return refs


# Validate database schema compatibility
validateSchema = ->
  log "\n#{GREEN}→${RESET} Validating database schema..."
  schema = extractSchema()

  log "  Found tables: #{Object.keys(schema).join(', ')}"

  # Check all .coffee files in lib/
  coffeeFiles = []
  findCoffeeFiles = (dir) ->
    return unless fs.existsSync dir
    for item in fs.readdirSync dir, withFileTypes: true
      filepath = path.join dir, item.name
      if item.isDirectory()
        findCoffeeFiles filepath
      else if item.name.endsWith '.coffee'
        coffeeFiles.push filepath

  findCoffeeFiles 'lib'

  issueCount = 0

  for filepath in coffeeFiles
    queries = findSQLQueries filepath
    continue unless queries.length > 0

    for query in queries
      refs = extractReferences query.sql

      for tableName, columns of refs
        # Check if table exists
        unless schema[tableName]
          error "#{filepath}:#{query.line} - Table '#{tableName}' does not exist"
          issueCount++
          continue

        # Check if columns exist
        for column in columns
          unless column in schema[tableName]
            error "#{filepath}:#{query.line} - Column '#{tableName}.#{column}' does not exist"
            error "  Available columns: #{schema[tableName].join(', ')}"
            issueCount++

  if issueCount is 0
    log "  ${GREEN}✓${RESET} Schema validation passed"
  else
    log "  ${RED}✗${RESET} Found #{issueCount} schema issue(s)"


# Validate API endpoint contracts
validateAPIContracts = ->
  log "\n${GREEN}→${RESET} Validating API contracts..."

  # Find all route definitions
  routes = {}

  # Parse routing files
  routeFiles = [
    'lib/routing.coffee'
    'lib/routes/rent.coffee'
    'lib/routes/work.coffee'
    'lib/routes/payment.coffee'
    'lib/routes/payments.coffee'
    'lib/routes/auth.coffee'
  ]

  for filepath in routeFiles
    continue unless fs.existsSync filepath
    content = fs.readFileSync filepath, 'utf8'

    # Find app.get/post/put/delete definitions
    routeRegex = /app\.(get|post|put|delete)\s+['"]([^'"]+)['"]/g
    match = routeRegex.exec content
    while match
      method = match[1].toUpperCase()
      endpoint = match[2]
      routes["#{method} #{endpoint}"] = filepath
      match = routeRegex.exec content

  log "  Found #{Object.keys(routes).length} API endpoints"

  # Find all fetch() calls in client code
  clientFiles = []
  if fs.existsSync 'static/coffee'
    for file in fs.readdirSync 'static/coffee'
      if file.endsWith '.coffee'
        clientFiles.push path.join('static/coffee', file)

  issueCount = 0

  for filepath in clientFiles
    content = fs.readFileSync filepath, 'utf8'

    # Find fetch() calls
    fetchRegex = /fetch\s+['"]([^'"]+)['"]/g
    match = fetchRegex.exec content
    while match
      endpoint = match[1]
      lineNum = content.substring(0, match.index).split('\n').length

      # Determine method (look for method: in the fetch options)
      methodMatch = content.substring(match.index, match.index + 200).match /method:\s*['"](\w+)['"]/
      method = if methodMatch then methodMatch[1].toUpperCase() else 'GET'

      # Check if endpoint exists (accounting for dynamic parts)
      routeKey = "#{method} #{endpoint}"

      # Try to match with parameter placeholders
      found = false
      for route of routes
        # Convert :param to regex pattern
        pattern = route.replace(/:\w+/g, '[^/]+')
        regex = new RegExp "^#{pattern}$"
        if regex.test routeKey
          found = true
          break

      unless found
        warn "#{filepath}:#{lineNum} - Fetch to undefined endpoint: #{method} #{endpoint}"
        issueCount++

      match = fetchRegex.exec content

  if issueCount is 0
    log "  ${GREEN}✓${RESET} API contract validation passed"
  else
    log "  ${YELLOW}⚠${RESET} Found #{issueCount} potential API issue(s)"


# Check for common code patterns
validateCodePatterns = ->
  log "\n${GREEN}→${RESET} Checking code patterns..."

  # Check for event listeners in loops without closure
  clientFiles = []
  if fs.existsSync 'static/coffee'
    for file in fs.readdirSync 'static/coffee'
      if file.endsWith '.coffee'
        clientFiles.push path.join('static/coffee', file)

  issueCount = 0

  for filepath in clientFiles
    content = fs.readFileSync filepath, 'utf8'
    lines = content.split '\n'

    inLoop = false
    loopDepth = 0

    for line, i in lines
      lineNum = i + 1

      # Track loop depth
      if line.match /^\s*for\s+\w+\s+in\s+/
        inLoop = true
        loopDepth++

      # Check for addEventListener in loop without 'do'
      if inLoop and line.match /addEventListener\s+['"]/
        # Check if previous line has 'do (...) ->'
        prevLine = if i > 0 then lines[i - 1] else ''
        unless prevLine.match(/do\s+\([^)]+\)\s*->/) or line.match(/do\s+\([^)]+\)\s*->/)
          warn "#{filepath}:#{lineNum} - addEventListener in loop without 'do' closure (potential closure bug)"
          issueCount++

      # Decrease depth when leaving loop (approximate)
      if line.match /^\s{0,#{loopDepth * 2}}\S/ and loopDepth > 0
        loopDepth--
        inLoop = loopDepth > 0

  if issueCount is 0
    log "  ${GREEN}✓${RESET} Code pattern validation passed"
  else
    log "  ${YELLOW}⚠${RESET} Found #{issueCount} potential code pattern issue(s)"


# Main validation
main = ->
  log "\n╔═══════════════════════════════════════╗"
  log "║  Pre-Deployment Validation            ║"
  log "╔═══════════════════════════════════════╝"

  validateSchema()
  validateAPIContracts()
  validateCodePatterns()

  # Print summary
  log "\n╔═══════════════════════════════════════╗"
  log "║  Validation Summary                   ║"
  log "╚═══════════════════════════════════════╝"

  if errors.length > 0
    log "\n${RED}ERRORS:${RESET}"
    for err in errors
      log "  ${RED}✗${RESET} #{err}"

  if warnings.length > 0
    log "\n${YELLOW}WARNINGS:${RESET}"
    for warn in warnings
      log "  ${YELLOW}⚠${RESET} #{warn}"

  if errors.length is 0 and warnings.length is 0
    log "\n${GREEN}✓ All validations passed!${RESET}"
    process.exit 0
  else if errors.length > 0
    log "\n${RED}✗ Validation failed with #{errors.length} error(s)${RESET}"
    process.exit 1
  else
    log "\n${YELLOW}⚠ Validation passed with #{warnings.length} warning(s)${RESET}"
    process.exit 0


main()
