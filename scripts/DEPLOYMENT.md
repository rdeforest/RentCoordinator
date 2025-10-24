# RentCoordinator Deployment Guide

This document describes the remote deployment system for RentCoordinator.

## Overview

RentCoordinator uses a **push-based deployment model** where you build on your dev machine and push pre-built artifacts to the remote server. This approach:

- ✓ Keeps a single source of truth (dev machine + GitHub)
- ✓ Doesn't require git or build tools on production
- ✓ Supports safe upgrades with automatic rollback
- ✓ Preserves database and config across upgrades
- ✓ Prepares for future .deb/.rpm packaging

## Architecture

```
Dev Machine (your laptop)
├── Source code (git repo)
├── scripts/deploy-*.sh        ← Run these
└── npm run build               ← Builds locally

                ↓ rsync

Production Server
├── ~/rent-coordinator/
│   ├── dist/                   ← Active version
│   ├── dist.old/               ← Previous version (for rollback)
│   ├── tenant-coordinator.db   ← Persistent data
│   ├── config.sh               ← Configuration
│   └── backups/                ← DB backups
└── systemd service             ← Managed by scripts
```

## Prerequisites

### On Dev Machine
- SSH key authentication configured
- Node.js and npm (for building)
- rsync

### On Remote Server
- SSH access with key authentication
- Passwordless sudo configured
- systemd (for service management)
- curl (for health checks)

## Deployment Scripts

### Local Scripts (run from dev machine)

**`deploy-install.sh <host>`** - First-time installation
```bash
./scripts/deploy-install.sh vault2.thatsnice.org
./scripts/deploy-install.sh admin@vault2
```

**`deploy-upgrade.sh <host>`** - Upgrade existing installation
```bash
./scripts/deploy-upgrade.sh vault2.thatsnice.org
```

**`deploy-uninstall.sh <host>`** - Remove installation
```bash
./scripts/deploy-uninstall.sh vault2.thatsnice.org
./scripts/deploy-uninstall.sh vault2 --force  # Skip confirmation
```

### Remote Scripts (executed automatically on server)

- `remote/install-remote.sh` - Performs installation on server
- `remote/upgrade-remote.sh` - Performs upgrade with rollback
- `remote/uninstall-remote.sh` - Removes installation

## Installation

### First-Time Setup

1. **Configure SSH** (on dev machine):
   ```bash
   # Add to ~/.ssh/config
   Host vault2
       HostName vault2.thatsnice.org
       User admin
       IdentityFile ~/.ssh/id_rsa
   ```

2. **Set up passwordless sudo** (on remote server):
   ```bash
   # Add to /etc/sudoers.d/admin
   admin ALL=(ALL) NOPASSWD: ALL
   ```

3. **Run installation**:
   ```bash
   cd /path/to/RentCoordinator
   ./scripts/deploy-install.sh vault2
   ```

4. **Configure the application**:
   ```bash
   ssh vault2
   nano ~/rent-coordinator/config.sh
   # Set SESSION_SECRET, configure SMTP
   sudo systemctl restart rent-coordinator
   ```

### What Installation Does

1. Validates SSH and sudo access
2. Builds project on dev machine
3. Creates deployment package
4. Pushes to `~/rent-coordinator-deploy/` on remote
5. Creates service user `rent-coordinator`
6. Installs Node.js for service user (if not already installed)
7. Copies files to `~/rent-coordinator/`
8. Creates default `config.sh`
9. Installs and starts systemd service
10. Runs health check

## Upgrading

### Safe Upgrade Process

The upgrade script implements a zero-downtime deployment with automatic rollback:

```bash
./scripts/deploy-upgrade.sh vault2
```

**Upgrade Steps:**
1. Validates environment
2. Builds new version locally
3. Pushes to remote
4. **Backs up database** → `backups/backup-TIMESTAMP.json`
5. Stops service
6. Deploys to `dist.new/`
7. **Atomic swap**: `dist` → `dist.old`, `dist.new` → `dist`
8. Starts service
9. **Health check** (port check)
10. If healthy: removes `dist.old`
11. **If unhealthy: automatic rollback**

### Rollback on Failure

If the health check fails after upgrade:
1. Service is stopped
2. `dist/` is removed
3. `dist.old/` becomes `dist/`
4. Service is restarted with old version
5. Exit with error

Your database and config are never touched during upgrades.

### Manual Rollback

If you need to manually rollback:
```bash
ssh vault2
cd ~/rent-coordinator
sudo systemctl stop rent-coordinator
rm -rf dist
mv dist.old dist
sudo systemctl start rent-coordinator
```

## Configuration

Configuration lives in `~/rent-coordinator/config.sh` on the remote server.

**Default config structure:**
```bash
# Server
export PORT=8080
export NODE_ENV=production

# Database
export DB_PATH="$HOME/rent-coordinator/tenant-coordinator.db"

# Authentication
export SESSION_SECRET="CHANGE_ME"

# SMTP (configure when ready for production)
# export SMTP_HOST="smtp.example.com"
# export SMTP_PORT=587
# export SMTP_USER="username"
# export SMTP_PASS="password"
# export EMAIL_FROM="noreply@thatsnice.org"

# Node.js (typically already in PATH on production systems)
# export PATH="/usr/local/bin:$PATH"
```

**After editing config:**
```bash
sudo systemctl restart rent-coordinator
```

## Managing the Service

```bash
# Status
sudo systemctl status rent-coordinator

# Start/Stop/Restart
sudo systemctl start rent-coordinator
sudo systemctl stop rent-coordinator
sudo systemctl restart rent-coordinator

# Logs
sudo journalctl -u rent-coordinator -f          # Follow
sudo journalctl -u rent-coordinator -n 100      # Last 100 lines
sudo journalctl -u rent-coordinator --since today
```

## Backups

Backups are created automatically during upgrades and stored in `~/rent-coordinator/backups/`.

**Manual backup:**
```bash
ssh vault2
cd ~/rent-coordinator
npm run backup > backups/manual-backup.json
```

**Restore from backup:**
```bash
npm run restore backups/backup-YYYY-MM-DD_HH-MM-SS.json
```

**Set up automated backups via rsync:**
```bash
# On your desktop, add to crontab:
0 2 * * * rsync -az vault2:~/rent-coordinator/backups/ ~/rent-coordinator-backups/
```

## Uninstallation

```bash
./scripts/deploy-uninstall.sh vault2
```

This will:
- Stop the service
- Remove application files
- Remove systemd service
- Remove service user
- **Preserve database and backups** in `~/rent-coordinator/`

To completely remove all data:
```bash
ssh vault2 'rm -rf ~/rent-coordinator/'
```

## Troubleshooting

### SSH Connection Fails
```bash
# Test SSH
ssh vault2 'echo "SSH OK"'

# Check SSH config
cat ~/.ssh/config
```

### Sudo Password Prompt
```bash
# Verify passwordless sudo
ssh vault2 'sudo -n true && echo "Sudo OK"'

# Fix: Add to /etc/sudoers.d/username
username ALL=(ALL) NOPASSWD: ALL
```

### Build Fails
```bash
# Check Node.js version
node --version  # Should be 16.17+

# Clean and rebuild
rm -rf dist node_modules
npm install
npm run build
```

### Service Won't Start
```bash
# Check logs
ssh vault2 'sudo journalctl -u rent-coordinator -n 50'

# Check config
ssh vault2 'cat ~/rent-coordinator/config.sh'

# Verify Node.js
ssh vault2 'sudo -u rent-coordinator node --version'
```

### Health Check Fails
```bash
# Check if service is listening
ssh vault2 'sudo ss -tlnp | grep 8080'

# Test health endpoint
ssh vault2 'curl http://localhost:8080/health'

# Check firewall
ssh vault2 'sudo iptables -L -n | grep 8080'
```

## Future: Package-Based Deployment

This deployment system is designed to migrate to .deb/.rpm packages:

```bash
# Future workflow
./scripts/build-deb.sh        # Build .deb package
./scripts/deploy-package.sh vault2 package.deb

# On server
sudo apt install ./rent-coordinator_1.0.0.deb
```

The directory structure (`~/rent-coordinator/` vs `/opt/`) will be easy to adapt.

## SMTP Configuration Reminder

**Before going live**, configure SMTP in `~/rent-coordinator/config.sh`:

```bash
export SMTP_HOST="smtp.example.com"
export SMTP_PORT=587
export SMTP_USER="your-username"
export SMTP_PASS="your-password"
export EMAIL_FROM="noreply@thatsnice.org"
```

Without SMTP configured:
- Development: Verification codes logged to console (journalctl)
- Production: Email sending will fail

Test SMTP configuration after setup:
```bash
# Check logs for verification codes
sudo journalctl -u rent-coordinator -f

# Try logging in at http://your-server:8080/login.html
```
