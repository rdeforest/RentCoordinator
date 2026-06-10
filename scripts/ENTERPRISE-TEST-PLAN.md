# Enterprise-Style Instance Persistence Test

## Overview

This test validates that data persists across instance replacements in the AWS Auto Scaling Group. It simulates real-world scenarios where instances are terminated and replaced.

## Test Scenario

1. **Terminate** current production instance
2. **Wait** for Auto Scaling Group to create replacement
3. **Add** test data via API
4. **Trigger** backup via API (POST /api/backup)
5. **Terminate** that instance
6. **Wait** for next replacement
7. **Verify** data persisted

## Prerequisites

### 1. Deploy Latest Code

```bash
# Push commits to GitHub
git push origin main

# Deploy to AWS (triggers new instance creation)
cd infrastructure
./deploy.sh deploy
```

**New commits to deploy:**
- `457a622` - Fix backup service and tests for dynamic config
- `2f3f5ba` - Rename rent override fields for clarity

### 2. Verify AWS Infrastructure

```bash
# Check Auto Scaling Group
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names RentCoordinator-production-asg \
  --region us-west-2

# Check S3 bucket exists
aws s3 ls s3://rent-coordinator-backups-822812818413/database/
```

### 3. Ensure IAM Permissions

The EC2 instance role needs:
- `s3:PutObject` on `rent-coordinator-backups-822812818413/*`
- `s3:GetObject` on `rent-coordinator-backups-822812818413/*`
- `s3:ListBucket` on `rent-coordinator-backups-822812818413`

## Running the Test

### Automated Test Script

```bash
cd scripts
./test-instance-persistence.sh
```

The script will:
- Automatically terminate instances
- Wait for replacements to be healthy
- Prompt for authentication code (check email)
- Add test data
- Trigger backup
- Verify persistence

### Manual Test Steps

If you prefer to run manually:

#### Step 1: Terminate Current Instance

```bash
# Get current instance
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names RentCoordinator-production-asg \
  --region us-west-2 \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)

echo "Terminating instance: $INSTANCE_ID"

# Terminate it
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region us-west-2
```

#### Step 2: Wait for Replacement (5-10 minutes)

```bash
# Monitor ASG
watch -n 5 'aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names RentCoordinator-production-asg \
  --region us-west-2 \
  --query "AutoScalingGroups[0].Instances[].[InstanceId,HealthStatus,LifecycleState]" \
  --output table'

# Check app health
curl https://rent.defore.st/health
```

#### Step 3: Authenticate

```bash
# Request verification code
curl -X POST https://rent.defore.st/auth/request-code \
  -H "Content-Type: application/json" \
  -d '{"email":"robert@defore.st"}'

# Check email, then verify (replace CODE)
curl -X POST https://rent.defore.st/auth/verify \
  -H "Content-Type: application/json" \
  -d '{"email":"robert@defore.st","code":"CODE"}' \
  -c /tmp/cookies.txt
```

#### Step 4: Add Test Data

```bash
curl -X POST https://rent.defore.st/work-logs \
  -H "Content-Type: application/json" \
  -b /tmp/cookies.txt \
  -d '{
    "worker": "robert",
    "start_time": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "end_time": "'$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%SZ)'",
    "duration": 120,
    "description": "Enterprise test - instance persistence",
    "billable": true
  }'
```

Save the work log ID from the response!

#### Step 5: Trigger Backup

```bash
curl -X POST https://rent.defore.st/api/backup \
  -H "Content-Type: application/json" \
  -b /tmp/cookies.txt
```

Wait ~10 seconds for S3 upload to complete.

#### Step 6: Verify Backup in S3

```bash
aws s3 ls s3://rent-coordinator-backups-822812818413/database/ --region us-west-2
```

You should see a new `.db` file with recent timestamp.

#### Step 7: Terminate Instance Again

```bash
# Get new instance ID
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names RentCoordinator-production-asg \
  --region us-west-2 \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)

echo "Terminating instance: $INSTANCE_ID"
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region us-west-2
```

#### Step 8: Wait for Next Replacement

Same as Step 2 - wait for healthy instance.

#### Step 9: Verify Data Persisted

```bash
# List work logs
curl https://rent.defore.st/work-logs \
  -H "Content-Type: application/json" \
  -b /tmp/cookies.txt
```

Check if your test work log ID is in the response!

## Expected Results

### ✅ Success Criteria

- New instance starts within 5-10 minutes
- App responds to /health endpoint
- Work log created in Step 4 exists in Step 9
- Data survived TWO instance terminations

### ❌ Failure Scenarios

**Data not found after replacement:**
- Check CloudWatch logs: `/rent-coordinator/application`
- Check if S3 restore was attempted
- Verify S3 bucket permissions
- Check if backup was created in Step 5

**Instance won't start:**
- Check CloudFormation events
- Check EC2 instance logs via AWS Console
- Verify GitHub repository is accessible
- Check IAM role permissions

## Debugging

### View Application Logs

```bash
# Real-time logs
aws logs tail /rent-coordinator/application --follow --region us-west-2

# Filter for backup events
aws logs tail /rent-coordinator/application \
  --follow \
  --filter-pattern "backup" \
  --region us-west-2
```

### SSH to Instance (if needed)

```bash
# Get instance IP
INSTANCE_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=RentCoordinator-production" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text \
  --region us-west-2)

# SSH in
ssh -i ~/.ssh/id_aws_rdeforest ubuntu@$INSTANCE_IP

# Check service status
sudo systemctl status rent-coordinator

# View local logs
sudo journalctl -u rent-coordinator -n 100 -f
```

## Rollback Plan

If the test fails and you need to recover:

1. **Restore from S3 manually:**
   ```bash
   ssh ubuntu@INSTANCE_IP
   sudo systemctl stop rent-coordinator

   # Restore from S3 via API (or manual)
   curl -X POST https://rent.defore.st/api/backup/restore -b /tmp/cookies.txt

   sudo systemctl start rent-coordinator
   ```

2. **Roll back code deployment:**
   ```bash
   cd infrastructure
   # Edit cloudformation/parameters.json to use previous commit
   ./deploy.sh deploy
   ```

## Post-Test

After successful test:

- [ ] Document results
- [ ] Review CloudWatch logs for any errors
- [ ] Verify backup count in S3 (should increase by 1-2)
- [ ] Clean up test work logs if desired
- [ ] Consider setting up scheduled backups (cron job or Lambda)

## Notes

- Terminating instances is safe with Auto Scaling Group - new ones are created automatically
- Current production has no data (per user), so safe to test
- S3 backup system is the critical component for data persistence
- Instance replacement typically takes 5-10 minutes total
