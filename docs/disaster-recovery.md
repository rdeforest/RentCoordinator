# Disaster Recovery Guide

**Last Updated:** 2025-11-05

## Architecture Overview

RentCoordinator runs on AWS infrastructure managed by CloudFormation:

- **Application Load Balancer (ALB)** - Routes traffic to instances
- **Auto Scaling Group (ASG)** - Maintains 1-3 instances (currently min=1, max=1)
- **EC2 Instances** - Ubuntu instances with automated bootstrap
- **S3 Bucket** - Database backups with versioning enabled
- **AWS Secrets Manager** - Application secrets and credentials
- **Route53** - DNS (`rent.thatsnice.org`)

## Persistence Model

### What We Store and Where

**Primary Database:**
- **Location:** SQLite file on EC2 instance EBS volume
- **Path:** `/opt/rent-coordinator/tenant-coordinator.db`
- **Storage:** EBS volume (survives instance stop/start, NOT instance termination)
- **Backup Strategy:** Automatic S3 uploads during operations

**S3 Backups:**
- **Bucket:** `rent-coordinator-backups-822812818413`
- **Versioning:** Enabled (can recover from accidental deletion/corruption)
- **Lifecycle:** Backups older than 90 days are deleted
- **Frequency:** On-demand (manual) and during critical operations

**Application Secrets:**
- **Location:** AWS Secrets Manager
- **Secret Name:** `rent-coordinator/config`
- **Region:** `us-west-2`
- **Contains:** SESSION_SECRET, SMTP credentials, Stripe keys

### Guarantees and Limitations

**What's Guaranteed:**
- ✅ Database backed up to S3 with versioning
- ✅ Secrets stored durably in Secrets Manager
- ✅ ASG automatically replaces failed instances
- ✅ New instances automatically restore from S3 on boot
- ✅ Application code recoverable from GitHub

**What Can Still Fail:**
- ⚠️ **EBS volume corruption** - Data since last S3 backup is lost
- ⚠️ **EC2 instance termination** - Local database on EBS is destroyed
- ⚠️ **S3 region failure** - Extremely rare, backups unavailable until recovery
- ⚠️ **Data between backups** - If no S3 backup triggered, recent data may be lost
- ⚠️ **Simultaneous failures** - Multiple correlated failures could extend outage

**Why This Is Acceptable:**
- **2 users only** - Small user base, minimal impact
- **90% uptime target** - Not mission-critical, some downtime acceptable
- **Financial impact minimal** - Rent tracking data is reconstructable from other records
- **Manual backup possible** - Can trigger S3 backup before risky operations
- **Recovery time acceptable** - 10-30 minutes to rebuild is fine for this application

**Recovery Objectives:**
- **RTO (Recovery Time Objective):** 30 minutes for full rebuild
- **RPO (Recovery Point Objective):** Since last S3 backup (typically < 24 hours)

## Failure Scenarios and Recovery

### Scenario 1: Instance Failure (Automatic Recovery)

**What happens:**
- EC2 instance fails health checks
- ALB marks instance unhealthy
- ASG automatically terminates and replaces instance
- New instance bootstraps, pulls from GitHub, restores DB from S3

**Recovery time:** 5-10 minutes (fully automated)

**Manual intervention:** None required

**What you'll see:**
```bash
# New instance will appear in target group
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=RentCoordinator-production" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,LaunchTime]'
```

### Scenario 2: Database Corruption (Manual Recovery)

**What happens:**
- SQLite database becomes corrupted
- Application can't read/write data
- Health check may or may not fail

**Recovery procedure:**
```bash
# 1. Find current instance
INSTANCE_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=RentCoordinator-production" \
  "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

# 2. SSH to instance and restore from S3
ssh -i ~/.ssh/id_aws_rdeforest ubuntu@$INSTANCE_IP

# 3. Stop application
sudo systemctl stop rent-coordinator

# 4. Backup corrupted database (just in case)
sudo -u rent-coordinator cp /opt/rent-coordinator/tenant-coordinator.db \
  /opt/rent-coordinator/tenant-coordinator.db.corrupted

# 5. Restore from S3
sudo -u rent-coordinator bash -c '
  cd /opt/rent-coordinator
  source ~/.nvm/nvm.sh
  nvm use
  npx coffee -e "
    backup = require('\''./lib/services/backup.coffee'\'')
    result = await backup.restoreFromS3()
    console.log('\''Restored:'\'', result)
  "
'

# 6. Restart application
sudo systemctl start rent-coordinator

# 7. Verify
curl http://localhost:8080/health
```

**Recovery time:** 5-10 minutes

### Scenario 3: Complete Infrastructure Loss

**What happens:**
- CloudFormation stack deleted
- All infrastructure gone
- S3 bucket and Secrets Manager remain (separate lifecycle)

**Recovery procedure:**
```bash
# 1. Verify S3 backups still exist
aws s3 ls s3://rent-coordinator-backups-822812818413/database/

# 2. Verify secrets still exist
aws secretsmanager get-secret-value \
  --secret-id rent-coordinator/config \
  --region us-west-2 \
  --query 'SecretString' \
  --output text | jq .

# 3. Rebuild CloudFormation stack
cd infrastructure/cloudformation
./deploy.sh deploy

# 4. Wait for stack creation (15-20 minutes)
./deploy.sh status

# 5. New instance will auto-restore from S3
# 6. Verify application is healthy
curl https://rent.thatsnice.org/health
```

**Recovery time:** 20-30 minutes

### Scenario 4: S3 Backup Unavailable

**What happens:**
- S3 bucket deleted or corrupted
- No backup available for restore
- Must start with fresh database

**Recovery options:**

**Option A: Reconstruct from other sources**
```bash
# 1. Check if old vault2 server still has data
ssh vault2 "ls -lh ~/rent-coordinator/tenant-coordinator.db"

# 2. Copy database from old server if available
scp vault2:~/rent-coordinator/tenant-coordinator.db ./tenant-coordinator.db

# 3. Upload to S3
aws s3 cp tenant-coordinator.db \
  s3://rent-coordinator-backups-822812818413/database/manual-recovery-$(date +%Y%m%d).db
```

**Option B: Start fresh and manually recreate**
- Historical work logs from memory/email/calendar
- Historical rent payments from Venmo/bank records
- Lyndzie can re-enter her work hours

**Recovery time:** 2-4 hours manual data entry

## Manual Backup Procedures

### Create On-Demand S3 Backup

```bash
# From your local machine with AWS credentials
INSTANCE_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=RentCoordinator-production" \
  "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

ssh -i ~/.ssh/id_aws_rdeforest ubuntu@$INSTANCE_IP \
  "sudo -u rent-coordinator bash -c 'cd /opt/rent-coordinator && \
   source ~/.nvm/nvm.sh && nvm use && \
   npx coffee -e \"backup = require('\''./lib/services/backup.coffee'\''); \
   result = await backup.backupToS3(); console.log(result)\"'"
```

### Download Latest Backup Locally

```bash
# List available backups
aws s3 ls s3://rent-coordinator-backups-822812818413/database/ --recursive

# Download specific backup
aws s3 cp s3://rent-coordinator-backups-822812818413/database/backup-YYYY-MM-DD.db \
  ./local-backup.db

# Or download most recent
LATEST=$(aws s3 ls s3://rent-coordinator-backups-822812818413/database/ \
  --recursive | sort | tail -n 1 | awk '{print $4}')
aws s3 cp s3://rent-coordinator-backups-822812818413/$LATEST ./latest-backup.db
```

## DR Dry Run Procedure

**Goal:** Prove we can recover by standing up a parallel test stack

### Step 1: Create Test Stack

```bash
cd infrastructure/cloudformation

# Copy parameters and modify for test stack
cp parameters.json parameters-dr-test.json

# Edit parameters-dr-test.json:
# - Change StackName to "RentCoordinator-DR-Test"
# - Use separate target group or create new ALB
# - Can use same secrets (test only)

# Deploy test stack
aws cloudformation create-stack \
  --stack-name RentCoordinator-DR-Test \
  --template-body file://rent-coordinator-infrastructure.yaml \
  --parameters file://parameters-dr-test.json \
  --capabilities CAPABILITY_IAM

# Monitor creation
aws cloudformation wait stack-create-complete \
  --stack-name RentCoordinator-DR-Test
```

### Step 2: Verify Test Stack

```bash
# Get test instance IP
TEST_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=RentCoordinator-DR-Test" \
  "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

# Test health endpoint
curl http://$TEST_IP:8080/health

# Test login (should restore from S3 backup)
curl -I http://$TEST_IP:8080/login.html
```

### Step 3: Validate Data

```bash
# SSH to test instance
ssh -i ~/.ssh/id_aws_rdeforest ubuntu@$TEST_IP

# Check database was restored
sudo -u rent-coordinator bash -c '
  cd /opt/rent-coordinator
  source ~/.nvm/nvm.sh
  nvm use
  sqlite3 tenant-coordinator.db "SELECT COUNT(*) FROM rent_periods;"
'

# Should match production count
```

### Step 4: Tear Down Test Stack

```bash
# Delete test stack
aws cloudformation delete-stack --stack-name RentCoordinator-DR-Test

# Wait for deletion
aws cloudformation wait stack-delete-complete \
  --stack-name RentCoordinator-DR-Test

# Verify deletion
aws cloudformation describe-stacks --stack-name RentCoordinator-DR-Test
# Should return error: Stack does not exist
```

**Recommendation:** Run DR dry run every 6 months or after major changes

## Secrets Management

### Current Secrets

**AWS Secrets Manager:**
- **Secret Name:** `rent-coordinator/config`
- **Region:** `us-west-2`
- **ARN:** `arn:aws:secretsmanager:us-west-2:822812818413:secret:rent-coordinator/config-zlAnNB`

**Contains:**
```json
{
  "SESSION_SECRET": "...",
  "SMTP_HOST": "email-smtp.us-west-2.amazonaws.com",
  "SMTP_PORT": "587",
  "SMTP_USER": "...",
  "SMTP_PASS": "...",
  "EMAIL_FROM": "noreply@defore.st",
  "STRIPE_SECRET_KEY": "sk_live_...",
  "STRIPE_PUBLISHABLE_KEY": "pk_live_..."
}
```

### Updating Secrets

```bash
# Get current secrets
aws secretsmanager get-secret-value \
  --secret-id rent-coordinator/config \
  --region us-west-2 \
  --query 'SecretString' \
  --output text > /tmp/secrets.json

# Edit secrets
vim /tmp/secrets.json

# Update in Secrets Manager
aws secretsmanager update-secret \
  --secret-id rent-coordinator/config \
  --region us-west-2 \
  --secret-string file:///tmp/secrets.json

# Restart application to pick up new secrets
INSTANCE_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=RentCoordinator-production" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

ssh -i ~/.ssh/id_aws_rdeforest ubuntu@$INSTANCE_IP \
  "sudo systemctl restart rent-coordinator"

# Clean up
rm /tmp/secrets.json
```

### Rotating Secrets

**After rotating Stripe keys or SMTP credentials:**

1. Update AWS Secrets Manager (see above)
2. Update instance .env file:
```bash
ssh -i ~/.ssh/id_aws_rdeforest ubuntu@$INSTANCE_IP
sudo vim /opt/rent-coordinator/.env
# Update relevant secrets
sudo systemctl restart rent-coordinator
```

## AWS Resources Reference

Store these for disaster recovery:

**CloudFormation:**
- Stack Name: `RentCoordinator` (or check: `aws cloudformation list-stacks`)

**Networking:**
- ALB: `rent-coordinator` (check: `aws elbv2 describe-load-balancers`)
- Target Group: `RentCoordinator` (check: `aws elbv2 describe-target-groups`)
- Security Groups: Created by CloudFormation, tagged with stack name

**Storage:**
- S3 Bucket: `rent-coordinator-backups-822812818413`
- Secrets: `rent-coordinator/config` (us-west-2)

**DNS:**
- Route53 Hosted Zone: `defore.st` (ID: `ZUK6DSCVHUE2Q`)
- DNS Record: `rent.thatsnice.org` → ALB

**IAM:**
- Instance Profile: Created by CloudFormation
- Policies: S3 backup access, Secrets Manager read

## Testing Checklist

**Before Major Changes:**
- [ ] Create manual S3 backup
- [ ] Verify secrets in AWS Secrets Manager
- [ ] Document current instance ID and IP
- [ ] Note current CloudFormation stack status

**Quarterly DR Test:**
- [ ] Create test stack (DR dry run procedure above)
- [ ] Verify database restore from S3
- [ ] Test application functionality
- [ ] Test login flow
- [ ] Verify rent calculations
- [ ] Verify Stripe integration (test mode)
- [ ] Clean up test stack
- [ ] Document any issues found

**Annual Full Test:**
- [ ] Complete infrastructure rebuild from scratch
- [ ] Time the recovery process (should be < 30 min)
- [ ] Update RTO/RPO estimates based on test
- [ ] Review and update this documentation

## Emergency Contacts

- **AWS Support:** Console → Support → Create Case
- **Stripe Support:** https://support.stripe.com
- **Domain Registrar:** (Wherever defore.st is registered)
- **Key Personnel:** Robert (robert@defore.st)

## Acceptable Risk Statement

**We accept the following risks for RentCoordinator:**

1. **Data loss between backups** - Manual S3 backup before critical operations
2. **Up to 30-minute outage** - Small user base can tolerate brief downtime
3. **Single region dependency** - Cost of multi-region not justified for 2 users
4. **No real-time replication** - Batch backups sufficient for use case
5. **Manual intervention may be needed** - Not fully automated recovery for all scenarios

These trade-offs are consciously made because:
- 2-user application (Robert and Lyndzie)
- 90% uptime acceptable
- Financial impact minimal (rent data reconstructable)
- Educational/learning value prioritized over operational perfection

---

**Recovery Confidence:** ✅ High

We can recover from all common failure scenarios with acceptable RTO/RPO.
