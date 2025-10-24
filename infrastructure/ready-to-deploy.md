# Ready to Deploy - rent01 Instance

## Summary of Changes

### ✅ Documentation Updated
- All references changed from Deno/Deno KV → Node.js/SQLite
- Updated all init-system docs (systemd, docker, pm2, etc.)
- CloudFormation infrastructure automation added

### ✅ S3 Database Sync Added
**New Features:**
- API endpoints for backup/restore operations
- Automatic S3 upload when backups are created
- Automatic S3 restore on instance startup
- Multi-instance data synchronization

**API Endpoints:**
- `POST /api/backup` - Create backup (local + S3)
- `GET /api/backup/list` - List S3 backups
- `POST /api/backup/restore` - Restore from S3
- `GET /api/backup/status` - Check backup system status

### ✅ AWS Infrastructure Created
**CloudFormation Template:**
- S3 bucket for database backups (with versioning and lifecycle)
- Launch Template with automated bootstrap from GitHub
- Auto Scaling Group (1-3 instances)
- IAM roles with Secrets Manager + S3 permissions
- Security Groups for app and ALB
- Target Group auto-registration

**Bootstrap Process:**
1. Clone from GitHub
2. Install Node.js dependencies
3. Build client-side assets
4. Retrieve secrets from Secrets Manager
5. Restore latest database from S3 (if available)
6. Start application
7. Register with Target Group

### ✅ Configuration Ready
**parameters.json created with:**
- VPC: vpc-894a9ced (from vault2)
- Subnets: subnet-5d815839 (us-west-2a), subnet-5d90622b (us-west-2b)
- KeyName: rdeforest
- Target Group: RentCoordinator
- Secrets Manager: rent-coordinator/config

## Deployment Workflow

### Step 1: Test on vault2 (Optional but Recommended)

First, test the backup/restore functionality on vault2:

```bash
:# SSH to vault2
ssh vault2

:# Go to application directory
cd ~/rent-coordinator

:# Pull latest changes (including new backup service)
git pull

:# Install AWS SDK
npm install

:# Test creating a backup
curl -X POST http://localhost:3000/api/backup

:# Check backup status
curl http://localhost:3000/api/backup/status

:# List backups in S3
curl http://localhost:3000/api/backup/list
```

This will:
- Upload vault2's database to S3
- Verify S3 permissions work
- Provide a backup for rent01 to restore from

### Step 2: Deploy rent01 Infrastructure

```bash
:# From your local machine
cd infrastructure

:# Deploy CloudFormation stack
./deploy.sh deploy

:# Monitor deployment (takes ~5-10 minutes)
watch -n 10 './deploy.sh status'
```

**What happens:**
1. Creates S3 bucket: `rent-coordinator-backups-822812818413`
2. Creates IAM roles and security groups
3. Launches first instance (rent01)
4. Instance boots, clones GitHub, installs deps
5. Instance restores database from S3 (uploaded from vault2)
6. Instance starts application
7. Instance registers with Target Group
8. Both vault2 and rent01 now serve traffic

### Step 3: Verify rent01

```bash
:# Check instance status
./deploy.sh instances

:# Get rent01 instance ID
INSTANCE_ID=$(./deploy.sh instances | grep i- | awk '{print $1}' | head -1)

:# Check target health (both should be healthy)
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:us-west-2:822812818413:targetgroup/RentCoordinator/faeeb51824fa4106

:# SSH to rent01 and check logs
aws ssm start-session --target $INSTANCE_ID
:# Or use regular SSH if you prefer
```

### Step 4: Test Application

```bash
:# Test health endpoint
curl https://rentcoordinator.defore.st/health

:# Test backup API (should work on rent01)
curl https://rentcoordinator.defore.st/api/backup/status
```

### Step 5: Traffic Management (When Ready)

**Current State:** Both vault2 and rent01 are in the target group, splitting traffic 50/50

**To send all traffic to rent01:**
```bash
:# Remove vault2 from target group
aws elbv2 deregister-targets \
  --target-group-arn arn:aws:elasticloadbalancing:us-west-2:822812818413:targetgroup/RentCoordinator/faeeb51824fa4106 \
  --targets Id=i-06a914c47bf8e08da
```

**To rollback (if needed):**
```bash
:# Re-add vault2 to target group
aws elbv2 register-targets \
  --target-group-arn arn:aws:elasticloadbalancing:us-west-2:822812818413:targetgroup/RentCoordinator/faeeb51824fa4106 \
  --targets Id=i-06a914c47bf8e08da
```

## Database Synchronization

### How it Works

**During Deployment:**
1. vault2 has the "source of truth" database
2. vault2 uploads to S3 via `/api/backup`
3. rent01 launches and restores from S3 automatically
4. Both instances now have the same data

**During Operation:**
1. Any instance can create a backup: `POST /api/backup`
2. Backup is saved locally AND uploaded to S3
3. New instances automatically get latest backup from S3
4. Manual restore available: `POST /api/backup/restore`

### S3 Backup Lifecycle

- **Versioning:** Enabled (can recover from accidental deletions)
- **Retention:** 30 days (older backups auto-deleted)
- **Bucket:** `rent-coordinator-backups-822812818413`
- **Prefix:** `database/`

### Testing Database Sync

```bash
:# On vault2: Create a backup
ssh vault2
curl -X POST http://localhost:3000/api/backup

:# On rent01: Restore from S3
ssh rent01  # (or use instance connect)
curl -X POST http://localhost:3000/api/backup/restore

:# Verify databases are in sync
:# (Check recent work logs, rent events, etc.)
```

## Operational Commands

### Scaling
```bash
:# Scale to 2 instances
cd infrastructure
./deploy.sh scale 2

:# Scale back to 1
./deploy.sh scale 1
```

### Updating Application
```bash
:# Method 1: Push to GitHub, then refresh instances
git push origin main
cd infrastructure
./deploy.sh refresh

:# Method 2: Terminate instances (ASG launches new ones with latest code)
INSTANCE_ID=$(./deploy.sh instances | grep i- | awk '{print $1}' | head -1)
aws autoscaling terminate-instance-in-auto-scaling-group \
  --instance-id $INSTANCE_ID \
  --no-should-decrement-desired-capacity
```

### Monitoring
```bash
:# Check status
cd infrastructure
./deploy.sh status

:# View logs
INSTANCE_ID=$(./deploy.sh instances | grep i- | awk '{print $1}' | head -1)
aws ssm start-session --target $INSTANCE_ID
sudo journalctl -u rent-coordinator -f
```

## Cleanup (If Needed)

```bash
:# Delete rent01 infrastructure (keeps vault2 intact)
cd infrastructure
./deploy.sh delete

:# This removes:
:# - EC2 instances (rent01)
:# - Launch Template
:# - Auto Scaling Group
:# - Security Groups
:# - IAM roles

:# This KEEPS:
:# - S3 backup bucket (delete manually if desired)
:# - Target Group and ALB (existed before)
:# - Secrets Manager (existed before)
:# - vault2 instance
```

## Cost Estimate

**With 1 instance (rent01):**
- t3.small instance: ~$15/month
- S3 storage: <$1/month (small database)
- **Total new cost:** ~$16/month

**With vault2 + rent01:**
- 2x t3.small: ~$30/month total
- ALB: ~$16/month (already paying)

## Troubleshooting

### Instance won't launch
```bash
:# Check CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name rent-coordinator-production \
  --region us-west-2 \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

### Instance not joining target group
```bash
:# Check bootstrap log
INSTANCE_ID=<from deploy.sh instances>
aws ssm start-session --target $INSTANCE_ID
sudo tail -f /var/log/user-data.log
```

### S3 restore fails
```bash
:# Check IAM permissions
:# Check if bucket exists
aws s3 ls s3://rent-coordinator-backups-822812818413/database/

:# Check application logs
sudo journalctl -u rent-coordinator -n 100
```

## Next Steps

1. **Test backup on vault2** - Verify S3 upload works
2. **Deploy infrastructure** - `./deploy.sh deploy`
3. **Verify rent01 health** - Check target group
4. **Test application** - Make sure everything works
5. **Remove vault2** - When confident (no rush!)

## Support

- **Infrastructure docs:** `infrastructure/README.md`
- **Migration guide:** `infrastructure/migration-guide.md`
- **Disaster recovery:** `docs/disaster-recovery.md`
- **Deployment tool:** `infrastructure/deploy.sh --help`
