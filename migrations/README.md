# Database Migrations

This directory contains database migrations for RentCoordinator.

The stack is **Node.js + SQLite** (via Node's built-in `node:sqlite` module). There is no external
migration framework — migrations are plain CoffeeScript scripts that run against the SQLite database.

## How Migrations Work

Migrations are executed manually or by `scripts/upgrade.sh` in alphabetical order. Each migration
is a `.coffee` file that opens the database and performs schema or data changes.

## Creating a Migration

1. **Name your migration with a timestamp prefix:**
   ```
   migrations/YYYY-MM-DD_HH-MM-SS_description.coffee
   ```
   Example: `migrations/2026-03-01_12-00-00_add_user_roles.coffee`

2. **Migration template:**
   ```coffeescript
   # migrations/2026-03-01_12-00-00_add_user_roles.coffee

   { DatabaseSync } = require 'node:sqlite'

   DB_PATH = process.env.DB_PATH or './tenant-coordinator.db'

   db = new DatabaseSync DB_PATH

   console.log 'Running migration: add_user_roles'

   try
     db.exec '''
       ALTER TABLE auth_sessions ADD COLUMN role TEXT DEFAULT 'user';
     '''

     console.log 'Migration completed successfully'
   catch err
     console.error 'Migration failed:', err
     throw err
   finally
     db.close()
   ```

3. **Test locally before running:**
   ```bash
   # Backup first
   curl -X POST http://localhost:3000/api/backup

   # Run the migration
   coffee migrations/YYYY-MM-DD_HH-MM-SS_description.coffee

   # Verify
   npm start
   # Test that the app still works

   # If it failed, restore from backup via API
   curl -X POST http://localhost:3000/api/backup/restore
   ```

4. **Commit the migration:**
   ```bash
   git add migrations/YYYY-MM-DD_HH-MM-SS_description.coffee
   git commit -m "Add migration: description"
   ```

## Migration Best Practices

- **Idempotent:** Migrations should be safe to run multiple times (use `IF NOT EXISTS`, etc.)
- **Backward compatible:** Don't break existing functionality
- **Test thoroughly:** Always backup first and test on development data
- **Small and focused:** One logical change per migration

## Common Migration Patterns

### Adding a column to an existing table

```coffeescript
db.exec '''
  ALTER TABLE work_logs ADD COLUMN billable INTEGER DEFAULT 1;
'''
```

### Creating a new table

```coffeescript
db.exec '''
  CREATE TABLE IF NOT EXISTS work_item_comments (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    work_item_type TEXT NOT NULL,
    work_item_id INTEGER NOT NULL,
    author       TEXT NOT NULL,
    content      TEXT NOT NULL,
    created_at   TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at   TEXT NOT NULL DEFAULT (datetime('now'))
  );
'''
```

### Transforming existing data

```coffeescript
stmt = db.prepare 'SELECT id, duration_minutes FROM work_logs WHERE duration_minutes IS NOT NULL'
update = db.prepare 'UPDATE work_logs SET duration = ? WHERE id = ?'

for row in stmt.all()
  update.run row.duration_minutes / 60, row.id

console.log 'Converted duration_minutes to hours for all rows'
```

## Rollback Strategy

Migrations don't have automatic rollback. If a migration fails:

1. **Restore from the pre-migration backup:**
   ```bash
   curl -X POST http://localhost:3000/api/backup/restore
   ```
   Or from a specific local backup file — restart the app pointing at the backup copy.

2. **Fix the migration and test again**

3. **If deployed to production:**
   ```bash
   # SSH to instance
   ssh -i ~/.ssh/id_aws_rdeforest ubuntu@<INSTANCE_IP>

   # Restore from latest S3 backup via API
   curl -X POST http://localhost:3000/api/backup/restore

   sudo systemctl restart rent-coordinator
   ```
