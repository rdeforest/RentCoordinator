# Troubleshooting Guide

## Assume Nothing: Development Best Practices

### Local Development

#### Quick Clean
When things don't work as expected, always start with a clean slate:

```bash
# Clean build artifacts and test data
npm run clean

# Full rebuild
npm run build
```

#### Nuclear Option (Local)
If `npm run clean` doesn't fix it:

```bash
# Remove everything including dependencies
npm run clean:all

# Fresh install
npm install

# Rebuild
npm run build
```

#### Common Issues

**Problem: "Module not found" errors**
- **Cause**: Stale compiled files in `dist/`
- **Solution**: `npm run clean && npm run build`

**Problem: SQLite foreign key constraint errors**
- **Cause**: Dirty database with `.db-shm` or `.db-wal` files from crashed processes
- **Solution**: `npm run clean` (removes all `.db*` files)

**Problem: Build seems to work but code changes aren't reflected**
- **Cause**: Build script didn't detect changes or compiled to wrong directory
- **Solution**: Check `pwd`, ensure not in symlinked directory, run `npm run clean && npm run build`


### Remote Deployment

#### Standard Upgrade
Use `deploy-upgrade.sh` for normal updates:

```bash
./scripts/deploy-upgrade.sh vault2
```

This:
1. Backs up database
2. Uploads new code
3. Runs npm install
4. Restarts service

#### Nuclear Option (Remote)
**If upgrade fails immediately**, use the nuclear option:

```bash
# Full uninstall (preserves database backups)
./scripts/deploy-uninstall.sh vault2

# Fresh install
./scripts/deploy-install.sh vault2
```

**When to use nuclear option:**
- First deploy fails with dependency errors
- Node version mismatch
- systemd service won't start after upgrade
- Any "it should work but doesn't" situation

**What it does:**
- Removes `~/rent-coordinator` directory entirely
- Removes systemd service
- Removes `rent-coordinator` user (install only)
- Fresh `npm install` with current dependencies
- Clean systemd service registration

**What it preserves:**
- Database backups in `backups/` (if you created them)
- AWS Secrets Manager configuration


### Verification Checklist

After any deployment or local change:

```bash
# 1. Build succeeded?
npm run build
# Should show: "✓ Build complete!"

# 2. Server starts?
PORT=3002 timeout 5 npm start
# Should show: "Tenant Coordinator Service Started"

# 3. No foreign key errors?
# Check output - should see "Recurring events system initialized" with no errors

# 4. Database created?
ls -la *.db*
# Should show tenant-coordinator.db (and possibly .db-shm, .db-wal if running)
```


### Diagnostic Commands

#### Check process state
```bash
# On remote server
sudo systemctl status rent-coordinator
sudo journalctl -u rent-coordinator -n 50 --no-pager

# Locally
ps aux | grep "node dist/main"
```

#### Check file permissions
```bash
ls -la ~/rent-coordinator/
ls -la ~/rent-coordinator/*.db*
```

#### Check port conflicts
```bash
# Remote
sudo ss -tlnp | grep :8080

# Local
lsof -i :3000
```

#### Check dependencies
```bash
# Verify Node version (need v22.5.0+ for native SQLite)
node --version

# Check installed packages
npm list --depth=0
```


### Prevention Strategies

1. **Always clean before major changes**
   ```bash
   npm run clean && npm run build
   ```

2. **Kill processes before testing**
   ```bash
   pkill -f "node dist/main"
   rm -f *.db*  # If starting fresh
   ```

3. **Use absolute paths in scripts**
   - Avoid `cd` in automation
   - Prefer `npm run` scripts over direct commands

4. **Verify assumptions explicitly**
   - Check `pwd` before running scripts
   - Verify files exist before using them
   - Check process state before restarting

5. **Document the nuclear option**
   - When in doubt, blow it away and start fresh
   - In development, speed > preservation
   - Production: different story (backups first!)


### Emergency Recovery

If the server is completely broken:

```bash
# 1. Stop the service
ssh vault2 'sudo systemctl stop rent-coordinator'

# 2. Backup database (if it exists and might be valuable)
ssh vault2 'cd ~/rent-coordinator && npm run backup'
scp vault2:~/rent-coordinator/backups/*.json ./backups/

# 3. Nuclear option
./scripts/deploy-uninstall.sh vault2
./scripts/deploy-install.sh vault2

# 4. Restore data if needed
# (See DISASTER-RECOVERY.md)
```


### Learning from Failures

**Today's lessons:**

1. **Symlink confusion**: Build was running in wrong directory
   - **Solution**: Check `pwd`, use absolute paths, or avoid symlinks

2. **Dirty SQLite files**: `.db-shm` and `.db-wal` persist after crashes
   - **Solution**: `npm run clean` removes all `.db*` files

3. **Stale compiled code**: Changes to source didn't appear
   - **Solution**: `rm -rf dist/` before rebuild

**General principle**: When debugging takes > 5 minutes, nuke it and rebuild. In development, time is more valuable than preservation.
