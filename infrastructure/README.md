# RentCoordinator AWS Infrastructure Automation

This directory contains AWS CloudFormation templates for automated infrastructure provisioning and deployment of RentCoordinator.

## Overview

The infrastructure automation provides:
- **Automated EC2 provisioning** from GitHub repository
- **Auto Scaling Group** with health checks and automatic replacement
- **IAM roles** for Secrets Manager access
- **Security Groups** for application and ALB
- **Target Group integration** with existing ALB
- **Zero-touch deployment** - instances bootstrap automatically on launch

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Internet                         │
└─────────────────┬───────────────────────────────────┘
                  │
         ┌────────▼────────┐
         │   Route 53      │
         │ (defore.st)     │
         └────────┬────────┘
                  │
         ┌────────▼────────┐
         │  ALB (existing) │
         │  Port 80/443    │
         └────────┬────────┘
                  │
         ┌────────▼─────────────────────┐
         │   Target Group (existing)    │
         │   Port 3000                  │
         └────────┬─────────────────────┘
                  │
    ┌─────────────┴─────────────┐
    │                           │
┌───▼────┐                  ┌───▼────┐
│  EC2   │                  │  EC2   │
│ rent01 │  Auto Scaling    │ rent02 │
│        │  ◄─────────────► │        │
└────────┘     Group        └────────┘
    │                           │
    └──────────┬────────────────┘
               │
    ┌──────────▼──────────┐
    │  Secrets Manager    │
    │ (configuration)     │
    └─────────────────────┘
```

## Prerequisites

### AWS Resources (must exist)
- **VPC** with at least 2 subnets in different Availability Zones
- **Application Load Balancer** with Target Group
- **EC2 Key Pair** for SSH access
- **Secrets Manager Secret** containing application configuration
- **AWS CLI** configured with appropriate credentials

### Secrets Manager Configuration

Your secret should contain the following keys:
```json
{
  "SESSION_SECRET": "your-session-secret",
  "SMTP_HOST": "email-smtp.us-west-2.amazonaws.com",
  "SMTP_PORT": "587",
  "SMTP_USER": "your-smtp-user",
  "SMTP_PASS": "your-smtp-password",
  "EMAIL_FROM": "noreply@defore.st",
  "STRIPE_SECRET_KEY": "sk_test_...",
  "STRIPE_PUBLISHABLE_KEY": "pk_test_..."
}
```

## Quick Start

### 1. Prepare Parameters

Copy and edit the parameters file:
```bash
cd infrastructure/cloudformation
cp parameters-example.json parameters.json

# Edit parameters.json with your values
nano parameters.json
```

**Required parameters to update:**
- `KeyName` - Your EC2 key pair name
- `VpcId` - Your VPC ID
- `SubnetIds` - Comma-separated list of subnet IDs (2+ subnets in different AZs)

### 2. Deploy Infrastructure

```bash
# Deploy the stack
aws cloudformation create-stack \
  --stack-name rent-coordinator-production \
  --template-body file://rent-coordinator-infrastructure.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-west-2

# Watch the deployment
aws cloudformation wait stack-create-complete \
  --stack-name rent-coordinator-production \
  --region us-west-2

# Check status
aws cloudformation describe-stacks \
  --stack-name rent-coordinator-production \
  --region us-west-2 \
  --query 'Stacks[0].StackStatus'
```

### 3. Verify Deployment

```bash
# Get Auto Scaling Group name
ASG_NAME=$(aws cloudformation describe-stacks \
  --stack-name rent-coordinator-production \
  --region us-west-2 \
  --query 'Stacks[0].Outputs[?OutputKey==`AutoScalingGroupName`].OutputValue' \
  --output text)

# List instances in Auto Scaling Group
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --region us-west-2 \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]' \
  --output table

# Check instance logs (replace INSTANCE_ID)
aws ssm start-session --target INSTANCE_ID
sudo journalctl -u rent-coordinator -f
```

## Operations

### Adding a New Instance

The Auto Scaling Group handles this automatically, but you can manually trigger:

```bash
# Increase desired capacity
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name $ASG_NAME \
  --desired-capacity 2 \
  --region us-west-2
```

New instances will:
1. Launch with the latest code from GitHub
2. Install dependencies and build automatically
3. Retrieve secrets from AWS Secrets Manager
4. Start the application
5. Register with the Target Group automatically
6. Receive traffic once healthy

### Removing an Instance (e.g., vault2)

```bash
# Decrease desired capacity
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name $ASG_NAME \
  --desired-capacity 1 \
  --region us-west-2

# Or manually deregister and terminate specific instance
aws elbv2 deregister-targets \
  --target-group-arn $TARGET_GROUP_ARN \
  --targets Id=i-xxxxxxxxx

aws ec2 terminate-instances --instance-ids i-xxxxxxxxx
```

### Updating the Application

There are two approaches:

#### Option 1: Rolling Update (Zero Downtime)
```bash
# Update Launch Template (if needed)
aws cloudformation update-stack \
  --stack-name rent-coordinator-production \
  --template-body file://rent-coordinator-infrastructure.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-west-2

# Perform instance refresh (rolling update)
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name $ASG_NAME \
  --preferences MinHealthyPercentage=50 \
  --region us-west-2
```

#### Option 2: Just Push to GitHub
Instances automatically pull latest code on boot. To deploy:
1. Push changes to GitHub
2. Terminate old instances one by one
3. Auto Scaling Group launches new instances with latest code

### Monitoring

```bash
# Check Auto Scaling Group status
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --region us-west-2

# Check target health
aws elbv2 describe-target-health \
  --target-group-arn $TARGET_GROUP_ARN \
  --region us-west-2

# View CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --dimensions Name=TargetGroup,Value=targetgroup/RentCoordinator/faeeb51824fa4106 \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region us-west-2
```

## Updating the Stack

```bash
# Update stack with changes to template or parameters
aws cloudformation update-stack \
  --stack-name rent-coordinator-production \
  --template-body file://rent-coordinator-infrastructure.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-west-2

# Wait for update to complete
aws cloudformation wait stack-update-complete \
  --stack-name rent-coordinator-production \
  --region us-west-2
```

## Deleting the Infrastructure

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
  --stack-name rent-coordinator-production \
  --region us-west-2

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
  --stack-name rent-coordinator-production \
  --region us-west-2
```

**Note:** This will terminate all instances but will NOT delete:
- The ALB and Target Group (existed before)
- The Secrets Manager secret
- Any data volumes or databases on instances

## Troubleshooting

### Stack Creation Fails

```bash
# Check stack events
aws cloudformation describe-stack-events \
  --stack-name rent-coordinator-production \
  --region us-west-2 \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

### Instance Bootstrap Fails

```bash
# SSH to instance
ssh -i ~/.ssh/your-key.pem admin@<instance-ip>

# Check user-data log
sudo tail -f /var/log/user-data.log

# Check application logs
sudo journalctl -u rent-coordinator -f
```

### Instances Not Joining Target Group

```bash
# Check instance health
aws elbv2 describe-target-health \
  --target-group-arn $TARGET_GROUP_ARN \
  --region us-west-2

# Verify security groups allow traffic
# Check health check endpoint
curl http://<instance-ip>:3000/health
```

## Cost Optimization

### Current Configuration
- **t3.small instances** (~$15/month each)
- **Auto Scaling**: 1-3 instances
- **Estimated monthly cost**: $15-45 (compute) + ALB ($16/month)

### Reducing Costs
```bash
# Use t3.micro for lighter workloads
# Edit parameters.json: "InstanceType": "t3.micro"

# Run single instance
# Edit parameters.json:
#   "MinSize": "1"
#   "MaxSize": "1"
#   "DesiredCapacity": "1"
```

## Security Best Practices

1. **Secrets Management**: All sensitive data in AWS Secrets Manager
2. **IAM Roles**: Least-privilege access for EC2 instances
3. **Security Groups**: Restricted to necessary ports only
4. **SSH Keys**: Use EC2 key pairs, rotate regularly
5. **Updates**: Instances automatically get latest code from GitHub
6. **HTTPS**: Terminate SSL at ALB level

## Migration from Manual Deployment (vault2 → rent01)

### Step 1: Prepare
```bash
# Backup database from vault2
ssh vault2 'cd ~/rent-coordinator && npm run backup'
scp vault2:~/rent-coordinator/backups/*.json ./backups/
```

### Step 2: Deploy Infrastructure
```bash
# Deploy CloudFormation stack (creates rent01 automatically)
aws cloudformation create-stack \
  --stack-name rent-coordinator-production \
  --template-body file://rent-coordinator-infrastructure.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM
```

### Step 3: Verify rent01
```bash
# Wait for instance to be healthy in target group
watch -n 5 aws elbv2 describe-target-health \
  --target-group-arn $TARGET_GROUP_ARN
```

### Step 4: Migrate Traffic
```bash
# Deregister vault2 from target group
aws elbv2 deregister-targets \
  --target-group-arn $TARGET_GROUP_ARN \
  --targets Id=i-06a914c47bf8e08da  # vault2 instance ID
```

### Step 5: Shutdown vault2
```bash
# Stop vault2 instance (keep it around for a few days in case of issues)
aws ec2 stop-instances --instance-ids i-06a914c47bf8e08da

# Later, terminate vault2
aws ec2 terminate-instances --instance-ids i-06a914c47bf8e08da
```

## Future Enhancements

- **Database backups**: Automated S3 backup of SQLite database
- **CloudWatch dashboards**: Application metrics and monitoring
- **Auto-scaling policies**: Scale based on request count or latency
- **Multi-region**: Deploy to multiple regions for disaster recovery
- **Blue/Green deployments**: Zero-downtime deployments with two ASGs
