# RentCoordinator Deployment Guide

This guide provides init-system agnostic instructions for deploying RentCoordinator to a production environment.

## Table of Contents
- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Automated Installation](#automated-installation)
- [Manual Installation](#manual-installation)
- [Configuration](#configuration)
- [Running the Application](#running-the-application)
- [Process Management](#process-management)
- [Web Server Setup](#web-server-setup)
- [Database Management](#database-management)
- [Monitoring & Maintenance](#monitoring--maintenance)
- [Troubleshooting](#troubleshooting)

## Quick Start

For automated installation, run:
```bash
curl -fsSL https://raw.githubusercontent.com/rdeforest/RentCoordinator/main/scripts/install.sh | bash
```

Or download and review first:
```bash
wget https://raw.githubusercontent.com/rdeforest/RentCoordinator/main/scripts/install.sh
chmod +x install.sh
./install.sh
```

## Prerequisites

### System Requirements
- Linux-based OS (tested on Ubuntu, Debian, RHEL, Alpine)
- Minimum 1GB RAM, 2GB recommended
- 10GB free disk space
- Network connectivity for package installation

### Required Software
- Deno v1.40 or newer
- Git for source management
- curl or wget for downloads
- A process manager (see [Process Management](#process-management))

## Automated Installation

The installation script handles:
- Dependency installation (Deno)
- User account creation
- Directory setup
- Repository cloning
- Initial build
- Basic configuration

Run with options:
```bash
:# Custom installation directory
./install.sh --prefix /usr/local

:# Custom user
./install.sh --user myapp

:# Custom port
./install.sh --port 8080

:# Skip user creation (use current user)
./install.sh --skip-user

:# All options
./install.sh --prefix /opt/apps --user webapp --port 8080
```

## Manual Installation

### 1. Create Application User (Optional but Recommended)
```bash
:# Create dedicated user
useradd -m -s /bin/bash rentcoordinator

:# Or on systems without useradd
adduser rentcoordinator
```

### 2. Create Directory Structure
```bash
:# Application directories
mkdir -p /opt/rentcoordinator
mkdir -p /var/log/rentcoordinator
mkdir -p /var/lib/rentcoordinator

:# Set ownership (if using dedicated user)
chown -R rentcoordinator:rentcoordinator /opt/rentcoordinator
chown -R rentcoordinator:rentcoordinator /var/log/rentcoordinator
chown -R rentcoordinator:rentcoordinator /var/lib/rentcoordinator
```

### 3. Install Deno
```bash
:# As the application user
su - rentcoordinator

:# Install Deno
curl -fsSL https://deno.land/install.sh | sh

:# Add to PATH (add to ~/.bashrc or ~/.profile for persistence)
export DENO_INSTALL="$HOME/.deno"
export PATH="$DENO_INSTALL/bin:$PATH"

:# Verify
deno --version
```

### 4. Clone and Build
```bash
:# Clone repository
cd /opt/rentcoordinator
git clone https://github.com/rdeforest/RentCoordinator.git .

:# Build application
deno task build
```

## Configuration

### Environment Configuration
Create `/opt/rentcoordinator/.env`:
```bash
:# Server Configuration
PORT=3000
HOST=0.0.0.0

:# Database Configuration
DB_PATH=/var/lib/rentcoordinator/db.kv

:# Application Settings
NODE_ENV=production
LOG_LEVEL=info

:# Optional: Custom workers
:# WORKERS=robert,lyndzie
```

### Application Configuration
The application reads configuration from:
1. Environment variables
2. `.env` file in application root
3. Default values in `lib/config.coffee`

## Running the Application

### Direct Execution
```bash
cd /opt/rentcoordinator

:# Using deno task
deno task start

:# Or directly
deno run --allow-read --allow-write --allow-env --allow-net --unstable-kv dist/main.js
```

### Background Execution
```bash
:# Using nohup
nohup deno task start > /var/log/rentcoordinator/app.log 2>&1 &

:# Save PID for management
echo $! > /var/run/rentcoordinator.pid
```

### With Environment Variables
```bash
PORT=3000 DB_PATH=/custom/path/db.kv deno task start
```

## Process Management

The application can be managed by various init systems and process managers:

### Init System Guides
- **systemd**: [docs/init-systems/systemd.md](init-systems/systemd.md)
- **OpenRC**: [docs/init-systems/openrc.md](init-systems/openrc.md)
- **runit**: [docs/init-systems/runit.md](init-systems/runit.md)
- **SysV init**: [docs/init-systems/sysvinit.md](init-systems/sysvinit.md)
- **Upstart**: [docs/init-systems/upstart.md](init-systems/upstart.md)

### Process Managers
- **PM2**: [docs/init-systems/pm2.md](init-systems/pm2.md)
- **Supervisor**: [docs/init-systems/supervisor.md](init-systems/supervisor.md)
- **Docker**: [docs/init-systems/docker.md](init-systems/docker.md)

### Generic Start/Stop Script
Create `/opt/rentcoordinator/bin/rentcoordinator`:
```bash
#!/bin/bash

APP_DIR="/opt/rentcoordinator"
PID_FILE="/var/run/rentcoordinator.pid"
LOG_FILE="/var/log/rentcoordinator/app.log"
USER="rentcoordinator"

start() {
    if [ -f $PID_FILE ] && kill -0 $(cat $PID_FILE) 2>/dev/null; then
        echo "RentCoordinator is already running"
        return 1
    fi

    echo "Starting RentCoordinator..."
    cd $APP_DIR
    su - $USER -c "cd $APP_DIR && nohup deno task start > $LOG_FILE 2>&1 & echo \$! > $PID_FILE"
    echo "RentCoordinator started"
}

stop() {
    if [ ! -f $PID_FILE ]; then
        echo "RentCoordinator is not running"
        return 1
    fi

    echo "Stopping RentCoordinator..."
    kill $(cat $PID_FILE)
    rm -f $PID_FILE
    echo "RentCoordinator stopped"
}

restart() {
    stop
    sleep 2
    start
}

status() {
    if [ -f $PID_FILE ] && kill -0 $(cat $PID_FILE) 2>/dev/null; then
        echo "RentCoordinator is running (PID: $(cat $PID_FILE))"
    else
        echo "RentCoordinator is not running"
        rm -f $PID_FILE
    fi
}

case "$1" in
    start)   start ;;
    stop)    stop ;;
    restart) restart ;;
    status)  status ;;
    *)       echo "Usage: $0 {start|stop|restart|status}" ;;
esac
```

Make it executable:
```bash
chmod +x /opt/rentcoordinator/bin/rentcoordinator
```

## Web Server Setup

### Nginx Reverse Proxy
See [docs/nginx.md](nginx.md) for detailed Nginx configuration.

Basic setup:
```nginx
server {
    listen 80;
    server_name rentcoordinator.example.com;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Apache Reverse Proxy
```apache
<VirtualHost *:80>
    ServerName rentcoordinator.example.com

    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:3000/
    ProxyPassReverse / http://127.0.0.1:3000/
</VirtualHost>
```

### Caddy
```caddyfile
rentcoordinator.example.com {
    reverse_proxy localhost:3000
}
```

## Database Management

### Database Location
- Default: `/var/lib/rentcoordinator/db.kv`
- Configurable via `DB_PATH` environment variable
- Uses Deno KV (key-value store)

### Backup Script
Create `/opt/rentcoordinator/scripts/backup.sh`:
```bash
#!/bin/bash

BACKUP_DIR="/var/backups/rentcoordinator"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_PATH="${DB_PATH:-/var/lib/rentcoordinator/db.kv}"
PID_FILE="/var/run/rentcoordinator.pid"

:# Create backup directory
mkdir -p "$BACKUP_DIR"

:# Optional: Stop application for consistency
if [ -f "$PID_FILE" ]; then
    echo "Stopping application for backup..."
    kill $(cat "$PID_FILE")
    sleep 2
fi

:# Create backup
cp -r "$DB_PATH" "$BACKUP_DIR/db_${TIMESTAMP}.kv"

:# Restart if it was running
if [ -f "$PID_FILE" ]; then
    echo "Restarting application..."
    /opt/rentcoordinator/bin/rentcoordinator start
fi

:# Clean old backups (keep 30 days)
find "$BACKUP_DIR" -name "db_*.kv" -mtime +30 -delete

echo "Backup completed: $BACKUP_DIR/db_${TIMESTAMP}.kv"
```

### Restore Script
Create `/opt/rentcoordinator/scripts/restore.sh`:
```bash
#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <backup_file>"
    exit 1
fi

BACKUP_FILE="$1"
DB_PATH="${DB_PATH:-/var/lib/rentcoordinator/db.kv}"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Backup file not found: $BACKUP_FILE"
    exit 1
fi

:# Stop application
/opt/rentcoordinator/bin/rentcoordinator stop

:# Backup current database
cp -r "$DB_PATH" "${DB_PATH}.before_restore"

:# Restore
cp -r "$BACKUP_FILE" "$DB_PATH"

:# Start application
/opt/rentcoordinator/bin/rentcoordinator start

echo "Database restored from $BACKUP_FILE"
```

## Monitoring & Maintenance

### Health Check
```bash
:# Basic health check
curl -f http://localhost:3000/health || echo "Service is down"

:# With timeout
timeout 5 curl -f http://localhost:3000/health || echo "Service is down or slow"
```

### Log Management
Create `/opt/rentcoordinator/scripts/rotate-logs.sh`:
```bash
#!/bin/bash

LOG_DIR="/var/log/rentcoordinator"
MAX_SIZE="100M"
MAX_DAYS=14

:# Rotate if size exceeds limit
for log in "$LOG_DIR"/*.log; do
    if [ -f "$log" ]; then
        size=$(du -h "$log" | cut -f1)
        if [ "${size%M}" -gt "${MAX_SIZE%M}" ]; then
            mv "$log" "$log.$(date +%Y%m%d)"
            touch "$log"
        fi
    fi
done

:# Delete old logs
find "$LOG_DIR" -name "*.log.*" -mtime +$MAX_DAYS -delete
```

Add to crontab:
```bash
:# Daily log rotation at 2 AM
0 2 * * * /opt/rentcoordinator/scripts/rotate-logs.sh
```

### Monitoring Script
Create `/opt/rentcoordinator/scripts/monitor.sh`:
```bash
#!/bin/bash

URL="http://localhost:3000/health"
ALERT_EMAIL="admin@example.com"
PID_FILE="/var/run/rentcoordinator.pid"

:# Check if process is running
if [ -f "$PID_FILE" ] && ! kill -0 $(cat "$PID_FILE") 2>/dev/null; then
    echo "Process is dead but PID file exists. Attempting restart..."
    /opt/rentcoordinator/bin/rentcoordinator restart
    sleep 5
fi

:# Check HTTP endpoint
if ! curl -f -m 10 "$URL" > /dev/null 2>&1; then
    echo "Health check failed. Attempting restart..."
    /opt/rentcoordinator/bin/rentcoordinator restart

    :# Optional: Send alert
    :# echo "RentCoordinator health check failed and was restarted" | mail -s "RentCoordinator Alert" "$ALERT_EMAIL"
fi
```

Add to crontab for monitoring every 5 minutes:
```bash
*/5 * * * * /opt/rentcoordinator/scripts/monitor.sh
```

## Troubleshooting

### Application Won't Start

1. **Check if port is in use:**
```bash
lsof -i :3000
:# or
netstat -tlnp | grep :3000
```

2. **Verify Deno installation:**
```bash
which deno
deno --version
```

3. **Check permissions:**
```bash
ls -la /opt/rentcoordinator/
ls -la /var/lib/rentcoordinator/
ls -la /var/log/rentcoordinator/
```

4. **Test manual startup:**
```bash
cd /opt/rentcoordinator
deno run --allow-read --allow-write --allow-env --allow-net --unstable-kv dist/main.js
```

### Database Issues

1. **Check database file:**
```bash
ls -la /var/lib/rentcoordinator/db.kv
```

2. **Verify disk space:**
```bash
df -h /var/lib/rentcoordinator
```

3. **Check database path in environment:**
```bash
echo $DB_PATH
grep DB_PATH /opt/rentcoordinator/.env
```

### Build Failures

1. **Clear and rebuild:**
```bash
cd /opt/rentcoordinator
rm -rf dist/
rm -rf node_modules/
deno task build
```

2. **Check for build errors:**
```bash
deno task build 2>&1 | tee build.log
```

### Performance Issues

1. **Check resource usage:**
```bash
:# CPU and memory
top -p $(cat /var/run/rentcoordinator.pid)

:# Open files
lsof -p $(cat /var/run/rentcoordinator.pid) | wc -l
```

2. **Check logs for errors:**
```bash
tail -f /var/log/rentcoordinator/app.log
```

3. **Increase memory limit if needed:**
```bash
:# Set V8 heap size
export DENO_V8_FLAGS="--max-old-space-size=2048"
```

### Debug Mode

For detailed debugging:
```bash
:# Stop normal service
/opt/rentcoordinator/bin/rentcoordinator stop

:# Run with debug output
cd /opt/rentcoordinator
DENO_LOG=debug deno run --allow-read --allow-write --allow-env --allow-net --unstable-kv dist/main.js
```

## Security Recommendations

1. **Run as non-root user**
2. **Use a firewall** (iptables, ufw, firewalld)
3. **Enable HTTPS** via reverse proxy
4. **Keep Deno updated**
5. **Regular backups**
6. **Monitor logs for suspicious activity**

## Support

- GitHub: https://github.com/rdeforest/RentCoordinator
- Issues: https://github.com/rdeforest/RentCoordinator/issues
- Deno Manual: https://deno.land/manual