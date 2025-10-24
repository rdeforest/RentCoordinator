# Disaster Recovery Guide

## Overview

This guide explains how to restore the RentCoordinator system from backups in case of server failure.

## Automated Backups

**Location:** `~/rent-coordinator/backups/` on vault2

Backups are created automatically during upgrades and can be created manually:

```bash
# On vault2
cd ~/rent-coordinator
npm run backup
```

Backups include:
- All database data (SQLite)
- Non-sensitive configuration
- Database schema version

## What's NOT in Backups (Stored in AWS Secrets Manager)

Application secrets are stored in **AWS Secrets Manager** for secure disaster recovery.

### Secrets Location

**Secret Name:** `rent-coordinator/config`
**Region:** `us-west-2`
**ARN:** `arn:aws:secretsmanager:us-west-2:822812818413:secret:rent-coordinator/config-zlAnNB`

### Secrets Included

The secret contains all sensitive configuration:

```json
{
  "SESSION_SECRET": "...",
  "SMTP_HOST": "email-smtp.us-west-2.amazonaws.com",
  "SMTP_PORT": "587",
  "SMTP_USER": "...",
  "SMTP_PASS": "...",
  "EMAIL_FROM": "noreply@defore.st",
  "STRIPE_SECRET_KEY": "sk_test_...",
  "STRIPE_PUBLISHABLE_KEY": "pk_test_..."
}
```

### Retrieving Secrets

```bash
# Retrieve all secrets as JSON
aws secretsmanager get-secret-value \
  --secret-id rent-coordinator/config \
  --region us-west-2 \
  --query 'SecretString' \
  --output text

# Or use the helper script (see scripts/restore-secrets.sh)
./scripts/restore-secrets.sh <server>
```

### AWS Resources

Store these ARNs/IDs for reference:
- ALB ARN: `arn:aws:elasticloadbalancing:us-west-2:822812818413:loadbalancer/app/rent-coordinator/f2b4afbafa85bdb5`
- Target Group ARN: `arn:aws:elasticloadbalancing:us-west-2:822812818413:targetgroup/RentCoordinator/faeeb51824fa4106`
- Route53 Hosted Zone ID: `ZUK6DSCVHUE2Q` (defore.st)
- EC2 Instance: vault2 (i-06a914c47bf8e08da)

## Full Restoration Procedure

### 1. Provision New Server

```bash
# Launch EC2 instance (or equivalent)
# Recommended: Debian/Ubuntu, t3.small or larger
# Node.js 18+ is typically pre-installed or available via:
sudo apt update && sudo apt install -y nodejs npm
```

### 2. Deploy Application

```bash
# From your local machine
cd /path/to/RentCoordinator
./scripts/deploy-install.sh <new-server>
```

### 3. Restore Configuration

Retrieve secrets from AWS Secrets Manager and configure the server:

```bash
# Use the automated restore script (recommended)
./scripts/restore-secrets.sh <new-server>

# Or manually:
# 1. Get secrets from AWS
aws secretsmanager get-secret-value \
  --secret-id rent-coordinator/config \
  --region us-west-2 \
  --query 'SecretString' \
  --output text > /tmp/secrets.json

# 2. SSH to server and update config.sh
ssh <new-server>
sudo -u rent-coordinator bash -c 'cat >> ~/rent-coordinator/config.sh << EOF

# Secrets from AWS Secrets Manager
SESSION_SECRET=$(jq -r .SESSION_SECRET /tmp/secrets.json)
SMTP_HOST=$(jq -r .SMTP_HOST /tmp/secrets.json)
SMTP_PORT=$(jq -r .SMTP_PORT /tmp/secrets.json)
SMTP_USER=$(jq -r .SMTP_USER /tmp/secrets.json)
SMTP_PASS=$(jq -r .SMTP_PASS /tmp/secrets.json)
EMAIL_FROM=$(jq -r .EMAIL_FROM /tmp/secrets.json)
STRIPE_SECRET_KEY=$(jq -r .STRIPE_SECRET_KEY /tmp/secrets.json)
STRIPE_PUBLISHABLE_KEY=$(jq -r .STRIPE_PUBLISHABLE_KEY /tmp/secrets.json)
EOF'
```

### 4. Restore Database

```bash
# Copy backup from old server or S3
scp vault2:~/rent-coordinator/backups/backup-YYYY-MM-DD*.json ./

# Upload to new server
scp backup-*.json <new-server>:~/

# Restore on new server
ssh <new-server>
cd ~/rent-coordinator
npm run restore ~/backup-*.json
```

### 5. Update DNS

Point `rent.thatsnice.org` to new server:

```bash
# Update ALB target or update Route53 A record
aws elbv2 register-targets --target-group-arn <arn> \\
  --targets Id=<new-instance-id>

# Or update Route53 directly if not using ALB
aws route53 change-resource-record-sets --hosted-zone-id ZUK6DSCVHUE2Q \\
  --change-batch file://dns-update.json
```

### 6. Verify

```bash
curl https://rent.thatsnice.org/health
# Should return: {"status":"healthy","timestamp":"..."}
```

## Regular Backup Schedule

**Recommendation:** Set up automated S3 sync for backups:

```bash
# Add to crontab on vault2
0 2 * * * aws s3 sync ~/rent-coordinator/backups/ s3://your-backup-bucket/rent-coordinator/ --delete
```

## Testing Recovery

**Important:** Test disaster recovery procedure annually:

1. Create fresh backup
2. Spin up test server
3. Follow restoration procedure
4. Verify all functionality
5. Document any issues
6. Destroy test server

## Secrets Management

**Secrets are stored in AWS Secrets Manager:**

- **Secret Name:** `rent-coordinator/config`
- **Region:** `us-west-2`
- **Access:** Protected by IAM credentials

**To update secrets:**

```bash
# Get current secret
aws secretsmanager get-secret-value \
  --secret-id rent-coordinator/config \
  --region us-west-2 \
  --query 'SecretString' \
  --output text > secrets.json

# Edit secrets.json as needed

# Update secret
aws secretsmanager update-secret \
  --secret-id rent-coordinator/config \
  --region us-west-2 \
  --secret-string file://secrets.json
```

**Additional items to secure:**

1. AWS access credentials (for Claude Code / disaster recovery access)
2. Server SSH keys
3. Domain registrar credentials

**Never commit secrets to git!**

## Emergency Contacts

- Domain Registrar: (where defore.st is registered)
- AWS Support: (your support plan)
- Stripe Support: https://support.stripe.com

---

Last Updated: 2025-10-21
