#!/bin/bash
# Enterprise-style test: Verify data persists across instance replacements
#
# Test flow:
# 1. Terminate current instance
# 2. Wait for new instance (Auto Scaling Group creates it)
# 3. Add test data via API
# 4. Trigger backup via API
# 5. Terminate that instance
# 6. Wait for next instance
# 7. Verify data persisted

set -e

ASG_NAME="RentCoordinator-production-asg"
REGION="us-west-2"
APP_URL="https://rent.defore.st"
TEST_EMAIL="robert@defore.st"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Get current instance ID from ASG
get_current_instance() {
    aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$ASG_NAME" \
        --region "$REGION" \
        --query 'AutoScalingGroups[0].Instances[?HealthStatus==`Healthy`].InstanceId' \
        --output text | head -1
}

# Get instance public IP
get_instance_ip() {
    local instance_id=$1
    aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$REGION" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text
}

# Wait for new healthy instance
wait_for_healthy_instance() {
    log "Waiting for new healthy instance..."
    local max_attempts=60  # 10 minutes
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        local instance_id=$(get_current_instance)

        if [ -n "$instance_id" ]; then
            # Check if instance is running
            local state=$(aws ec2 describe-instances \
                --instance-ids "$instance_id" \
                --region "$REGION" \
                --query 'Reservations[0].Instances[0].State.Name' \
                --output text)

            if [ "$state" = "running" ]; then
                # Wait a bit more for app to start
                log "Instance $instance_id is running, waiting for app to be ready..."
                sleep 30

                # Check health endpoint
                if curl -sf "$APP_URL/health" > /dev/null 2>&1; then
                    success "Instance $instance_id is healthy and app is responding"
                    echo "$instance_id"
                    return 0
                fi
            fi
        fi

        attempt=$((attempt + 1))
        echo -n "."
        sleep 10
    done

    error "Timeout waiting for healthy instance"
    return 1
}

# Request verification code
request_verification_code() {
    log "Requesting verification code for $TEST_EMAIL..."

    response=$(curl -sf -X POST "$APP_URL/auth/request-code" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$TEST_EMAIL\"}")

    if echo "$response" | grep -q "success.*true"; then
        success "Verification code sent"
        return 0
    else
        error "Failed to request verification code: $response"
        return 1
    fi
}

# Verify code and get session (you'll need to check your email)
verify_code() {
    local code=$1
    log "Verifying code $code..."

    response=$(curl -sf -X POST "$APP_URL/auth/verify" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$TEST_EMAIL\",\"code\":\"$code\"}" \
        -c /tmp/rent-cookies.txt)

    if echo "$response" | grep -q "success.*true"; then
        success "Verified! Session saved to /tmp/rent-cookies.txt"
        return 0
    else
        error "Failed to verify code: $response"
        return 1
    fi
}

# Add test data
add_test_data() {
    log "Adding test data via API..."

    local test_data='{
        "worker": "robert",
        "start_time": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "end_time": "'$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%SZ)'",
        "duration": 120,
        "description": "Enterprise persistence test - Instance replacement verification",
        "billable": true
    }'

    response=$(curl -sf -X POST "$APP_URL/work-logs" \
        -H "Content-Type: application/json" \
        -b /tmp/rent-cookies.txt \
        -d "$test_data")

    if echo "$response" | grep -q "id"; then
        local work_log_id=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        success "Created work log: $work_log_id"
        echo "$work_log_id"
        return 0
    else
        error "Failed to create work log: $response"
        return 1
    fi
}

# Trigger backup via API
trigger_backup() {
    log "Triggering backup via API..."

    response=$(curl -sf -X POST "$APP_URL/api/backup" \
        -H "Content-Type: application/json" \
        -b /tmp/rent-cookies.txt)

    if echo "$response" | grep -q "success.*true"; then
        success "Backup created successfully"
        echo "$response" | grep -o '"filename":"[^"]*"' | cut -d'"' -f4
        return 0
    else
        error "Failed to create backup: $response"
        return 1
    fi
}

# Verify data exists
verify_data_exists() {
    local work_log_id=$1
    log "Verifying work log $work_log_id exists..."

    response=$(curl -sf "$APP_URL/work-logs" \
        -H "Content-Type: application/json" \
        -b /tmp/rent-cookies.txt)

    if echo "$response" | grep -q "$work_log_id"; then
        success "Work log $work_log_id found!"
        return 0
    else
        error "Work log $work_log_id NOT FOUND"
        echo "Response: $response"
        return 1
    fi
}

# Terminate instance
terminate_instance() {
    local instance_id=$1
    log "Terminating instance $instance_id..."

    aws ec2 terminate-instances \
        --instance-ids "$instance_id" \
        --region "$REGION" > /dev/null

    success "Termination initiated for $instance_id"
}

# Main test flow
main() {
    log "=== Enterprise-Style Instance Persistence Test ==="
    echo ""

    # Step 1: Terminate current instance
    log "STEP 1: Terminate current instance"
    current_instance=$(get_current_instance)
    if [ -z "$current_instance" ]; then
        error "No healthy instance found in ASG"
        exit 1
    fi
    log "Current instance: $current_instance"
    terminate_instance "$current_instance"
    echo ""

    # Step 2: Wait for new instance
    log "STEP 2: Wait for new instance to be healthy"
    instance1=$(wait_for_healthy_instance)
    if [ -z "$instance1" ]; then
        error "Failed to get healthy instance"
        exit 1
    fi
    echo ""

    # Step 3: Authenticate
    log "STEP 3: Authenticate with the application"
    request_verification_code
    echo ""
    warn "Check your email for the verification code and enter it here:"
    read -p "Verification code: " code
    verify_code "$code" || exit 1
    echo ""

    # Step 4: Add test data
    log "STEP 4: Add test data"
    work_log_id=$(add_test_data)
    if [ -z "$work_log_id" ]; then
        error "Failed to add test data"
        exit 1
    fi
    echo ""

    # Step 5: Trigger backup
    log "STEP 5: Trigger backup"
    backup_file=$(trigger_backup)
    if [ -z "$backup_file" ]; then
        error "Failed to trigger backup"
        exit 1
    fi
    log "Backup file: $backup_file"
    sleep 5  # Give S3 upload time to complete
    echo ""

    # Step 6: Terminate instance again
    log "STEP 6: Terminate instance $instance1"
    terminate_instance "$instance1"
    echo ""

    # Step 7: Wait for next instance
    log "STEP 7: Wait for replacement instance to be healthy"
    instance2=$(wait_for_healthy_instance)
    if [ -z "$instance2" ]; then
        error "Failed to get replacement instance"
        exit 1
    fi
    echo ""

    # Step 8: Verify data persisted
    log "STEP 8: Verify data persisted across instance replacement"
    if verify_data_exists "$work_log_id"; then
        echo ""
        success "=== TEST PASSED ==="
        success "Data successfully persisted across TWO instance replacements!"
        success "Work log $work_log_id survived:"
        success "  Instance 1 (terminated): $current_instance"
        success "  Instance 2 (data added): $instance1"
        success "  Instance 3 (data verified): $instance2"
        exit 0
    else
        echo ""
        error "=== TEST FAILED ==="
        error "Data did NOT persist across instance replacement"
        exit 1
    fi
}

# Run the test
main "$@"
