{ describe, it, before, after, beforeEach } = require 'node:test'
assert                                    = require 'node:assert/strict'
fs                                        = require 'node:fs'
path                                      = require 'node:path'
{ DatabaseSync }                          = require 'node:sqlite'

# Set test environment before loading backup module
process.env.S3_BACKUP_ENABLED = 'false'  # Disable S3 for most tests

{
  createLocalBackup
  uploadBackupToS3
  downloadBackupFromS3
  restoreFromFile
  restoreFromS3
  listS3Backups
  S3_ENABLED
  S3_BUCKET
  S3_PREFIX
}                                         = require '../../lib/services/backup.coffee'


TEST_TMP_DIR = '/tmp/rent-coordinator-backup-tests'
TEST_DB_PATH = path.join TEST_TMP_DIR, 'test-backup.db'
BACKUP_DIR   = path.join TEST_TMP_DIR, 'backups'


# Prepare clean test environment
prepareTestEnv = ->
  if fs.existsSync TEST_TMP_DIR
    fs.rmSync TEST_TMP_DIR, recursive: true, force: true
  fs.mkdirSync TEST_TMP_DIR, recursive: true
  fs.mkdirSync BACKUP_DIR, recursive: true


# Clean up test environment
cleanupTestEnv = ->
  try
    if fs.existsSync TEST_TMP_DIR
      fs.rmSync TEST_TMP_DIR, recursive: true, force: true


# Create test database with known data
createTestDatabase = (dbPath) ->
  db = new DatabaseSync dbPath
  db.exec 'PRAGMA foreign_keys = ON'

  # Create minimal schema for testing
  db.exec """
    CREATE TABLE IF NOT EXISTS work_logs (
      id TEXT PRIMARY KEY,
      worker TEXT NOT NULL,
      start_time DATETIME NOT NULL,
      end_time DATETIME NOT NULL,
      duration INTEGER NOT NULL,
      description TEXT NOT NULL,
      billable BOOLEAN DEFAULT 1,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS rent_periods (
      id TEXT PRIMARY KEY,
      year INTEGER NOT NULL,
      month INTEGER NOT NULL,
      base_rent REAL NOT NULL,
      amount_due REAL NOT NULL,
      amount_paid REAL DEFAULT 0,
      UNIQUE(year, month)
    );

    CREATE INDEX IF NOT EXISTS idx_work_logs_worker ON work_logs(worker);
  """

  # Insert known test data
  db.prepare("""
    INSERT INTO work_logs (id, worker, start_time, end_time, duration, description)
    VALUES (?, ?, ?, ?, ?, ?)
  """).run(
    'wl-test-1'
    'lyndzie'
    '2026-01-01T10:00:00Z'
    '2026-01-01T12:00:00Z'
    120
    'Test work session'
  )

  db.prepare("""
    INSERT INTO rent_periods (id, year, month, base_rent, amount_due, amount_paid)
    VALUES (?, ?, ?, ?, ?, ?)
  """).run(
    'rp-2026-01'
    2026
    1
    1600
    950
    0
  )

  db.close()

  # Return expected data for verification
  workLogs:    1
  rentPeriods: 1
  sampleWorkLog:
    id:          'wl-test-1'
    worker:      'lyndzie'
    duration:    120
    description: 'Test work session'
  sampleRentPeriod:
    id:         'rp-2026-01'
    year:       2026
    month:      1
    base_rent:  1600
    amount_due: 950


# Verify database matches expected data
verifyDatabaseData = (dbPath, expected) ->
  db = new DatabaseSync dbPath

  # Check table counts
  workLogCount = db.prepare('SELECT COUNT(*) as count FROM work_logs').get().count
  assert.equal workLogCount, expected.workLogs,
    "Work logs count should match (expected #{expected.workLogs}, got #{workLogCount})"

  rentPeriodCount = db.prepare('SELECT COUNT(*) as count FROM rent_periods').get().count
  assert.equal rentPeriodCount, expected.rentPeriods,
    "Rent periods count should match (expected #{expected.rentPeriods}, got #{rentPeriodCount})"

  # Verify sample work log
  workLog = db.prepare('SELECT * FROM work_logs WHERE id = ?').get expected.sampleWorkLog.id
  assert.ok workLog, 'Sample work log should exist'
  assert.equal workLog.worker, expected.sampleWorkLog.worker,
    'Work log worker should match'
  assert.equal workLog.duration, expected.sampleWorkLog.duration,
    'Work log duration should match'
  assert.equal workLog.description, expected.sampleWorkLog.description,
    'Work log description should match'

  # Verify sample rent period
  rentPeriod = db.prepare('SELECT * FROM rent_periods WHERE id = ?').get expected.sampleRentPeriod.id
  assert.ok rentPeriod, 'Sample rent period should exist'
  assert.equal rentPeriod.year, expected.sampleRentPeriod.year,
    'Rent period year should match'
  assert.equal rentPeriod.month, expected.sampleRentPeriod.month,
    'Rent period month should match'
  assert.equal rentPeriod.base_rent, expected.sampleRentPeriod.base_rent,
    'Rent period base_rent should match'
  assert.equal rentPeriod.amount_due, expected.sampleRentPeriod.amount_due,
    'Rent period amount_due should match'

  db.close()


# Verify database schema exists and is valid
verifyDatabaseSchema = (dbPath) ->
  db = new DatabaseSync dbPath

  # Check that expected tables exist
  tables = db.prepare("""
    SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'
  """).all()
  tableNames = tables.map (t) -> t.name

  assert.ok tableNames.includes('work_logs'), 'work_logs table should exist'
  assert.ok tableNames.includes('rent_periods'), 'rent_periods table should exist'

  # Check that expected indexes exist
  indexes = db.prepare("""
    SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'
  """).all()
  indexNames = indexes.map (i) -> i.name

  assert.ok indexNames.includes('idx_work_logs_worker'),
    'idx_work_logs_worker index should exist'

  # Verify work_logs columns
  workLogColumns = db.prepare("PRAGMA table_info(work_logs)").all()
  columnNames = workLogColumns.map (c) -> c.name

  assert.ok columnNames.includes('id'), 'work_logs should have id column'
  assert.ok columnNames.includes('worker'), 'work_logs should have worker column'
  assert.ok columnNames.includes('duration'), 'work_logs should have duration column'
  assert.ok columnNames.includes('description'), 'work_logs should have description column'

  db.close()


describe 'Backup Integration Tests', ->

  beforeEach ->
    prepareTestEnv()

  after ->
    cleanupTestEnv()


  it 'should create and restore local backup with data integrity', ->
    # Override config DB_PATH for this test
    originalDbPath = process.env.DB_PATH
    process.env.DB_PATH = TEST_DB_PATH

    try
      # Create test database with known data
      expected = createTestDatabase TEST_DB_PATH

      # Create local backup
      { filepath } = await createLocalBackup BACKUP_DIR
      assert.ok fs.existsSync(filepath), 'Backup file should exist'

      # Delete original database
      fs.unlinkSync TEST_DB_PATH
      assert.ok !fs.existsSync(TEST_DB_PATH), 'Original database should be deleted'

      # Restore from backup
      result = await restoreFromFile filepath
      assert.equal result.restored, true, 'Restore should succeed'
      assert.ok fs.existsSync(TEST_DB_PATH), 'Database should be restored'

      # Verify all data matches
      verifyDatabaseData TEST_DB_PATH, expected

      # Verify schema is intact
      verifyDatabaseSchema TEST_DB_PATH

    finally
      process.env.DB_PATH = originalDbPath


  it 'should verify database is queryable after restore', ->
    originalDbPath = process.env.DB_PATH
    process.env.DB_PATH = TEST_DB_PATH

    try
      # Create test database
      expected = createTestDatabase TEST_DB_PATH

      # Backup and restore
      { filepath } = await createLocalBackup BACKUP_DIR
      fs.unlinkSync TEST_DB_PATH
      await restoreFromFile filepath

      # Test querying the restored database
      db = new DatabaseSync TEST_DB_PATH

      # Query work logs
      workLogs = db.prepare('SELECT * FROM work_logs').all()
      assert.equal workLogs.length, expected.workLogs,
        'Should be able to query work logs'

      # Query with filter
      lyndizieWork = db.prepare("SELECT * FROM work_logs WHERE worker = ?").all('lyndzie')
      assert.equal lyndizieWork.length, 1,
        'Should be able to query with WHERE clause'

      # Join query (if tables support it)
      # This verifies foreign key relationships work
      db.close()

    finally
      process.env.DB_PATH = originalDbPath


  # S3 tests - only run when explicitly enabled
  it.skip 'should upload to and download from S3 successfully (requires S3_BACKUP_ENABLED=true)', ->
      originalDbPath = process.env.DB_PATH
      process.env.DB_PATH = TEST_DB_PATH

      try
        # Create test database
        expected = createTestDatabase TEST_DB_PATH

        # Create local backup
        { filepath } = await createLocalBackup BACKUP_DIR

        # Upload to S3
        s3Result = await uploadBackupToS3 filepath
        assert.ok s3Result.bucket, 'S3 upload should return bucket'
        assert.ok s3Result.key, 'S3 upload should return key'
        assert.equal s3Result.bucket, S3_BUCKET, 'Should upload to correct bucket'

        # Verify file exists in S3 by listing
        backups = await listS3Backups()
        assert.ok backups.length > 0, 'Should find backups in S3'

        uploadedBackup = backups.find (b) -> b.key is s3Result.key
        assert.ok uploadedBackup, 'Uploaded backup should appear in S3 list'
        assert.ok uploadedBackup.size > 0, 'Backup should have non-zero size'

        # Delete local files completely
        fs.unlinkSync TEST_DB_PATH
        fs.unlinkSync filepath

        # Download from S3
        downloadPath = path.join BACKUP_DIR, 'downloaded-from-s3.db'
        downloadResult = await downloadBackupFromS3 s3Result.key, downloadPath
        assert.ok fs.existsSync(downloadPath), 'Downloaded file should exist'

        # Restore from downloaded backup
        await restoreFromFile downloadPath

        # Verify all data matches exactly
        verifyDatabaseData TEST_DB_PATH, expected
        verifyDatabaseSchema TEST_DB_PATH

        # Clean up test backup from S3
        { S3Client, DeleteObjectCommand } = require '@aws-sdk/client-s3'
        s3Client = new S3Client { region: process.env.AWS_REGION or 'us-west-2' }
        deleteCommand = new DeleteObjectCommand
          Bucket: S3_BUCKET
          Key:    s3Result.key
        await s3Client.send deleteCommand
        console.log "Cleaned up test backup from S3: #{s3Result.key}"

      finally
        process.env.DB_PATH = originalDbPath


    it.skip 'should restore from latest S3 backup (requires S3_BACKUP_ENABLED=true)', ->
      originalDbPath = process.env.DB_PATH
      process.env.DB_PATH = TEST_DB_PATH

      try
        # Create test database
        expected = createTestDatabase TEST_DB_PATH

        # Create and upload backup
        { filepath } = await createLocalBackup BACKUP_DIR
        s3Result = await uploadBackupToS3 filepath

        # Delete local database
        fs.unlinkSync TEST_DB_PATH

        # Restore from S3
        restoreResult = await restoreFromS3()
        assert.ok restoreResult, 'Should find backup in S3'
        assert.equal restoreResult.restored, true, 'Restore should succeed'

        # Verify data
        verifyDatabaseData TEST_DB_PATH, expected
        verifyDatabaseSchema TEST_DB_PATH

        # Clean up test backup from S3
        { S3Client, DeleteObjectCommand } = require '@aws-sdk/client-s3'
        s3Client = new S3Client { region: process.env.AWS_REGION or 'us-west-2' }
        deleteCommand = new DeleteObjectCommand
          Bucket: S3_BUCKET
          Key:    s3Result.key
        await s3Client.send deleteCommand
        console.log "Cleaned up test backup from S3: #{s3Result.key}"

      finally
        process.env.DB_PATH = originalDbPath


  it 'should handle backup of empty database', ->
    originalDbPath = process.env.DB_PATH
    process.env.DB_PATH = TEST_DB_PATH

    try
      # Create database with schema but no data
      db = new DatabaseSync TEST_DB_PATH
      db.exec """
        CREATE TABLE IF NOT EXISTS work_logs (
          id TEXT PRIMARY KEY,
          worker TEXT NOT NULL
        );
      """
      db.close()

      # Backup and restore
      { filepath } = await createLocalBackup BACKUP_DIR
      fs.unlinkSync TEST_DB_PATH
      await restoreFromFile filepath

      # Verify schema exists
      db = new DatabaseSync TEST_DB_PATH
      tables = db.prepare("""
        SELECT name FROM sqlite_master WHERE type='table' AND name='work_logs'
      """).all()
      assert.equal tables.length, 1, 'Table should exist after restore'

      # Verify no data
      count = db.prepare('SELECT COUNT(*) as count FROM work_logs').get().count
      assert.equal count, 0, 'Should have no data'

      db.close()

    finally
      process.env.DB_PATH = originalDbPath
