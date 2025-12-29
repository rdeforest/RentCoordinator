# CloudWatch Logs Setup Guide

**Last Updated:** 2025-12-29

## Overview

CloudWatch Logs provides centralized logging for the RentCoordinator application, allowing you to view and search logs without SSH access to EC2 instances.

## Architecture

- **Source:** systemd journald (rent-coordinator.service)
- **Agent:** Amazon CloudWatch Agent
- **Destination:** CloudWatch Logs
- **Log Group:** `/rent-coordinator/application`
- **Log Stream:** Per-instance (instance ID)

## Prerequisites

- EC2 instance running RentCoordinator
- IAM role with `CloudWatchAgentServerPolicy` (already configured)
- AWS CLI configured for CloudWatch Logs access

## Installation

### 1. Deploy Configuration Files

```bash
# From your local machine
scp infrastructure/cloudwatch-agent-config.json ubuntu@<instance-ip>:/tmp/
scp infrastructure/setup-cloudwatch-logs.sh ubuntu@<instance-ip>:/tmp/
```

### 2. Run Setup Script

```bash
ssh ubuntu@<instance-ip>

# Move files to application directory
sudo cp /tmp/cloudwatch-agent-config.json /opt/rent-coordinator/infrastructure/
sudo cp /tmp/setup-cloudwatch-logs.sh /opt/rent-coordinator/infrastructure/
sudo chown -R rent-coordinator:rent-coordinator /opt/rent-coordinator/infrastructure/

# Run setup
sudo bash /opt/rent-coordinator/infrastructure/setup-cloudwatch-logs.sh
```

### 3. Verify Installation

```bash
# Check agent status
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a query -m ec2 -c default -s

# View local test
sudo journalctl -u rent-coordinator -n 50
```

## Viewing Logs

### AWS Console

1. Open [CloudWatch Console](https://console.aws.amazon.com/cloudwatch/)
2. Navigate to **Logs** → **Log groups**
3. Select `/rent-coordinator/application`
4. Choose the instance stream

### AWS CLI

```bash
# Tail logs in real-time
aws logs tail /rent-coordinator/application --follow

# Tail logs for specific instance
aws logs tail /rent-coordinator/application --follow \
  --log-stream-names i-1234567890abcdef0

# Search logs
aws logs filter-log-events \
  --log-group-name /rent-coordinator/application \
  --filter-pattern "ERROR"

# Get recent payment logs
aws logs filter-log-events \
  --log-group-name /rent-coordinator/application \
  --filter-pattern "payment" \
  --start-time $(date -d '1 hour ago' +%s)000
```

### CloudWatch Insights Queries

```sql
-- Find all errors in last hour
fields @timestamp, @message
| filter @message like /ERROR|error/
| sort @timestamp desc
| limit 100

-- Payment intent activity
fields @timestamp, @message
| filter @message like /payment intent|Payment intent/
| sort @timestamp desc

-- Slow queries or performance issues
fields @timestamp, @message
| filter @message like /slow|timeout|performance/
| sort @timestamp desc
```

## Cost Estimation

- **Ingestion:** $0.50 per GB
- **Storage:** $0.03 per GB/month (after free tier)
- **Typical usage:** ~100-500 MB/month = **~$0.50-2.50/month**

First 5 GB/month ingestion and storage are free tier eligible.

## Retention Policy

Default: **Never expire**

To set retention:
```bash
aws logs put-retention-policy \
  --log-group-name /rent-coordinator/application \
  --retention-in-days 30
```

Recommended retention: **30 days** (balances cost vs. debugging needs)

## Troubleshooting

### Agent not running

```bash
sudo systemctl status amazon-cloudwatch-agent
sudo systemctl restart amazon-cloudwatch-agent
```

### Logs not appearing in CloudWatch

```bash
# Check agent logs
sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log

# Verify IAM permissions
aws sts get-caller-identity

# Check journald has logs
sudo journalctl -u rent-coordinator -n 20
```

### Permission denied errors

Ensure the EC2 instance has the `CloudWatchAgentServerPolicy` attached via its IAM role (already configured in CloudFormation).

## Metric Filters (Optional)

Create metric filters to track specific events:

```bash
# Track payment errors
aws logs put-metric-filter \
  --log-group-name /rent-coordinator/application \
  --filter-name PaymentErrors \
  --filter-pattern "[...] payment*error" \
  --metric-transformations \
    metricName=PaymentErrors,metricNamespace=RentCoordinator,metricValue=1

# Track server errors
aws logs put-metric-filter \
  --log-group-name /rent-coordinator/application \
  --filter-name ServerErrors \
  --filter-pattern "ERROR" \
  --metric-transformations \
    metricName=ServerErrors,metricNamespace=RentCoordinator,metricValue=1
```

## Automated Deployment

For future instance launches, add to user-data script:

```bash
# In CloudFormation LaunchTemplate UserData
cd /opt/rent-coordinator
sudo bash infrastructure/setup-cloudwatch-logs.sh
```

## Next Steps

1. Set up CloudWatch Alarms for critical errors
2. Create CloudWatch Dashboard for application health
3. Configure SNS notifications for important events
