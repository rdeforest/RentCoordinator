# RentCoordinator Deployment Guide

The production deployment is **AWS CloudFormation** with an Auto Scaling Group behind an
Application Load Balancer. The instance runs Debian 12, pulls code from GitHub on boot,
and starts the app via systemd.

See `infrastructure/README.md` for the authoritative guide.

## Quick Reference

### Deploy / Update Stack

```bash
cd infrastructure
./deploy.sh deploy
```

### Find Current Instance IP

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=RentCoordinator-production" \
  --query 'Reservations[*].Instances[*].PublicIpAddress'
```

### Restart App on Running Instance

```bash
ssh -i ~/.ssh/id_aws_rdeforest admin@<INSTANCE_IP> \
  "sudo systemctl restart rent-coordinator"
```

### View Live Logs

```bash
aws logs tail /rent-coordinator/application --follow
```

## Auto Scaling

- Min/Max/Desired: 1/3/1 (single instance in practice)
- `ReplaceUnhealthy` process is **suspended** — a failing health check will not
  trigger instance termination. The instance stays up (unhealthy) until manually
  acted on. This prevents data loss from cycling instances before a replacement
  is healthy.
- Health check grace period: 480 seconds (8 minutes)

To manually suspend/resume termination behavior:

```bash
# Suspend (current default — already applied)
aws autoscaling suspend-processes \
  --auto-scaling-group-name RentCoordinator-production \
  --scaling-processes ReplaceUnhealthy

# Re-enable if desired
aws autoscaling resume-processes \
  --auto-scaling-group-name RentCoordinator-production \
  --scaling-processes ReplaceUnhealthy
```

## Prerequisites (for a fresh install)

- Node.js 24 LTS (managed via nvm)
- CoffeeScript (`npm install -g coffeescript`)
- Git

The CloudFormation user data script handles all of this automatically on instance launch.

## Running Locally

```bash
# Install dependencies
npm install

# Start server (also compiles client CoffeeScript on startup)
npm start
```

No separate build step. Client-side CoffeeScript is compiled to `static/js/` on every startup.

## Environment Variables

| Variable              | Default                    | Notes                          |
|-----------------------|----------------------------|--------------------------------|
| `PORT`                | 3000                       |                                |
| `NODE_ENV`            | development                | Set to `production` in prod    |
| `DB_PATH`             | ./tenant-coordinator.db    | SQLite file path               |
| `SESSION_SECRET`      | (required in production)   | From AWS Secrets Manager       |
| `SMTP_HOST`           | (optional in dev)          | AWS SES SMTP in production     |
| `SMTP_PORT`           | 587                        |                                |
| `SMTP_USER`           |                            |                                |
| `SMTP_PASS`           |                            |                                |
| `EMAIL_FROM`          | noreply@thatsnice.org      |                                |
| `STRIPE_SECRET_KEY`   |                            | sk_live_... in production      |
| `STRIPE_PUBLISHABLE_KEY` |                         | pk_live_... in production      |

Production secrets are stored in AWS Secrets Manager under `rent-coordinator/config` (us-west-2).

## Database

- SQLite via Node.js built-in `node:sqlite` module (requires Node 22+)
- Database file: `./tenant-coordinator.db` (configurable via `DB_PATH`)
- Schema initialized on startup in `lib/db/schema.coffee`

## Backups

Backups are triggered on-demand — there is no automatic scheduler yet.

```bash
# Trigger backup (local + S3 upload)
curl -X POST http://localhost:3000/api/backup

# Check status / last backup time
curl http://localhost:3000/api/backup/status

# List all S3 backups
curl http://localhost:3000/api/backup/list

# Restore from latest S3 backup
curl -X POST http://localhost:3000/api/backup/restore
```

S3 bucket: `rent-coordinator-backups-822812818413` (us-west-2), 30-day retention.

## Health Check

```bash
curl http://localhost:3000/health
```

## Process Management

The app runs as a systemd service (`rent-coordinator.service`) on the EC2 instance.
Logs flow to journald → `/var/log/rent-coordinator/application.log` → CloudWatch Logs
(`/rent-coordinator/application`).

## Security

- Non-root service user (`rent-coordinator`)
- Secrets via AWS Secrets Manager (never in source)
- HTTPS terminated at the ALB
- Email auth with 90-day sessions (2-user whitelist)
