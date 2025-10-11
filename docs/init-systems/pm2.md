# PM2 Process Manager

## External Documentation

- [PM2 Official Documentation](https://pm2.keymetrics.io/docs/)
- [PM2 Quick Start Guide](https://pm2.keymetrics.io/docs/usage/quick-start/)
- [PM2 Ecosystem File](https://pm2.keymetrics.io/docs/usage/application-declaration/)

## Installation

```bash
# Install PM2 globally via npm
npm install -g pm2

# Or using Deno (if available)
deno install --allow-read --allow-write --allow-env --allow-net --allow-run --allow-sys --name pm2 npm:pm2
```

## PM2 Ecosystem File

Create `/opt/rentcoordinator/ecosystem.config.js`:

```javascript
module.exports = {
  apps: [{
    name: 'rentcoordinator',
    script: '/home/rentcoordinator/.deno/bin/deno',
    args: 'run --allow-read --allow-write --allow-env --allow-net --unstable-kv dist/main.js',
    cwd: '/opt/rentcoordinator',
    interpreter: 'none',
    env: {
      PORT: 3000,
      DB_PATH: '/var/lib/rentcoordinator/db.kv',
      NODE_ENV: 'production'
    },
    error_file: '/var/log/rentcoordinator/pm2-error.log',
    out_file: '/var/log/rentcoordinator/pm2-out.log',
    log_file: '/var/log/rentcoordinator/pm2-combined.log',
    time: true,
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    min_uptime: '10s',
    max_restarts: 10
  }]
};
```

## Common Commands

```bash
# Start application
pm2 start ecosystem.config.js

# Or directly
pm2 start "deno run --allow-read --allow-write --allow-env --allow-net --unstable-kv dist/main.js" --name rentcoordinator

# List processes
pm2 list

# Monitor processes
pm2 monit

# View logs
pm2 logs rentcoordinator

# Stop application
pm2 stop rentcoordinator

# Restart application
pm2 restart rentcoordinator

# Delete from PM2
pm2 delete rentcoordinator

# Save PM2 process list
pm2 save

# Setup PM2 to start on boot
pm2 startup
# Follow the instructions it provides

# View detailed information
pm2 describe rentcoordinator

# Zero-downtime reload
pm2 reload rentcoordinator
```

## PM2 with Clustering

For multiple instances (load balancing):

```javascript
// In ecosystem.config.js
instances: 'max', // or specific number like 4
exec_mode: 'cluster'
```

## Monitoring

```bash
# Real-time monitoring dashboard
pm2 monit

# Web-based monitoring (PM2 Plus)
pm2 link <secret_key> <public_key>
```