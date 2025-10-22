# lib/services/backup.coffee

{ db }        = require('../db/schema.coffee')
config        = require('../config.coffee')
{ join }      = require('node:path')
{ existsSync} = require('node:fs')

BACKUP_VERSION = '1.0.0'

# All KV key prefixes used in the system
KEY_PREFIXES = [
  ['timer_state']
  ['work_sessions']
  ['work_events']
  ['current_session']
  ['work_logs']
  ['work_logs_by_worker']
  ['work_logs_by_date']
  ['rent_periods']
  ['rent_payments']
  ['rent_events']
  ['audit_logs']
  ['recurring_events']
  ['recurring_event_logs']
]


# Export all data from Deno KV to JSON structure
exportBackup = ->
  console.log 'Starting backup export...'

  backup =
    version:   BACKUP_VERSION
    timestamp: new Date().toISOString()
    db_path:   config.DB_PATH
    data:      {}
    config:    {}  # Configuration and environment

  # Export environment configuration (for disaster recovery)
  console.log '  Exporting configuration...'
  backup.config =
    port:                 config.PORT
    node_env:             config.NODE_ENV
    db_path:              config.DB_PATH
    base_rent:            config.BASE_RENT
    hourly_credit:        config.HOURLY_CREDIT
    max_monthly_hours:    config.MAX_MONTHLY_HOURS
    workers:              config.WORKERS
    default_stakeholders: config.DEFAULT_STAKEHOLDERS
    allowed_emails:       config.ALLOWED_EMAILS
    session_max_age:      config.SESSION_MAX_AGE
    code_expiry:          config.CODE_EXPIRY
    # Note: Secrets like SESSION_SECRET, SMTP credentials, and Stripe keys
    # should be stored separately in a secure location (password manager)
    # and restored manually during disaster recovery

  totalEntries = 0

  for prefix in KEY_PREFIXES
    prefixKey = prefix.join('/')
    backup.data[prefixKey] = []

    console.log "  Exporting #{prefixKey}..."
    count = 0

    entries = db.list prefix: prefix
    for await entry from entries
      backup.data[prefixKey].push
        key:   entry.key
        value: entry.value
      count++
      totalEntries++

    console.log "    Found #{count} entries"

  console.log "Total entries exported: #{totalEntries}"
  backup


# Import data from JSON structure back to Deno KV
importBackup = (backup, options = {}) ->
  { overwrite = true, dryRun = false } = options

  unless backup.version
    throw new Error 'Invalid backup format: missing version'

  unless backup.data
    throw new Error 'Invalid backup format: missing data'

  console.log "Starting backup restore (version #{backup.version})..."
  console.log "Backup from: #{backup.timestamp}"
  console.log "Dry run: #{dryRun}"
  console.log "Overwrite: #{overwrite}"

  stats =
    total:    0
    created:  0
    updated:  0
    skipped:  0
    errors:   0

  for prefixKey, entries of backup.data
    console.log "  Restoring #{prefixKey} (#{entries.length} entries)..."

    for entry in entries
      stats.total++

      try
        unless Array.isArray(entry.key)
          throw new Error "Invalid key format: #{JSON.stringify(entry.key)}"

        # Check if entry exists
        existing = await db.get(entry.key)

        if existing.value and not overwrite
          stats.skipped++
          console.log "    Skipped existing: #{JSON.stringify(entry.key)}"
          continue

        # Write entry
        unless dryRun
          await db.set entry.key, entry.value

        if existing.value
          stats.updated++
        else
          stats.created++

      catch err
        stats.errors++
        console.error "    Error restoring #{JSON.stringify(entry.key)}: #{err.message}"

  console.log '\nRestore summary:'
  console.log "  Total entries:   #{stats.total}"
  console.log "  Created:         #{stats.created}"
  console.log "  Updated:         #{stats.updated}"
  console.log "  Skipped:         #{stats.skipped}"
  console.log "  Errors:          #{stats.errors}"

  stats


# Save backup to file
saveBackupToFile = (backup, filepath) ->
  json = JSON.stringify backup, null, 2
  await Deno.writeTextFile filepath, json
  console.log "Backup saved to: #{filepath}"
  filepath


# Load backup from file
loadBackupFromFile = (filepath) ->
  unless existsSync filepath
    throw new Error "Backup file not found: #{filepath}"

  json = await Deno.readTextFile filepath
  backup = JSON.parse json

  console.log "Loaded backup from: #{filepath}"
  console.log "  Version:   #{backup.version}"
  console.log "  Timestamp: #{backup.timestamp}"

  backup


# Create backup directory if it doesn't exist
ensureBackupDir = (dir) ->
  unless existsSync dir
    await Deno.mkdir dir, recursive: true
    console.log "Created backup directory: #{dir}"
  dir


# Generate backup filename with timestamp
generateBackupFilename = (timestamp = new Date()) ->
  # Format: backup-2025-10-20T12-30-45.json
  isoString = timestamp.toISOString()
  dateStr = isoString.replace(/:/g, '-').split('.')[0]
  "backup-#{dateStr}.json"


# Full backup operation: export and save to file
createBackup = (backupDir = './backups') ->
  await ensureBackupDir backupDir

  backup = await exportBackup()
  filename = generateBackupFilename()
  filepath = join backupDir, filename

  await saveBackupToFile backup, filepath

  { filepath, backup }


# Full restore operation: load from file and import
restoreBackup = (filepath, options = {}) ->
  backup = await loadBackupFromFile filepath
  stats = await importBackup backup, options

  { backup, stats }

module.exports = {
  exportBackup
  importBackup
  saveBackupToFile
  loadBackupFromFile
  ensureBackupDir
  generateBackupFilename
  createBackup
  restoreBackup
}
