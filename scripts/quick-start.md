# RentCoordinator Deployment Quick Start

## Prerequisites Setup (One Time)

### 1. Configure SSH on Dev Machine
```bash
:# Add to ~/.ssh/config
Host vault2
    HostName vault2.thatsnice.org
    User admin
    IdentityFile ~/.ssh/id_rsa
```

### 2. Configure Sudo on Remote Server
```bash
ssh vault2
sudo visudo -f /etc/sudoers.d/admin
:# Add: admin ALL=(ALL) NOPASSWD: ALL
```

## Deploy to Production

### First-Time Installation
```bash
cd /path/to/RentCoordinator
./scripts/deploy-install.sh vault2
```

### Configure Application
```bash
ssh vault2
nano ~/rent-coordinator/config.sh
:# 1. Set SESSION_SECRET to random value
:# 2. Configure SMTP (when ready)
sudo systemctl restart rent-coordinator
```

### Upgrade Existing Installation
```bash
./scripts/deploy-upgrade.sh vault2
```

### Remove Installation
```bash
./scripts/deploy-uninstall.sh vault2
```

## Common Commands

### Check Status
```bash
ssh vault2 'sudo systemctl status rent-coordinator'
```

### View Logs
```bash
ssh vault2 'sudo journalctl -u rent-coordinator -f'
```

### Restart Service
```bash
ssh vault2 'sudo systemctl restart rent-coordinator'
```

### Manual Rollback
```bash
ssh vault2
cd ~/rent-coordinator
sudo systemctl stop rent-coordinator
rm -rf dist
mv dist.old dist
sudo systemctl start rent-coordinator
```

### Create Manual Backup
```bash
ssh vault2 'cd ~/rent-coordinator && npm run backup > backups/manual-$(date +%Y%m%d).json'
```

## SMTP Configuration (Before Go-Live!)

Edit `~/rent-coordinator/config.sh` on production:
```bash
export SMTP_HOST="smtp.example.com"
export SMTP_PORT=587
export SMTP_USER="username"
export SMTP_PASS="password"
export EMAIL_FROM="noreply@thatsnice.org"
```

Without SMTP: Verification codes are logged to journalctl (dev only)

## Troubleshooting

### Build Fails
```bash
rm -rf dist node_modules
npm install
npm run build
```

### Can't SSH
```bash
ssh -v vault2    # Verbose debugging
```

### Service Won't Start
```bash
ssh vault2 'sudo journalctl -u rent-coordinator -n 100'
```

### Health Check Fails
```bash
ssh vault2 'curl http://localhost:8080/health'
```

## Full Documentation

See `scripts/deployment.md` for complete guide.
