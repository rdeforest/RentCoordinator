# Migration Guide: vault2 → AWS Auto Scaling

This guide walks you through migrating from the manual vault2 deployment to automated AWS infrastructure.

## Overview

**Current State:** Single server (vault2) manually deployed
**Target State:** Auto Scaling Group with 1-3 instances, automatically deployed from GitHub

**Benefits of Migration:**
- ✅ Automatic instance replacement on failure
- ✅ Zero-touch deployment from GitHub
- ✅ Easy scaling up/down
- ✅ Infrastructure as Code (versioned, repeatable)
- ✅ Secrets securely managed in AWS Secrets Manager
- ✅ No more manual SSH deployments

## Prerequisites

### AWS Resources Already Exist
- ✅ Application Load Balancer (rent-coordinator)
- ✅ Target Group (RentCoordinator)
- ✅ Secrets Manager secret (rent-coordinator/config)
- ✅ Route53 hosted zone (defore.st)

### What You Need
- AWS CLI installed and configured
- VPC ID where vault2 currently runs
- Subnet IDs (2+ in different AZs for high availability)
- EC2 Key Pair name for SSH access
- Current database backup from vault2

## Migration Steps

### Phase 1: Preparation (No Downtime)

#### 1. Backup vault2 Database
```bash
# SSH to vault2 and create backup
ssh vault2 'cd ~/rent-coordinator && npm run backup'

# Download backup to local machine
scp vault2:~/rent-coordinator/backups/*.json ./backups/

# Keep this backup safe!
```

#### 2. Get AWS Resource IDs
```bash
# Get VPC ID where vault2 runs
aws ec2 describe-instances \
  --instance-ids i-06a914c47bf8e08da \
  --query 'Reservations[0].Instances[0].VpcId' \
  --output text

# Get Subnet IDs (need at least 2 in different AZs)
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=<vpc-id>" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone]' \
  --output table

# Verify Target Group ARN
aws elbv2 describe-target-groups \
  --names RentCoordinator \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text
```

#### 3. Configure Infrastructure Parameters
```bash
cd infrastructure/cloudformation

# Copy example parameters
cp parameters-example.json parameters.json

# Edit with your values
nano parameters.json
```

**Update these fields:**
```json
{
  "KeyName": "your-ec2-keypair",
  "VpcId": "vpc-xxxxxxxxx",
  "SubnetIds": "subnet-xxxxxxxx,subnet-yyyyyyyy",
  "TargetGroupArn": "arn:aws:elasticloadbalancing:...",
  "SecretsManagerSecretArn": "arn:aws:secretsmanager:...",
  "DesiredCapacity": "1"  // Start with 1 instance
}
```

#### 4. Validate Template
```bash
cd infrastructure
./deploy.sh validate
```

### Phase 2: Deploy New Infrastructure (Parallel to vault2)

#### 5. Deploy CloudFormation Stack
```bash
# This creates rent01 automatically and adds it to the target group
./deploy.sh deploy

# Monitor deployment (takes ~5-10 minutes)
watch -n 10 './deploy.sh status'
```

**What happens:**
1. Creates Launch Template with user-data bootstrap
2. Creates Auto Scaling Group
3. Launches first instance (rent01)
4. Instance clones GitHub repo, installs dependencies
5. Instance retrieves secrets from Secrets Manager
6. Instance starts application
7. Instance registers with Target Group automatically
8. Health checks verify instance is healthy

#### 6. Verify rent01 is Healthy
```bash
# Check instance status
./deploy.sh instances

# Get Target Group health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:us-west-2:822812818413:targetgroup/RentCoordinator/faeeb51824fa4106

# Expected output: Both vault2 and rent01 should show "healthy"
```

#### 7. Test rent01 Directly
```bash
# Get rent01 IP address
RENT01_IP=$(./deploy.sh instances | grep i- | awk '{print $1}' | head -1)
RENT01_IP=$(aws ec2 describe-instances --instance-ids $RENT01_IP --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

# Test health endpoint
curl http://$RENT01_IP:3000/health

# Test login page
curl -I http://$RENT01_IP:3000/login.html
```

### Phase 3: Traffic Migration (Brief Downtime)

#### 8. Monitor ALB Traffic Distribution
```bash
# Both vault2 and rent01 are now serving traffic
# ALB distributes evenly between them

# Watch target connections
watch -n 5 'aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:us-west-2:822812818413:targetgroup/RentCoordinator/faeeb51824fa4106'
```

#### 9. Remove vault2 from Target Group
```bash
# This starts directing all traffic to rent01
aws elbv2 deregister-targets \
  --target-group-arn arn:aws:elasticloadbalancing:us-west-2:822812818413:targetgroup/RentCoordinator/faeeb51824fa4106 \
  --targets Id=i-06a914c47bf8e08da

# Traffic now goes 100% to rent01
```

#### 10. Verify Traffic to rent01
```bash
# Test application is accessible
curl -I https://rentcoordinator.defore.st/health

# Check application logs
RENT01_ID=$(./deploy.sh instances | grep i- | awk '{print $1}' | head -1)
ssh -i ~/.ssh/your-key.pem admin@$(aws ec2 describe-instances --instance-ids $RENT01_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
sudo journalctl -u rent-coordinator -f
```

### Phase 4: Decommission vault2 (Gradual)

#### 11. Stop vault2 Service
```bash
# Stop the application on vault2 (keep instance running for safety)
ssh vault2 'sudo systemctl stop rent-coordinator'

# Monitor for any issues over the next few hours
# If problems arise, you can quickly re-add vault2 to target group
```

#### 12. Keep vault2 Running for 24-48 Hours
```bash
# Leave vault2 instance running but stopped
# This gives you quick rollback capability if needed

# To rollback if issues arise:
# 1. ssh vault2 'sudo systemctl start rent-coordinator'
# 2. aws elbv2 register-targets --target-group-arn ... --targets Id=i-06a914c47bf8e08da
```

#### 13. Stop vault2 Instance
```bash
# After 24-48 hours with no issues
aws ec2 stop-instances --instance-ids i-06a914c47bf8e08da

# This stops the instance but keeps the EBS volume
# You can still start it again if needed
```

#### 14. Terminate vault2 (After 1 Week)
```bash
# After 1 week of successful operation
# Take final backup first
ssh vault2 'cd ~/rent-coordinator && npm run backup'
scp vault2:~/rent-coordinator/backups/*.json ./backups/

# Terminate instance
aws ec2 terminate-instances --instance-ids i-06a914c47bf8e08da
```

## Post-Migration Operations

### Adding More Instances
```bash
# Scale to 2 instances
cd infrastructure
./deploy.sh scale 2

# New instance launches automatically, bootstraps from GitHub, and joins target group
```

### Deploying Application Updates
```bash
# Method 1: Just push to GitHub
git push origin main

# Then force instance refresh (rolling update)
cd infrastructure
./deploy.sh refresh

# Method 2: Terminate instances one by one
# Auto Scaling Group launches new ones with latest code
ASG_NAME=$(./deploy.sh status | grep "Auto Scaling Group:" | awk '{print $5}')
INSTANCE_ID=$(./deploy.sh instances | grep i- | awk '{print $1}' | head -1)
aws autoscaling terminate-instance-in-auto-scaling-group \
  --instance-id $INSTANCE_ID \
  --no-should-decrement-desired-capacity
```

### Monitoring
```bash
# Check status
cd infrastructure
./deploy.sh status

# List instances
./deploy.sh instances

# Check target health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:us-west-2:822812818413:targetgroup/RentCoordinator/faeeb51824fa4106

# View logs on an instance
INSTANCE_ID=$(./deploy.sh instances | grep i- | awk '{print $1}' | head -1)
ssh -i ~/.ssh/your-key.pem admin@$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
sudo journalctl -u rent-coordinator -f
```

## Rollback Procedures

### Rollback to vault2 (Emergency)
```bash
# 1. Start vault2 if stopped
aws ec2 start-instances --instance-ids i-06a914c47bf8e08da

# 2. Wait for instance to be running
aws ec2 wait instance-running --instance-ids i-06a914c47bf8e08da

# 3. Start rent-coordinator service
ssh vault2 'sudo systemctl start rent-coordinator'

# 4. Re-register with target group
aws elbv2 register-targets \
  --target-group-arn arn:aws:elasticloadbalancing:us-west-2:822812818413:targetgroup/RentCoordinator/faeeb51824fa4106 \
  --targets Id=i-06a914c47bf8e08da

# 5. Remove rent01 from target group
./deploy.sh instances  # Get instance IDs
aws elbv2 deregister-targets \
  --target-group-arn arn:aws:elasticloadbalancing:us-west-2:822812818413:targetgroup/RentCoordinator/faeeb51824fa4106 \
  --targets Id=<rent01-instance-id>
```

### Complete Rollback (Remove Infrastructure)
```bash
# Delete CloudFormation stack
cd infrastructure
./deploy.sh delete

# This terminates all rent01 instances and removes infrastructure
# Does NOT affect vault2 or the ALB/Target Group
```

## Troubleshooting

### Instance Won't Launch
```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name rent-coordinator-production \
  --region us-west-2 \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'

# Common issues:
# - Wrong subnet IDs
# - Missing EC2 key pair
# - IAM permissions for CloudFormation
```

### Instance Not Joining Target Group
```bash
# SSH to instance
INSTANCE_ID=$(./deploy.sh instances | grep i- | awk '{print $1}' | head -1)
INSTANCE_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
ssh -i ~/.ssh/your-key.pem admin@$INSTANCE_IP

# Check bootstrap log
sudo tail -f /var/log/user-data.log

# Check application
sudo systemctl status rent-coordinator
sudo journalctl -u rent-coordinator -n 100

# Check health endpoint
curl http://localhost:3000/health
```

### Application Won't Start
```bash
# Check if secrets were retrieved
ssh to instance
sudo cat /opt/rent-coordinator/.env  # Should contain secrets

# Check database
ls -la /var/lib/rent-coordinator/

# Check application logs
sudo journalctl -u rent-coordinator -f
```

## Cost Comparison

### Current (vault2)
- t3.small instance: ~$15/month
- No Auto Scaling, manual deployment

### New (Auto Scaling)
- 1 t3.small instance: ~$15/month
- 2 t3.small instances: ~$30/month
- 3 t3.small instances: ~$45/month
- ALB: ~$16/month (already paying this)

**Net difference:** $0 for same capacity, more for HA

## Timeline

**Recommended Timeline:**
- **Day 0:** Deploy infrastructure, verify rent01 healthy (2 hours)
- **Day 1:** Monitor both vault2 and rent01 in parallel (24 hours)
- **Day 2:** Remove vault2 from target group, stop service (5 minutes)
- **Day 3-7:** Monitor rent01 alone, keep vault2 stopped (1 week)
- **Day 8+:** Terminate vault2, fully migrated

## Questions?

See:
- `infrastructure/README.md` - Complete AWS deployment documentation
- `docs/DISASTER-RECOVERY.md` - Recovery procedures
- `docs/TROUBLESHOOTING.md` - Common issues and solutions

**Support:**
- Check application logs: `sudo journalctl -u rent-coordinator -f`
- Check CloudFormation events: `aws cloudformation describe-stack-events --stack-name rent-coordinator-production`
- Test instance health: `curl http://localhost:3000/health`
