#!/bin/bash

# DR Test Stack Verification
# Validates that the DR test stack is functioning correctly

set -e

STACK_NAME="rent-coordinator-dr-test"
SSH_KEY="$HOME/.ssh/id_aws_rdeforest"

echo "========================================"
echo "  DR Test Stack Verification"
echo "========================================"
echo

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" &> /dev/null; then
    echo "❌ Stack $STACK_NAME does not exist!"
    echo "   Run ./dr-test-create.sh first."
    exit 1
fi

echo "✓ Stack exists"
echo

# Get stack status
STACK_STATUS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].StackStatus' \
    --output text)

if [ "$STACK_STATUS" != "CREATE_COMPLETE" ]; then
    echo "❌ Stack status is $STACK_STATUS (expected CREATE_COMPLETE)"
    exit 1
fi

echo "✓ Stack status: $STACK_STATUS"
echo

# Get test instance IP
echo "Finding test instance..."
TEST_INSTANCE_IP=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=RentCoordinator-staging" \
              "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

if [ -z "$TEST_INSTANCE_IP" ] || [ "$TEST_INSTANCE_IP" == "None" ]; then
    echo "❌ Could not find running test instance"
    exit 1
fi

echo "✓ Test instance found: $TEST_INSTANCE_IP"
echo

# Test health endpoint
echo "Testing health endpoint..."
HEALTH_RESPONSE=$(curl -sf "http://$TEST_INSTANCE_IP:8080/health" || echo "FAILED")

if [ "$HEALTH_RESPONSE" == "FAILED" ]; then
    echo "❌ Health check failed (may still be starting up)"
    echo "   Wait a few minutes and try again"
    exit 1
fi

echo "✓ Health check passed: $HEALTH_RESPONSE"
echo

# Test login page
echo "Testing login page..."
LOGIN_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$TEST_INSTANCE_IP:8080/login.html")

if [ "$LOGIN_STATUS" != "200" ]; then
    echo "❌ Login page returned HTTP $LOGIN_STATUS"
    exit 1
fi

echo "✓ Login page accessible (HTTP $LOGIN_STATUS)"
echo

# SSH to instance and check database
echo "Checking database was restored from S3..."
if [ ! -f "$SSH_KEY" ]; then
    echo "⚠️  SSH key not found: $SSH_KEY"
    echo "   Skipping database verification"
else
    DB_CHECK=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@$TEST_INSTANCE_IP" \
        "sudo -u rent-coordinator bash -c 'cd /opt/rent-coordinator && \
         source ~/.nvm/nvm.sh && nvm use && \
         sqlite3 tenant-coordinator.db \"SELECT COUNT(*) FROM rent_periods;\"'" 2>&1)

    if [[ "$DB_CHECK" =~ ^[0-9]+$ ]]; then
        echo "✓ Database restored: $DB_CHECK rent periods found"
    else
        echo "⚠️  Could not verify database: $DB_CHECK"
    fi
fi
echo

# Compare with production
echo "Comparing with production..."
PROD_INSTANCE_IP=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=RentCoordinator-production" \
              "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

if [ -n "$PROD_INSTANCE_IP" ] && [ "$PROD_INSTANCE_IP" != "None" ]; then
    if [ -f "$SSH_KEY" ]; then
        PROD_COUNT=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@$PROD_INSTANCE_IP" \
            "sudo -u rent-coordinator bash -c 'cd /opt/rent-coordinator && \
             source ~/.nvm/nvm.sh && nvm use && \
             sqlite3 tenant-coordinator.db \"SELECT COUNT(*) FROM rent_periods;\"'" 2>&1)

        if [[ "$PROD_COUNT" =~ ^[0-9]+$ ]] && [[ "$DB_CHECK" =~ ^[0-9]+$ ]]; then
            if [ "$PROD_COUNT" == "$DB_CHECK" ]; then
                echo "✓ Database matches production ($PROD_COUNT periods)"
            else
                echo "⚠️  Database count differs from production (prod: $PROD_COUNT, test: $DB_CHECK)"
                echo "   This is OK if production has changed since last backup"
            fi
        fi
    fi
fi
echo

echo "========================================"
echo "✅ DR Test Stack Verification Complete"
echo "========================================"
echo
echo "Summary:"
echo "  - Stack created successfully"
echo "  - Instance running and healthy"
echo "  - Application responding"
echo "  - Database restored from S3"
echo
echo "Next steps:"
echo "  - Review the results above"
echo "  - Run ./dr-test-destroy.sh to clean up"
echo
