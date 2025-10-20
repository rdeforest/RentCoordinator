# Database Migrations

This directory contains database migrations for RentCoordinator.

## How Migrations Work

Migrations are executed automatically by `scripts/upgrade.sh` in alphabetical order. They are JavaScript files that run once to transform the database schema or data.

## Creating a Migration

1. **Name your migration with a timestamp prefix:**
   ```
   migrations/YYYY-MM-DD_HH-MM-SS_description.js
   ```
   Example: `2025-10-20_15-30-00_add_user_roles.js`

2. **Migration template:**
   ```javascript
   // migrations/2025-10-20_15-30-00_add_user_roles.js

   const db = await Deno.openKv('./tenant-coordinator.db');

   console.log('Running migration: add_user_roles');

   try {
       // Your migration code here
       // Example: Add new keys, transform data, etc.

       // Mark migration as complete
       await db.set(['migration', '2025-10-20_15-30-00_add_user_roles'], {
           completed: new Date().toISOString(),
           description: 'Add user roles to auth system'
       });

       console.log('Migration completed successfully');
   } catch (err) {
       console.error('Migration failed:', err);
       throw err;
   } finally {
       db.close();
   }
   ```

3. **Test your migration locally:**
   ```bash
   # Create a backup first
   deno task backup > backups/before-migration.json

   # Run the migration
   deno run --allow-read --allow-write --allow-env --unstable-kv \
     migrations/YYYY-MM-DD_HH-MM-SS_description.js

   # Verify it worked
   npm run start
   # Test your app

   # If it failed, restore from backup
   deno task restore backups/before-migration.json
   ```

4. **Commit the migration:**
   ```bash
   git add migrations/YYYY-MM-DD_HH-MM-SS_description.js
   git commit -m "Add migration: description"
   ```

## Migration Best Practices

- **Idempotent:** Migrations should be safe to run multiple times
- **Backward compatible:** Don't break existing functionality
- **Test thoroughly:** Always test migrations on a backup first
- **Document changes:** Include comments explaining what the migration does
- **Small and focused:** One logical change per migration

## Common Migration Patterns

### Adding a new field to existing records

```javascript
// Get all work_sessions
const entries = db.list({ prefix: ['work_session'] });

for await (const entry of entries) {
    const session = entry.value;

    // Add new field if not present
    if (!session.hasOwnProperty('newField')) {
        session.newField = 'default_value';
        await db.set(entry.key, session);
        console.log(`Updated session ${entry.key[1]}`);
    }
}
```

### Renaming a key structure

```javascript
// Move data from old keys to new keys
const oldEntries = db.list({ prefix: ['old_prefix'] });

for await (const entry of oldEntries) {
    const newKey = ['new_prefix', entry.key[1]];
    await db.set(newKey, entry.value);
    await db.delete(entry.key);
    console.log(`Migrated ${entry.key} -> ${newKey}`);
}
```

### Data transformation

```javascript
// Transform existing data
const entries = db.list({ prefix: ['work_log'] });

for await (const entry of entries) {
    const log = entry.value;

    // Convert minutes to hours
    if (log.duration_minutes) {
        log.duration_hours = log.duration_minutes / 60;
        delete log.duration_minutes;
        await db.set(entry.key, log);
    }
}
```

## Rollback Strategy

Migrations don't have automatic rollback. If a migration fails:

1. **Restore from backup:**
   ```bash
   deno task restore backups/backup-YYYY-MM-DD_HH-MM-SS.json
   ```

2. **Fix the migration and test again**

3. **If deployed to production, use git to rollback:**
   ```bash
   cd /path/to/production
   git reset --hard PREVIOUS_COMMIT
   npm run build
   deno task restore backups/backup-YYYY-MM-DD_HH-MM-SS.json
   sudo systemctl restart rent-coordinator
   ```

## Future: SQLite Migration

When we migrate from Deno KV to SQLite:

1. Create a migration that exports all KV data
2. Create SQLite schema
3. Import data into SQLite
4. Update application code to use SQLite
5. Keep KV backup for safety

This will be a major migration and should be tested extensively in development first.
