# Backup API Routes

backupService = require '../services/backup.coffee'


setup = (app) ->
  # POST /api/backup
  # Create a database backup (local + S3)
  app.post '/api/backup', createBackupRoute

  # GET /api/backup/list
  # List available backups in S3
  app.get '/api/backup/list', listBackupsRoute

  # POST /api/backup/restore
  # Restore database from latest S3 backup
  app.post '/api/backup/restore', restoreFromS3Route

  # GET /api/backup/status
  # Get backup system status
  app.get '/api/backup/status', backupStatusRoute


# POST /api/backup
# Create a database backup (local + S3)
createBackupRoute = (req, res) ->
  try
    result = await backupService.createBackup()

    res.json
      success: true
      backup:
        filename:  result.filename
        filepath:  result.filepath
        timestamp: result.timestamp
        s3:
          enabled:  backupService.S3_ENABLED
          uploaded: result.s3?
          bucket:   result.s3?.bucket
          key:      result.s3?.key

  catch error
    console.error 'Backup creation failed:', error
    res.status(500).json
      success: false
      error:   error.message


# GET /api/backup/list
# List available backups in S3
listBackupsRoute = (req, res) ->
  try
    unless backupService.S3_ENABLED
      return res.json
        success: true
        backups: []
        s3Enabled: false

    backups = await backupService.listS3Backups()

    res.json
      success:    true
      s3Enabled:  true
      backups:    backups
      bucket:     backupService.S3_BUCKET

  catch error
    console.error 'Failed to list backups:', error
    res.status(500).json
      success: false
      error:   error.message


# POST /api/backup/restore
# Restore database from latest S3 backup
restoreFromS3Route = (req, res) ->
  try
    unless backupService.S3_ENABLED
      return res.status(400).json
        success: false
        error:   'S3 backup is not enabled'

    result = await backupService.restoreFromS3()

    if result
      res.json
        success:  true
        restored: true
        backup:   result.backup
    else
      res.json
        success:  true
        restored: false
        message:  'No backups found in S3'

  catch error
    console.error 'Restore from S3 failed:', error
    res.status(500).json
      success: false
      error:   error.message


# GET /api/backup/status
# Get backup system status
backupStatusRoute = (req, res) ->
  try
    status =
      s3Enabled: backupService.S3_ENABLED
      bucket:    backupService.S3_BUCKET
      prefix:    backupService.S3_PREFIX
      region:    backupService.AWS_REGION

    if backupService.S3_ENABLED
      backups = await backupService.listS3Backups()
      status.backupCount = backups.length
      status.latestBackup = backups[0] if backups.length > 0

    res.json
      success: true
      status:  status

  catch error
    console.error 'Failed to get backup status:', error
    res.status(500).json
      success: false
      error:   error.message


module.exports = { setup }
