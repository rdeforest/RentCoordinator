# SQLite Database Backup Service with S3 Sync
#
# This service handles database backups with optional S3 synchronization for
# multi-instance deployments.

{ S3Client, PutObjectCommand, GetObjectCommand, ListObjectsV2Command } = require '@aws-sdk/client-s3'
{ createReadStream, createWriteStream, copyFileSync, existsSync, mkdirSync } = require 'node:fs'
{ readFile } = require 'node:fs/promises'
{ join, dirname, basename } = require 'node:path'

BACKUP_VERSION = '2.0.0'  # SQLite-based backups

# Get database path dynamically (allows test overrides)
getDbPath = -> process.env.DB_PATH or './tenant-coordinator.db'

# S3 Configuration (read dynamically to support test overrides)
getS3Config = ->
  bucket:  process.env.BACKUP_S3_BUCKET || 'rent-coordinator-backups-822812818413'
  prefix:  process.env.BACKUP_S3_PREFIX || 'database/'
  region:  process.env.AWS_REGION || 'us-west-2'
  enabled: process.env.S3_BACKUP_ENABLED isnt 'false'

# Legacy constants for backwards compatibility
S3_BUCKET  = process.env.BACKUP_S3_BUCKET || 'rent-coordinator-backups-822812818413'
S3_PREFIX  = process.env.BACKUP_S3_PREFIX || 'database/'
AWS_REGION = process.env.AWS_REGION || 'us-west-2'
S3_ENABLED = process.env.S3_BACKUP_ENABLED isnt 'false'

# Initialize S3 client
s3Client = new S3Client { region: AWS_REGION }


# Generate backup filename with timestamp
generateBackupFilename = (timestamp = new Date()) ->
  isoString = timestamp.toISOString()
  dateStr   = isoString.replace(/:/g, '-').replace(/\./g, '-')
  "tenant-coordinator-#{dateStr}.db"


# Ensure backup directory exists
ensureBackupDir = (dir) ->
  unless existsSync dir
    mkdirSync dir, recursive: true
    console.log "Created backup directory: #{dir}"
  dir


# Create local backup of SQLite database
createLocalBackup = (backupDir = './backups') ->
  await ensureBackupDir backupDir
  dbPath = getDbPath()

  unless existsSync dbPath
    throw new Error "Database file not found: #{dbPath}"

  filename = generateBackupFilename()
  filepath = join backupDir, filename

  console.log "Creating backup: #{filepath}"
  copyFileSync dbPath, filepath

  console.log "Backup created successfully"
  { filepath, filename }


# Upload backup to S3
uploadBackupToS3 = (filepath) ->
  s3Config = getS3Config()

  unless s3Config.enabled
    console.log "S3 sync disabled, skipping upload"
    return null

  filename = basename filepath
  s3Key    = "#{s3Config.prefix}#{filename}"

  console.log "Uploading backup to S3: s3://#{s3Config.bucket}/#{s3Key}"

  try
    fileContent = await readFile filepath

    command = new PutObjectCommand
      Bucket:      s3Config.bucket
      Key:         s3Key
      Body:        fileContent
      ContentType: 'application/x-sqlite3'
      Metadata:
        'backup-version': BACKUP_VERSION
        'db-path':        getDbPath()
        'timestamp':      new Date().toISOString()

    result = await s3Client.send command
    console.log "Backup uploaded successfully to S3"

    { bucket: s3Config.bucket, key: s3Key, etag: result.ETag }
  catch error
    console.error "Failed to upload backup to S3:", error.message
    throw error


# List backups in S3
listS3Backups = ->
  s3Config = getS3Config()

  unless s3Config.enabled
    console.log "S3 sync disabled"
    return []

  console.log "Listing backups in S3: s3://#{s3Config.bucket}/#{s3Config.prefix}"

  try
    command = new ListObjectsV2Command
      Bucket: s3Config.bucket
      Prefix: s3Config.prefix

    result = await s3Client.send command

    backups = (result.Contents || [])
      .filter (obj) -> obj.Key.endsWith('.db')
      .map (obj) ->
        key:          obj.Key
        size:         obj.Size
        lastModified: obj.LastModified
        filename:     basename obj.Key
      .sort (a, b) -> b.lastModified - a.lastModified  # Most recent first

    console.log "Found #{backups.length} backups in S3"
    backups
  catch error
    console.error "Failed to list S3 backups:", error.message
    throw error


# Download backup from S3
downloadBackupFromS3 = (s3Key, localPath) ->
  s3Config = getS3Config()

  unless s3Config.enabled
    throw new Error "S3 sync is disabled"

  console.log "Downloading backup from S3: s3://#{s3Config.bucket}/#{s3Key}"

  try
    command = new GetObjectCommand
      Bucket: s3Config.bucket
      Key:    s3Key

    result      = await s3Client.send command
    bodyStream  = result.Body
    writeStream = createWriteStream localPath

    # Stream the download
    await new Promise (resolve, reject) ->
      bodyStream.pipe writeStream
      writeStream.on 'finish', resolve
      writeStream.on 'error', reject

    console.log "Backup downloaded successfully to: #{localPath}"
    { localPath, metadata: result.Metadata }
  catch error
    console.error "Failed to download backup from S3:", error.message
    throw error


# Get latest backup from S3
getLatestBackupFromS3 = ->
  backups = await listS3Backups()

  unless backups.length > 0
    return null

  backups[0]  # Most recent (already sorted)


# Download and restore latest backup from S3
restoreFromS3 = ->
  s3Config = getS3Config()

  unless s3Config.enabled
    console.log "S3 sync disabled, skipping restore"
    return null

  console.log "Checking for latest backup in S3..."
  latest = await getLatestBackupFromS3()

  unless latest
    console.log "No backups found in S3"
    return null

  console.log "Latest backup: #{latest.filename} (#{latest.lastModified})"

  dbPath = getDbPath()

  # Download to temporary location
  tempPath = "#{dbPath}.restore-temp"
  await downloadBackupFromS3 latest.key, tempPath

  # Backup current database if it exists
  if existsSync dbPath
    backupPath = "#{dbPath}.before-restore"
    console.log "Backing up current database to: #{backupPath}"
    copyFileSync dbPath, backupPath

  # Replace current database with downloaded backup
  console.log "Restoring database from S3 backup"
  copyFileSync tempPath, dbPath

  # Clean up temp file
  fs = require 'node:fs'
  fs.unlinkSync tempPath

  console.log "Database restored successfully from S3"
  { restored: true, backup: latest }


# Full backup workflow: local + S3
createBackup = (backupDir = './backups') ->
  console.log 'Starting backup...'

  # Create local backup
  { filepath, filename } = await createLocalBackup backupDir

  result =
    filepath:   filepath
    filename:   filename
    s3:         null
    timestamp:  new Date()

  # Upload to S3 if enabled
  s3Config = getS3Config()
  if s3Config.enabled
    try
      result.s3 = await uploadBackupToS3 filepath
    catch error
      console.error "S3 upload failed, backup is still available locally"
      result.s3Error = error.message

  console.log 'Backup complete'
  result


# Restore from local file
restoreFromFile = (filepath) ->
  unless existsSync filepath
    throw new Error "Backup file not found: #{filepath}"

  console.log "Restoring database from: #{filepath}"

  dbPath = getDbPath()

  # Backup current database
  if existsSync dbPath
    backupPath = "#{dbPath}.before-restore"
    console.log "Backing up current database to: #{backupPath}"
    copyFileSync dbPath, backupPath

  # Restore from backup
  copyFileSync filepath, dbPath

  console.log "Database restored successfully"
  { restored: true, source: filepath }


module.exports = {
  createBackup
  createLocalBackup
  uploadBackupToS3
  listS3Backups
  downloadBackupFromS3
  getLatestBackupFromS3
  restoreFromS3
  restoreFromFile
  generateBackupFilename
  ensureBackupDir

  # Config
  S3_BUCKET
  S3_PREFIX
  S3_ENABLED
}
