# Health Check Endpoints

## Overview

The application provides two health check endpoints with different readiness criteria:

- `/health` - **Liveness check** with database validation
- `/health/ready` - **Readiness check** that only passes after full initialization

## Endpoints

### `GET /health` - Liveness Check

Returns 200 when the application is alive and the database is accessible.

**Checks performed:**
- Database file exists at `DB_PATH`
- Database connection succeeds
- Critical tables exist (`work_logs`, `rent_periods`, `timer_state`)

**Response (healthy):**
```json
{
  "status": "healthy",
  "version": "0.1.1",
  "uptime": 45,
  "timestamp": "2026-02-13T21:41:21.164Z",
  "ready": true
}
```

**Response (unhealthy - 503):**
```json
{
  "status": "unhealthy",
  "error": "Database file not found",
  "dbPath": "./tenant-coordinator.db",
  "timestamp": "2026-02-13T21:41:21.164Z"
}
```

**Use case:** ALB target group health checks, monitoring systems

### `GET /health/ready` - Readiness Check

Returns 200 only after the application has fully initialized.

**Checks performed:**
- Database initialized
- Database connectable
- Schema valid
- Recurring events scheduler started
- Application marked as ready

**Response (ready):**
```json
{
  "status": "ready",
  "version": "0.1.1",
  "uptime": 45
}
```

**Response (not ready - 503):**
```json
{
  "status": "not_ready",
  "dbInitialized": true,
  "dbConnectable": true,
  "schemaValid": true,
  "startupComplete": false
}
```

**Use case:** Kubernetes readiness probes, strict initialization checks

## Startup Flow

1. **Database initialization** (`db.initialize()`)
   - Creates schema if needed
   - Checks for existing database
   - Attempts S3 restore if database missing

2. **Middleware and routing setup**
   - Express middleware configured
   - Routes registered

3. **Server listening**
   - HTTP server starts on port 3000

4. **Service initialization**
   - Recurring events scheduler starts

5. **Application ready**
   - `routing.markAppReady()` called
   - `/health/ready` now returns 200

## Current ALB Configuration

**Target Group Health Check:**
- Path: `/health`
- Interval: 30 seconds
- Healthy threshold: 5 successes (150 seconds total)
- Unhealthy threshold: 2 failures (60 seconds)
- Timeout: 5 seconds
- Expected: 200

**Issue:** The previous `/health` endpoint returned 200 immediately when the HTTP server started, even if the database wasn't ready or S3 restore was still in progress. This caused the ALB to mark instances as "healthy" before they could actually serve requests.

**Fix:** The new `/health` endpoint validates database connectivity, so instances won't be marked healthy until they're actually ready to serve traffic.

## Recommendations

### Option 1: Use Current `/health` (Recommended)

Keep using `/health` for ALB health checks. The improved validation now ensures:
- Database is accessible
- Critical tables exist
- App can serve requests

**Pros:**
- No infrastructure changes needed
- Already deployed
- Adequate for most use cases

**Cons:**
- None significant

### Option 2: Switch to `/health/ready` (Stricter)

Update ALB target group to use `/health/ready` for even stricter checks.

```bash
# Update target group health check path
aws elbv2 modify-target-group \
  --target-group-arn "arn:aws:elasticloadbalancing:us-west-2:822812818413:targetgroup/RentCoordinator/faeeb51824fa4106" \
  --health-check-path "/health/ready" \
  --region us-west-2
```

**Pros:**
- Ensures recurring events scheduler is running
- Guarantees full initialization
- More robust readiness validation

**Cons:**
- Slightly longer time to mark healthy
- May need to adjust grace period if initialization takes >150s

### Option 3: Reduce Healthy Threshold (Fastest)

Keep `/health` but reduce the healthy threshold from 5 to 2:

```bash
# Reduce healthy threshold
aws elbv2 modify-target-group \
  --target-group-arn "arn:aws:elasticloadbalancing:us-west-2:822812818413:targetgroup/RentCoordinator/faeeb51824fa4106" \
  --healthy-threshold-count 2 \
  --region us-west-2
```

**Result:** Instances marked healthy after 60 seconds instead of 150 seconds

## Monitoring

### Check Instance Health

```bash
# Via ALB
aws elbv2 describe-target-health \
  --target-group-arn "arn:aws:elasticloadbalancing:us-west-2:822812818413:targetgroup/RentCoordinator/faeeb51824fa4106" \
  --region us-west-2

# Via direct curl
curl https://rent.defore.st/health
curl https://rent.defore.st/health/ready
```

### CloudWatch Logs

Health check failures are logged to `/rent-coordinator/application`:

```bash
aws logs tail /rent-coordinator/application \
  --follow \
  --filter-pattern "Health check failed" \
  --region us-west-2
```

## Version Tracking

Both endpoints now return the application version from `package.json`:

```json
{
  "status": "healthy",
  "version": "0.1.1",
  ...
}
```

This helps verify which version is running on each instance, useful for:
- Deployment verification
- Rolling update monitoring
- Debugging version-specific issues

## Testing

```bash
# Local testing
curl http://localhost:3000/health
curl http://localhost:3000/health/ready

# Production testing
curl https://rent.defore.st/health
curl https://rent.defore.st/health/ready

# Test unhealthy state (requires direct instance access)
ssh ubuntu@INSTANCE_IP
sudo systemctl stop rent-coordinator
curl http://localhost:3000/health  # Should timeout or fail
```
