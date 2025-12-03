#!/bin/bash
# Create backup on remote production instance
# Usage: ./scripts/remote/backup-now-remote.sh

set -e

echo "Finding production instance..."
PROD_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=RentCoordinator-production" \
  "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

if [ -z "$PROD_IP" ] || [ "$PROD_IP" = "None" ]; then
  echo "Error: Production instance not found"
  exit 1
fi

echo "Connecting to production instance at $PROD_IP..."
ssh ubuntu@$PROD_IP "sudo -u rent-coordinator /opt/rent-coordinator/scripts/backup-now.sh"
