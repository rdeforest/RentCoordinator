#!/usr/bin/env coffee
# scripts/restore-work-logs.coffee
#
# Extracts work entries from a saved HTML tab and restores them to the database.
#
# Usage:
#   coffee scripts/restore-work-logs.coffee [--dry-run] [HTML_FILE]
#
# Options:
#   --dry-run   Show what would be inserted without actually inserting
#   HTML_FILE   Path to saved HTML (default: saved-tab/Work Management - Tenant Coordinator.html)
#
# The script uses the original UUIDs from the HTML (editWork/deleteWork onclick handlers)
# for idempotency - entries that already exist in the DB are skipped.
#
# After inserting, re-runs rent period calculation for all affected lyndzie months.

{ readFileSync }  = require 'fs'
{ join }          = require 'path'
{ DatabaseSync }  = require 'node:sqlite'

args    = process.argv.slice 2
dryRun  = '--dry-run' in args
htmlArg = args.find (a) -> not a.startsWith '--'

HTML_PATH = htmlArg or join __dirname, '..', 'saved-tab', 'Work Management - Tenant Coordinator.html'
DB_PATH   = process.env.DB_PATH or join __dirname, '..', 'tenant-coordinator.db'

# ============================================================
# Date parsing: "M/D/YYYY HH:MM AM/PM" → ISO string
# ============================================================

parseDate = (str) ->
  m = str.trim().match /^(\d+)\/(\d+)\/(\d+)\s+(\d+):(\d+)\s+(AM|PM)$/i
  unless m
    throw new Error "Cannot parse date: '#{str}'"

  [_, mon, day, yr, hr, min, ampm] = m
  h = parseInt hr
  h = 0  if h is 12 and ampm.toUpperCase() is 'AM'
  h += 12 if ampm.toUpperCase() is 'PM' and h isnt 12

  # Store as local-time ISO (matches how the UI entered the original data)
  d = new Date parseInt(yr), parseInt(mon) - 1, parseInt(day), h, parseInt(min)
  d.toISOString()

parseDurationMinutes = (str) ->
  m = str.trim().match /^([\d.]+)\s+hours?$/i
  unless m
    throw new Error "Cannot parse duration: '#{str}'"
  Math.round parseFloat(m[1]) * 60

# ============================================================
# HTML parsing
# ============================================================

extractEntries = (html) ->
  entries = []

  # Match each <tr> block containing work data
  trPattern = /<tr>([\s\S]*?)<\/tr>/gi

  while (trMatch = trPattern.exec html)?
    row = trMatch[1]

    # Extract individual cells
    cells = []
    cellPattern = /<td[^>]*>([\s\S]*?)<\/td>/gi
    while (cellMatch = cellPattern.exec row)?
      cells.push cellMatch[1].replace(/<[^>]+>/g, '').trim()

    # Need 4 data cells + 1 actions cell → 5 total
    continue unless cells.length >= 4

    [dateStr, worker, durationStr, description] = cells

    # Validate worker field looks right
    continue unless worker in ['robert', 'lyndzie']

    # Extract UUID from editWork('...') in actions column
    uuidMatch = row.match /editWork\('([0-9a-f-]{36})'\)/i
    continue unless uuidMatch
    uuid = uuidMatch[1]

    try
      startTime = parseDate dateStr
      duration  = parseDurationMinutes durationStr
      endTime   = new Date(new Date(startTime).getTime() + duration * 60 * 1000).toISOString()

      entries.push { uuid, worker, startTime, endTime, duration, description, dateStr }
    catch err
      console.warn "  WARN: Skipping row (#{err.message}) — raw: #{dateStr} / #{durationStr}"

  entries

# ============================================================
# Rent period recalculation (mirrors POST /work-logs logic)
# ============================================================

recalcRentPeriods = (db, entries) ->
  months = new Set()
  for e in entries when e.worker is 'lyndzie'
    for ts in [e.startTime, e.endTime]
      d = new Date ts
      months.add "#{d.getFullYear()}-#{d.getMonth() + 1}"

  return if months.size is 0

  console.log "\nRecalculating rent periods for #{months.size} month(s)..."

  # Load rent service dynamically (needs db to be initialized first)
  rentService = require '../lib/services/rent.coffee'

  for monthKey from months
    [year, month] = monthKey.split('-').map (n) -> parseInt n
    console.log "  Recalculating #{year}-#{String(month).padStart 2, '0'}..."
    await rentService.createOrUpdateRentPeriod year, month

# ============================================================
# Main
# ============================================================

main = ->
  console.log "Reading HTML: #{HTML_PATH}"
  html    = readFileSync HTML_PATH, 'utf-8'
  entries = extractEntries html

  console.log "Parsed #{entries.length} entries from HTML"
  console.log "Database: #{DB_PATH}"
  console.log "Mode: #{if dryRun then 'DRY RUN (no changes)' else 'LIVE INSERT'}"
  console.log ''

  db = new DatabaseSync DB_PATH

  added   = []
  skipped = 0
  failed  = 0

  insertStmt = db.prepare """
    INSERT INTO work_logs
           ( id,  worker,  start_time,  end_time,  duration,  description,  project_id,  task_id,  billable,  submitted,  created_at)
    VALUES (:id, :worker, :start_time, :end_time, :duration, :description, :project_id, :task_id, :billable, :submitted, :created_at)
  """

  checkStmt = db.prepare "SELECT id FROM work_logs WHERE id = ?"

  for entry in entries
    existing = checkStmt.get entry.uuid

    if existing
      console.log "  SKIP  #{entry.dateStr.padEnd 22} #{entry.worker.padEnd 8} #{entry.uuid}"
      skipped++
      continue

    shortDesc = if entry.description.length > 55 then entry.description[...55] + '...' else entry.description
    console.log "  #{if dryRun then 'WOULD' else 'ADD  '} #{entry.dateStr.padEnd 22} #{entry.worker.padEnd 8} #{entry.duration}min  #{shortDesc}"

    unless dryRun
      try
        insertStmt.run
          ':id':          entry.uuid
          ':worker':      entry.worker
          ':start_time':  entry.startTime
          ':end_time':    entry.endTime
          ':duration':    entry.duration
          ':description': entry.description
          ':project_id':  null
          ':task_id':     null
          ':billable':    1
          ':submitted':   0
          ':created_at':  new Date().toISOString()
        added.push entry
      catch err
        console.error "  FAIL  #{entry.dateStr} #{entry.worker}: #{err.message}"
        failed++

  console.log ''
  console.log "Summary: #{added.length} added, #{skipped} skipped, #{failed} failed"

  unless dryRun or added.length is 0
    await recalcRentPeriods db, added

  db.close()

main().catch (err) ->
  console.error "Fatal:", err.message
  process.exit 1
