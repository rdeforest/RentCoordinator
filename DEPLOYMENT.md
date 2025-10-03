# RentCoordinator Deployment Guide

This document provides comprehensive instructions for deploying RentCoordinator to a production environment.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Server Requirements](#server-requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Systemd Service Setup](#systemd-service-setup)
- [Nginx Reverse Proxy](#nginx-reverse-proxy)
- [Database Management](#database-management)
- [Monitoring & Maintenance](#monitoring--maintenance)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### System Requirements
- Ubuntu 20.04 LTS or newer (tested on Ubuntu 22.04)
- Minimum 1GB RAM, 2GB recommended
- 10GB free disk space
- Port 3000 available (or configured alternative)

### Required Software
- Deno v1.40 or newer
- Node.js 18+ and npm (for build tools)
- Git for source code management
- systemd for service management
- nginx (optional, for reverse proxy)

## Server Requirements

### User Account Setup
```bash
# Create dedicated user for the application
sudo useradd -m -s /bin/bash rentcoordinator
sudo passwd rentcoordinator

# Add user to necessary groups
sudo usermod -aG systemd-journal rentcoordinator
```

### Directory Structure
```bash
# Create application directories
sudo mkdir -p /opt/rentcoordinator
sudo mkdir -p /var/log/rentcoordinator
sudo mkdir -p /var/lib/rentcoordinator

# Set ownership
sudo chown -R rentcoordinator:rentcoordinator /opt/rentcoordinator
sudo chown -R rentcoordinator:rentcoordinator /var/log/rentcoordinator
sudo chown -R rentcoordinator:rentcoordinator /var/lib/rentcoordinator
```

## Installation

### 1. Install Deno
```bash
# Install Deno
curl -fsSL https://deno.land/install.sh | sh

# Add to PATH (add to ~/.bashrc for persistence)
export DENO_INSTALL="/home/rentcoordinator/.deno"
export PATH="$DENO_INSTALL/bin:$PATH"

# Verify installation
deno --version
```

### 2. Install Node.js and npm (for build tools)
```bash
# Using NodeSource repository
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify installation
node --version
npm --version
```

### 3. Clone Repository
```bash
# Switch to application user
sudo su - rentcoordinator

# Clone the repository
cd /opt/rentcoordinator
git clone https://github.com/rdeforest/RentCoordinator.git .

# Or if using SSH
git clone git@github.com:rdeforest/RentCoordinator.git .
```

### 4. Build Application
```bash
# Install dependencies and build
cd /opt/rentcoordinator

# Build the application
npm run build
# or
deno task build

# Verify build output
ls -la dist/
```

## Configuration

### Environment Variables
Create `/opt/rentcoordinator/.env` file:
```bash
# Server Configuration
PORT=3000
HOST=0.0.0.0

# Database Configuration
DB_PATH=/var/lib/rentcoordinator/db.kv

# Application Settings
NODE_ENV=production
LOG_LEVEL=info

# Workers (comma-separated list if customizing)
# WORKERS=robert,lyndzie
```

### Application Configuration
Edit `/opt/rentcoordinator/lib/config.coffee` if needed:
```coffeescript
# Modify default values as needed
export config =
  port: process.env.PORT or 3000
  dbPath: process.env.DB_PATH or '/var/lib/rentcoordinator/db.kv'
  workers: process.env.WORKERS?.split(',') or ['robert', 'lyndzie']
```

## Systemd Service Setup

### Create Service File
Create `/etc/systemd/system/rentcoordinator.service`:
```ini
[Unit]
Description=RentCoordinator Application
After=network.target
Documentation=https://github.com/rdeforest/RentCoordinator

[Service]
Type=simple
User=rentcoordinator
Group=rentcoordinator
WorkingDirectory=/opt/rentcoordinator

# Environment
Environment="NODE_ENV=production"
Environment="PORT=3000"
Environment="DB_PATH=/var/lib/rentcoordinator/db.kv"
Environment="DENO_INSTALL=/home/rentcoordinator/.deno"
Environment="PATH=/home/rentcoordinator/.deno/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Start command
ExecStart=/home/rentcoordinator/.deno/bin/deno run --allow-read --allow-write --allow-env --allow-net --unstable-kv /opt/rentcoordinator/dist/main.js

# Restart policy
Restart=always
RestartSec=10

# Logging
StandardOutput=append:/var/log/rentcoordinator/app.log
StandardError=append:/var/log/rentcoordinator/error.log

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/var/lib/rentcoordinator /var/log/rentcoordinator

[Install]
WantedBy=multi-user.target
```

### Enable and Start Service
```bash
# Reload systemd configuration
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable rentcoordinator

# Start the service
sudo systemctl start rentcoordinator

# Check service status
sudo systemctl status rentcoordinator

# View logs
sudo journalctl -u rentcoordinator -f
```

## Nginx Reverse Proxy

### Install Nginx
```bash
sudo apt update
sudo apt install nginx
```

### Configure Nginx
Create `/etc/nginx/sites-available/rentcoordinator`:
```nginx
server {
    listen 80;
    server_name rentcoordinator.example.com;

    # Redirect to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name rentcoordinator.example.com;

    # SSL Configuration (update paths to your certificates)
    ssl_certificate /etc/letsencrypt/live/rentcoordinator.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/rentcoordinator.example.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Logging
    access_log /var/log/nginx/rentcoordinator.access.log;
    error_log /var/log/nginx/rentcoordinator.error.log;

    # Proxy settings
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Static file caching (optional)
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
        proxy_pass http://127.0.0.1:3000;
        expires 1d;
        add_header Cache-Control "public, immutable";
    }
}
```

### Enable Site
```bash
# Enable the site
sudo ln -s /etc/nginx/sites-available/rentcoordinator /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx
```

### SSL Certificate with Let's Encrypt
```bash
# Install Certbot
sudo apt install certbot python3-certbot-nginx

# Obtain certificate
sudo certbot --nginx -d rentcoordinator.example.com

# Auto-renewal is configured automatically
sudo certbot renew --dry-run
```

## Database Management

### Database Location
The application uses Deno KV store located at:
- Default: `/var/lib/rentcoordinator/db.kv`
- Configurable via `DB_PATH` environment variable

### Backup Database
```bash
#!/bin/bash
# Create backup script at /opt/rentcoordinator/scripts/backup.sh

BACKUP_DIR="/var/backups/rentcoordinator"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_PATH="/var/lib/rentcoordinator/db.kv"

# Create backup directory
mkdir -p $BACKUP_DIR

# Stop service temporarily (optional, for consistency)
sudo systemctl stop rentcoordinator

# Create backup
cp -r $DB_PATH $BACKUP_DIR/db_${TIMESTAMP}.kv

# Restart service
sudo systemctl start rentcoordinator

# Remove backups older than 30 days
find $BACKUP_DIR -name "db_*.kv" -mtime +30 -delete

echo "Backup completed: $BACKUP_DIR/db_${TIMESTAMP}.kv"
```

### Restore Database
```bash
#!/bin/bash
# Restore script at /opt/rentcoordinator/scripts/restore.sh

if [ -z "$1" ]; then
    echo "Usage: ./restore.sh <backup_file>"
    exit 1
fi

BACKUP_FILE=$1
DB_PATH="/var/lib/rentcoordinator/db.kv"

# Stop service
sudo systemctl stop rentcoordinator

# Backup current database
cp -r $DB_PATH ${DB_PATH}.before_restore

# Restore from backup
cp -r $BACKUP_FILE $DB_PATH

# Set correct permissions
chown -R rentcoordinator:rentcoordinator $DB_PATH

# Restart service
sudo systemctl start rentcoordinator

echo "Database restored from $BACKUP_FILE"
```

### Automated Backups (Cron)
```bash
# Add to rentcoordinator user's crontab
crontab -e

# Daily backup at 2 AM
0 2 * * * /opt/rentcoordinator/scripts/backup.sh >> /var/log/rentcoordinator/backup.log 2>&1
```

## Monitoring & Maintenance

### Health Check Endpoint
The application provides a health check endpoint at `/health`:
```bash
# Check application health
curl http://localhost:3000/health
```

### Log Rotation
Create `/etc/logrotate.d/rentcoordinator`:
```
/var/log/rentcoordinator/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 644 rentcoordinator rentcoordinator
    sharedscripts
    postrotate
        systemctl reload rentcoordinator > /dev/null 2>&1 || true
    endscript
}
```

### Monitoring with Systemd
```bash
# View service logs
journalctl -u rentcoordinator -f

# Check service status
systemctl status rentcoordinator

# View recent logs
journalctl -u rentcoordinator --since "1 hour ago"

# Check resource usage
systemctl show rentcoordinator --property=CPUUsageNSec,MemoryCurrent
```

### Application Updates
```bash
#!/bin/bash
# Update script at /opt/rentcoordinator/scripts/update.sh

cd /opt/rentcoordinator

# Pull latest code
git pull origin main

# Rebuild application
npm run build

# Restart service
sudo systemctl restart rentcoordinator

echo "Application updated and restarted"
```

## Troubleshooting

### Common Issues

#### Service Won't Start
```bash
# Check service status
sudo systemctl status rentcoordinator

# Check logs
sudo journalctl -u rentcoordinator -n 50

# Verify permissions
ls -la /opt/rentcoordinator
ls -la /var/lib/rentcoordinator
ls -la /var/log/rentcoordinator

# Test manual startup
cd /opt/rentcoordinator
sudo -u rentcoordinator deno run --allow-read --allow-write --allow-env --allow-net --unstable-kv dist/main.js
```

#### Database Issues
```bash
# Check database file permissions
ls -la /var/lib/rentcoordinator/db.kv

# Verify database path in environment
grep DB_PATH /etc/systemd/system/rentcoordinator.service

# Check disk space
df -h /var/lib/rentcoordinator
```

#### Build Failures
```bash
# Clear build cache
rm -rf dist/
rm -rf node_modules/
rm -rf .deno/

# Reinstall and rebuild
npm install
npm run build

# Check Deno version
deno --version
```

#### Port Already in Use
```bash
# Find process using port 3000
sudo lsof -i :3000
# or
sudo netstat -tulpn | grep :3000

# Kill the process if needed
sudo kill -9 <PID>

# Or change port in configuration
# Edit /etc/systemd/system/rentcoordinator.service
# Change Environment="PORT=3001"
```

#### Permission Denied Errors
```bash
# Fix ownership
sudo chown -R rentcoordinator:rentcoordinator /opt/rentcoordinator
sudo chown -R rentcoordinator:rentcoordinator /var/lib/rentcoordinator
sudo chown -R rentcoordinator:rentcoordinator /var/log/rentcoordinator

# Fix permissions
sudo chmod -R 755 /opt/rentcoordinator
sudo chmod -R 755 /var/lib/rentcoordinator
sudo chmod -R 755 /var/log/rentcoordinator
```

### Debug Mode
To run in debug mode for troubleshooting:
```bash
# Stop service
sudo systemctl stop rentcoordinator

# Run manually with verbose output
cd /opt/rentcoordinator
sudo -u rentcoordinator DENO_LOG=debug deno run --allow-read --allow-write --allow-env --allow-net --unstable-kv dist/main.js
```

### Performance Tuning

#### System Limits
Add to `/etc/security/limits.d/rentcoordinator.conf`:
```
rentcoordinator soft nofile 4096
rentcoordinator hard nofile 8192
rentcoordinator soft nproc 512
rentcoordinator hard nproc 1024
```

#### Deno Flags
For better performance, add to service file:
```ini
Environment="DENO_V8_FLAGS=--max-old-space-size=2048"
```

## Security Considerations

### Firewall Rules
```bash
# Allow HTTP and HTTPS if using Nginx
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Or allow direct access to app port (not recommended for production)
# sudo ufw allow 3000/tcp

# Enable firewall
sudo ufw enable
```

### Application Security
- Run as non-root user (rentcoordinator)
- Use systemd security features (PrivateTmp, ProtectHome, etc.)
- Keep Deno and dependencies updated
- Use HTTPS in production
- Implement rate limiting in Nginx
- Regular security updates: `sudo apt update && sudo apt upgrade`

## Support and Resources

- GitHub Repository: https://github.com/rdeforest/RentCoordinator
- Issues: https://github.com/rdeforest/RentCoordinator/issues
- Deno Documentation: https://deno.land/manual
- Systemd Documentation: https://www.freedesktop.org/software/systemd/man/