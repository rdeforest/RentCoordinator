# claude.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RentCoordinator is a Node.js-based tenant coordination application for tracking work hours, calculating rent credits, and managing reimbursements between Robert and Lyndzie. Built with CoffeeScript on both server and client sides.

## Development Commands

### Essential Commands
```bash
:# Start server (compiles client JS on startup, runs server)
npm start

:# Run integration tests
npm run test:integration

:# Local installation (current machine)
./scripts/install.sh

:# AWS deployment (current production method)
cd infrastructure
./deploy.sh deploy

:# Manual instance update (SSH to current instance)
:# Find current instance IP: aws ec2 describe-instances --filters "Name=tag:Name,Values=RentCoordinator-production" --query 'Reservations[*].Instances[*].PublicIpAddress'
ssh -i ~/.ssh/id_aws_rdeforest ubuntu@<INSTANCE_IP> "sudo systemctl restart rent-coordinator"
```

### Build System
The server automatically compiles client-side CoffeeScript to JavaScript on startup. Server-side CoffeeScript runs directly via the `coffee` command. No separate build step needed - just start the server.

### Deployment System

RentCoordinator supports two deployment models:

#### 1. AWS Infrastructure Automation (Recommended)
**Automated cloud deployment** using AWS CloudFormation:

**Features:**
- Auto Scaling Group with automatic instance replacement
- Zero-touch deployment from GitHub
- IAM roles for secure Secrets Manager access
- Auto-registration with Application Load Balancer
- Health checks and automatic rollback
- Scale up/down on demand

**Quick Start:**
```bash
cd infrastructure
cp cloudformation/parameters-example.json cloudformation/parameters.json
:# Edit parameters.json with your AWS settings
./deploy.sh deploy
```

See `infrastructure/README.md` for complete AWS deployment guide.

#### 2. Manual Remote Deployment (Legacy)
**Push-based remote deployment** to individual servers:

**Local Scripts** (run from dev machine):
- `deploy-install.sh <host>` - First-time installation on remote server
- `deploy-upgrade.sh <host>` - Safe upgrade with automatic rollback
- `deploy-uninstall.sh <host>` - Remove installation from remote

**How it works:**
1. Build project locally on dev machine
2. Create deployment package
3. Push to remote server via rsync
4. Execute remote installation/upgrade script
5. Automatic health checks and rollback on failure

**Upgrade safety features:**
- Automatic database backup before upgrade
- Atomic swap between versions (dist.new → dist, dist.old for rollback)
- Health check verification after deployment
- Automatic rollback if health check fails
- Database and config never touched during upgrades

**Remote structure:**
```
~/rent-coordinator/
├── dist/              # Active version
├── dist.old/          # Previous version (for rollback)
├── config.sh          # Configuration (persists across upgrades)
├── tenant-coordinator.db  # Database (never deleted)
└── backups/           # Automatic backups
```

See `scripts/deployment.md` for complete manual deployment documentation.
See `migrations/README.md` for database migration guide.
See `docs/disaster-recovery.md` for complete disaster recovery procedures.

### Logging and Monitoring

**CloudWatch Logs** (deployed 2025-12-29):
- Application logs shipped to CloudWatch Logs in real-time
- Log group: `/rent-coordinator/application`
- View logs: `aws logs tail /rent-coordinator/application --follow`
- Setup script: `infrastructure/setup-cloudwatch-logs.sh`
- Full documentation: `docs/cloudwatch-logs-setup.md`

**Log Architecture:**
1. `rent-coordinator.service` → journald
2. `rent-coordinator-logs.service` → `/var/log/rent-coordinator/application.log`
3. CloudWatch Agent → CloudWatch Logs

## Technology Stack

- **Runtime**: Node.js 24 LTS (managed via nvm) with CoffeeScript
- **Backend**: Express.js server with CoffeeScript source, compiled to JavaScript
- **Frontend**: Compiled JavaScript (from CoffeeScript) - no longer browser-compiled
- **Database**: SQLite (using node:sqlite built-in module)
- **Build**: CoffeeScript compiler for client-side code

## Architecture

### Project Structure
```
lib/
├── config.coffee          - Environment config and constants
├── db/schema.coffee       - Database initialization and KV setup
├── middleware.coffee      - Express middleware and auth middleware
├── routing.coffee         - Main route definitions and timer API
├── services/             - Business logic layer
│   ├── timer.coffee      - Timer operations and session management
│   ├── rent.coffee       - Rent calculation logic
│   ├── recurring_events.coffee - Recurring events processing
│   ├── backup.coffee     - Database backup/restore
│   └── email.coffee      - Email verification codes
├── models/               - Data access layer
│   ├── work_session.coffee - Work session CRUD operations
│   ├── work_log.coffee   - Work log management
│   ├── rent.coffee       - Rent periods, events, audit logs
│   └── auth.coffee       - Auth verification codes and validation
└── routes/               - Route handlers
    ├── work.coffee       - Work management routes
    ├── rent.coffee       - Rent-related endpoints
    ├── recurring_events.coffee - Recurring events API
    └── auth.coffee       - Authentication endpoints

static/                   - Frontend assets
├── coffee/               - Frontend CoffeeScript (source)
│   ├── auth.coffee       - Shared auth utilities
│   └── login.coffee      - Login page logic
├── js/                   - Compiled JavaScript (served to browser)
├── css/                  - Stylesheets
└── *.html               - HTML pages (index, work, rent, login)

scripts/                  - Build and deployment scripts
├── build.ts              - CoffeeScript compilation and asset copying
├── backup.ts             - Database backup CLI
└── upgrade.sh            - Production upgrade automation

migrations/               - Database migrations (empty for now)
└── README.md             - Migration documentation

backups/                  - Database backups (gitignored)

test/                     - Test suite
├── integration/          - Integration tests
│   ├── auth.coffee       - Authentication flow tests (including session race conditions)
│   └── timer.coffee      - Timer system tests
├── services/             - Unit tests for services
└── helper.coffee         - Test utilities
```

### Testing

**Integration Tests:**
- Use Node's built-in test runner (no additional test framework needed)
- Start isolated server instances with temporary databases
- Test full HTTP request/response cycles with real sessions
- Auth tests verify session persistence immediately after verification (catches race conditions)
- Run with: `npm run test:integration`

**Key Testing Insights:**
- Session race conditions manifest as flakiness, not timing issues
- Test the invariant (session available after response) not the timing
- No need for headless browsers or sleep() calls to test session persistence
- Use native `node:sqlite` DatabaseSync for test database inspection

### Database Design
Uses SQLite (via node:sqlite) with tables for projects, tasks, work_sessions, work_events, work_logs, timer_state, rent_periods, rent_events, audit_logs, recurring_events, and auth_sessions. Designed with proper foreign key constraints and indexes for performance.

### Core Domains

#### Timer System
- Multi-worker support (robert, lyndzie)
- Session-based work tracking with start/pause/resume/stop
- Real-time status updates via polling API
- Automatic session timeout after 8 hours
- Manual work entry via POST /work-logs endpoint
- **Bug Fix** (2025-12-29): Fixed SQL parameter binding for `billable` field - must pass 0/1 integers, not JavaScript booleans

#### Rent Coordination

**Business Rules:**
- Base rent: $1600/month (due on the 15th)
- Agreed payment: $950/month from Lyndzie
- Hourly credit: $50/hour worked (max 8 hours/month creditable = $400)
- Excess hours roll over to next month
- Comprehensive event tracking system (payments, adjustments, manual entries)
- Rent calculation based on work logs with manual adjustments
- Audit logging for all rent events

**Stress-Free Display Logic:**
- Current/past months show $950 as "amount due" (not full $1600)
- Current month shows $0 before the 15th, $950 after the 15th
- Future months show full calculation ($1600 - work credits)
- Payment status shows PAID when >= $950 paid (green, stress-free)
- "Outstanding Balance" and "Total Paid" hidden behind "Show Full Details" button
- Real debt tracked in background for gradual catch-up over 1-3 years
- Constants: AGREED_MONTHLY_PAYMENT = 950, RENT_DUE_DAY = 15

**Stripe Integration:**
- Live mode enabled (pk_live_... and sk_live_... keys)
- Keys stored in AWS Secrets Manager and server .env file
- Payment processing for monthly rent payments via ACH Direct Debit
- API version: 2024-12-18.acacia
- **Error Handling** (enhanced 2025-12-29):
  - All PaymentIntent statuses properly handled: succeeded, processing, requires_payment_method, requires_action, canceled, requires_capture
  - User-friendly error messages for common issues (insufficient funds, closed accounts, verification failures)
  - Comprehensive logging of payment intent creation and confirmation
  - ACH-specific messaging (4-5 business days processing time)

#### Authentication System

**Current Implementation:**
- Email-based verification code authentication (6-digit codes, 10-minute expiration)
- Session management with 90-day cookie expiration
- Whitelist-based access control (robert@defore.st, lynz57@hotmail.com)
- All routes protected except `/login.html`, `/auth/*`, and `/health`
- Browser requests redirect to login page, API requests return 401 JSON
- Console logging in development, AWS SES SMTP in production

**Email Configuration:**
- Production uses AWS SES SMTP (email-smtp.us-west-2.amazonaws.com:587)
- Account in SES sandbox mode (can only send to verified addresses)
- Both allowed emails (robert@defore.st, lynz57@hotmail.com) are verified
- Sender domain (defore.st) and email (noreply@defore.st) verified
- Credentials stored in AWS Secrets Manager (rent-coordinator/config)

**Session Management Implementation Notes:**
- CRITICAL: Must call `await req.session.save()` before responding after session modifications
- Without explicit save, race condition exists between session persistence and response
- Manifests as: user verifies code successfully but gets logged out on redirect
- Tests in test/integration/auth.coffee verify session persistence without timing hacks

**Future OAuth Migration Plan:**

*Phase 1: Current (Stable)*
- Email verification working well with 90-day sessions
- Minimal login frequency due to long session duration
- Adequate security for 2-user application

*Phase 2: Authelia (3-6 months, Learning Project)*
- Set up lightweight self-hosted OAuth provider
- Low operational complexity (<30MB footprint, 1-2 hrs/month maintenance)
- Good learning experience with OAuth/OIDC
- Can run on existing infrastructure ($0 cost)
- Resources: Single instance with Redis for sessions
- Target: Educational value + control over auth

*Phase 3: Keycloak (6+ months, Teaching Platform)*
- Upgrade to enterprise-grade OAuth provider
- Better for teaching friends about IAM
- Full OAuth 2.0 / OpenID Connect compliance
- Industry-standard skills transferable to enterprise
- Resources: Single instance + PostgreSQL (~$30/month or use existing infra)
- Target: Educational platform for helping friends learn tech

**Design Constraints:**
- 90% uptime acceptable (not high-availability requirements)
- 2 users only (no scale requirements)
- Educational value prioritized over operational efficiency
- Self-hosted to support migration away from Google services

### Key Configuration
- Workers defined in `config.WORKERS` array
- Allowed emails defined in `config.ALLOWED_EMAILS` array
- Timer polling interval: 1000ms client-side

### Environment Variables
- `PORT` - Server port (default: 3000)
- `NODE_ENV` - Environment mode (development/production)
- `DB_PATH` - SQLite database path (default: ./tenant-coordinator.db)
- `SESSION_SECRET` - Secret for session encryption (required for production)
- `SMTP_HOST` - SMTP server for sending verification emails (optional in dev)
- `SMTP_PORT` - SMTP port (default: 587)
- `SMTP_USER` - SMTP username
- `SMTP_PASS` - SMTP password
- `EMAIL_FROM` - From address for emails (default: noreply@thatsnice.org)
- `STRIPE_SECRET_KEY` - Stripe API secret key (sk_test_... or sk_live_...)
- `STRIPE_PUBLISHABLE_KEY` - Stripe publishable key (pk_test_... or pk_live_...)

### Backup and Disaster Recovery

**Automated Backups:**
```bash
:# Create database backup
npm run backup

:# Restore from backup
npm run restore backups/backup-YYYY-MM-DD*.json

:# Backups include:
:# - All SQLite database data
:# - Non-sensitive configuration (port, business rules, etc.)
:# - Database schema version
```

**Secrets Management:**
- Application secrets stored in AWS Secrets Manager
- Secret name: `rent-coordinator/config` (us-west-2)
- Protected by IAM credentials

```bash
:# Restore secrets to a server
./scripts/restore-secrets.sh vault2

:# Manual secret retrieval
aws secretsmanager get-secret-value \
  --secret-id rent-coordinator/config \
  --region us-west-2 \
  --query 'SecretString' \
  --output text
```

See `DISASTER-RECOVERY.md` for complete restoration procedures.

### Startup Process
1. Server startup compiles client-side CoffeeScript to `static/js/`
2. Server runs directly from source via `coffee main.coffee`
3. Static files served from `static/`

No separate build step needed - compilation happens automatically on startup.

## Development Notes

- **Node.js Version**: Uses nvm with Node 24 LTS (`.nvmrc` file in repo root)
- **Client-side**: CoffeeScript compiled to JavaScript on server startup
- **Server-side**: CoffeeScript runs directly via coffee command
- **Database**: Uses SQLite via Node.js built-in `node:sqlite` module (Node 22+)
- **Workers**: Hardcoded as ['robert', 'lyndzie'] in config
- **Frontend**: Loads compiled JavaScript, polls `/timer/status` every second for live updates
- **Hot Reload**: Available in dev mode with file watching

### Local Development Setup
```bash
:# Install nvm (if not already installed)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

:# Use the project's Node version
nvm install
nvm use

:# Install dependencies and run
npm install
npm run dev
```

## Planned Features

### Work Item Comments System
**Requested:** 2026-01-05

Add commenting functionality to work items with bidirectional notifications:

**Requirements:**
- Both Robert and Lyndzie can add comments to work items (work_logs, rent_periods, and/or rent_events)
- Comment thread display on work item details
- Notification system: Email users if they haven't seen a comment 3 days after it was posted
- Bidirectional: Works for both users

**Design Notes (from exploration):**
- Two-table structure:
  - `work_item_comments`: id, work_item_type, work_item_id, author, content, created_at, updated_at
  - `comment_seen_status`: comment_id, user, seen_at (tracks who has seen each comment)
- Scheduled notification check (daily cron-like task)
- Integrate with existing Nodemailer email service
- Frontend: Add comment UI to work items interface (modal or inline)
- Follow existing CoffeeScript + SQLite patterns

**Status:** Design phase complete, awaiting implementation decision

## Known Issues

### Work Hours Not Appearing in Rent Periods (2026-01-01)
**Reported:** Lyndzie entered 48.75 hours in production, but they're not showing up in the rent periods list.

**Investigation needed:**
- Verify work logs are being saved correctly in database
- Check if rent calculation is pulling work logs for the correct date range
- Verify rent period recalculation is including the hours
- Check if there's a worker name mismatch or filtering issue
- Review `lib/services/rent.coffee` calculateRent function
- Review work log queries in `lib/models/work_log.coffee`
