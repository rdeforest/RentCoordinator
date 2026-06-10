# Backup API Reference

The RentCoordinator application includes a complete backup API for managing database backups locally and in S3.

## Endpoints

### `POST /api/backup`
Create a database backup (local + S3 if enabled)

**Request:**
```bash
curl -X POST https://rent.defore.st/api/backup \
  -H "Content-Type: application/json" \
  -b cookies.txt
```

**Response:**
```json
{
  "success": true,
  "backup": {
    "filepath": "./backups/tenant-coordinator-2026-02-13T21-30-00-000Z.db",
    "filename": "tenant-coordinator-2026-02-13T21-30-00-000Z.db",
    "timestamp": "2026-02-13T21:30:00.000Z",
    "s3": {
      "enabled": true,
      "bucket": "rent-coordinator-backups-822812818413",
      "key": "database/tenant-coordinator-2026-02-13T21-30-00-000Z.db"
    }
  }
}
```

### `GET /api/backup/list`
List available backups in S3

**Request:**
```bash
curl https://rent.defore.st/api/backup/list \
  -H "Content-Type: application/json" \
  -b cookies.txt
```

**Response:**
```json
{
  "success": true,
  "backups": [
    {
      "key": "database/tenant-coordinator-2026-02-13T21-30-00-000Z.db",
      "size": 204800,
      "lastModified": "2026-02-13T21:30:00.000Z",
      "filename": "tenant-coordinator-2026-02-13T21-30-00-000Z.db"
    }
  ],
  "bucket": "rent-coordinator-backups-822812818413",
  "count": 1
}
```

### `POST /api/backup/restore`
Restore database from latest S3 backup

**Request:**
```bash
curl -X POST https://rent.defore.st/api/backup/restore \
  -H "Content-Type: application/json" \
  -b cookies.txt
```

**Response:**
```json
{
  "success": true,
  "restored": true,
  "backup": {
    "key": "database/tenant-coordinator-2026-02-13T21-30-00-000Z.db",
    "filename": "tenant-coordinator-2026-02-13T21-30-00-000Z.db"
  }
}
```

### `GET /api/backup/status`
Get backup system status

**Request:**
```bash
curl https://rent.defore.st/api/backup/status \
  -H "Content-Type: application/json" \
  -b cookies.txt
```

**Response:**
```json
{
  "s3Enabled": true,
  "bucket": "rent-coordinator-backups-822812818413",
  "prefix": "database/",
  "region": "us-west-2",
  "backupCount": 5,
  "latestBackup": {
    "key": "database/tenant-coordinator-2026-02-13T21-30-00-000Z.db",
    "filename": "tenant-coordinator-2026-02-13T21-30-00-000Z.db",
    "lastModified": "2026-02-13T21:30:00.000Z"
  }
}
```

## Environment Variables

- `S3_BACKUP_ENABLED` - Enable/disable S3 sync (default: `true` in production)
- `BACKUP_S3_BUCKET` - S3 bucket name (default: `rent-coordinator-backups-822812818413`)
- `BACKUP_S3_PREFIX` - S3 key prefix (default: `database/`)
- `AWS_REGION` - AWS region (default: `us-west-2`)

## Backup Workflow

The backup system works in two stages:

1. **Local Backup**: Creates a copy of the SQLite database in `./backups/`
2. **S3 Sync**: Uploads the backup to S3 (if enabled)

When a new instance starts, it:
1. Checks for the database file (`DB_PATH`)
2. If not found, attempts to restore from latest S3 backup
3. If restore succeeds, instance starts with restored data
4. If restore fails, instance starts with fresh database

## Authentication

All backup endpoints require authentication. You must be logged in with a valid session cookie.

## CLI Commands

For manual backup/restore operations:

```bash
# Create backup
npm run backup

# Restore from file
npm run restore backups/backup-YYYY-MM-DD*.json

# List backups (requires AWS CLI)
aws s3 ls s3://rent-coordinator-backups-822812818413/database/
```
