# claude.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Documentation Index

If you're investigating a problem, start with these before diving into code:

- **[docs/architecture.md](docs/architecture.md)** — one-page tour of how
  the pieces fit together. Read this when you need to remember where a
  thing lives.
- **[docs/bugs/](docs/bugs/)** — active known bugs, one file each, with
  reproduction steps and root cause.
- **[docs/fixes/](docs/fixes/)** — proposed patches for the known bugs.
- **[docs/code-review-2026-05.md](docs/code-review-2026-05.md)** — most
  recent code review with structural concerns and recommended cleanups.
- **[docs/disaster-recovery.md](docs/disaster-recovery.md)** — full
  disaster recovery procedures.
- **[docs/deployment.md](docs/deployment.md)** — deployment procedures.
- **[migrations/README.md](migrations/README.md)** — how migrations work
  in this project (manual, no framework).

When adding a new bug or fix, follow the patterns in `docs/bugs/README.md`
and put the corresponding patch in `docs/fixes/`.

## Project Overview

RentCoordinator is a Node.js-based tenant coordination application for tracking work hours, calculating rent credits, and managing reimbursements between Robert and Lyndzie. Built with CoffeeScript on both server and client sides.

GitHub: `rdeforest/RentCoordinator`.

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
ssh -i ~/.ssh/id_aws_rdeforest admin@<INSTANCE_IP> "sudo systemctl restart rent-coordinator"
```

The SSH user is `admin` on the current Debian-based AMI. If you're working
against an Ubuntu instance, use `ubuntu` instead.

### Build System
The server automatically compiles client-side CoffeeScript to JavaScript on startup. Server-side CoffeeScript runs directly via the `coffee` command. No separate build step needed — just start the server.

### Deployment System

RentCoordinator supports two deployment models:

#### 1. AWS Infrastructure Automation (Recommended)
**Automated cloud deployment** using AWS CloudFormation:

**Features:**
- Auto Scaling Group (ReplaceUnhealthy suspended — instances stay up when unhealthy rather than being terminated)
- Zero-touch deployment from GitHub
- IAM roles for secure Secrets Manager access
- Auto-registration with Application Load Balancer
- Health checks visible via CloudWatch
- Scale up/down on demand

**Quick Start:**
```bash
cd infrastructure
cp cloudformation/parameters-example.json cloudformation/parameters.json
:# Edit parameters.json with your AWS settings
./deploy.sh deploy
```

See `infrastructure/README.md` for complete AWS deployment guide.

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
- **Frontend**: Compiled JavaScript (from CoffeeScript) — no longer browser-compiled
- **Database**: SQLite (using node:sqlite built-in module)
- **Build**: CoffeeScript compiler for client-side code

## Architecture

For the full layered architecture and data flow diagrams, see
[docs/architecture.md](docs/architecture.md). The summary below is
preserved for quick reference.

### Project Structure
```
lib/
├── config.coffee          - Environment config and constants
├── logger.coffee          - Structured error logging with PII tokenization
├── middleware.coffee      - Express middleware and auth middleware
├── routing.coffee         - Main route definitions, health checks, timer API
├── db/
│   ├── schema.coffee      - Database initialization and table definitions
│   └── utils.coffee       - SQL parameter formatting helper
├── services/              - Business logic layer
│   ├── timer.coffee       - Timer operations and session management
│   ├── rent.coffee        - Rent calculation logic
│   ├── recurring_events.coffee - Recurring events processing
│   ├── backup.coffee      - Database backup/restore
│   ├── email.coffee       - Email verification codes
│   ├── payment.coffee     - Stripe payment processing
│   └── tokenization.coffee - PII tokenization for logs
├── models/                - Data access layer
│   ├── work_session.coffee - Work session CRUD operations
│   ├── work_log.coffee    - Work log management
│   ├── rent.coffee        - Rent periods, events, audit logs
│   ├── rent_configuration.coffee - Singleton rent configuration
│   ├── recurring_events.coffee - Recurring events CRUD
│   └── auth.coffee        - Auth verification codes and validation
└── routes/                - Route handlers
    ├── work.coffee        - Work management routes
    ├── rent.coffee        - Rent-related endpoints
    ├── recurring_events.coffee - Recurring events API
    ├── auth.coffee        - Authentication endpoints
    ├── payment.coffee     - Stripe checkout flow
    ├── payments.coffee    - Payment history CRUD (NOTE: different from payment.coffee)
    ├── backup.coffee      - Backup endpoints
    └── admin.coffee       - Admin endpoints

static/                    - Frontend assets
├── coffee/                - Frontend CoffeeScript (source)
│   ├── auth.coffee        - Shared auth utilities
│   ├── login.coffee       - Login page logic
│   ├── rent.coffee        - Rent dashboard logic
│   ├── work.coffee        - Work page logic
│   ├── timer.coffee       - Timer logic
│   ├── payment.coffee     - Stripe checkout page logic
│   ├── payments.coffee    - Payment history page logic
│   └── shared-utils.coffee - Shared frontend utilities
├── js/                    - Compiled JavaScript (served to browser)
├── css/                   - Stylesheets
└── *.html                 - HTML pages (index, work, rent, login, payment, payments, admin)

scripts/                   - Build and deployment scripts
├── build.ts               - CoffeeScript compilation and asset copying
├── backup.ts              - Backup logic (called by backup service, not directly)
├── backup-now.sh          - Shell wrapper to trigger a backup manually
├── backup-list.sh         - List available S3 backups
├── backup-restore.sh      - Restore from S3 backup
└── upgrade.sh             - Production upgrade automation

migrations/                - Database migrations (see migrations/README.md)
├── 001-add-discount-applied.sql
├── 002-add-amount-due-manual.sql
└── 2026-03-17_add_amount_paid_manual.coffee

docs/                      - Project documentation (see Documentation Index above)
├── architecture.md
├── code-review-2026-05.md
├── bugs/                  - Known bugs, one file each
├── fixes/                 - Proposed patches
├── disaster-recovery.md
├── deployment.md
├── cloudwatch-logs-setup.md
├── health-checks.md
├── nginx.md
├── todo.md
└── troubleshooting.md

backups/                   - Database backups (gitignored)

test/                      - Test suite
├── integration/           - Integration tests
│   ├── auth.coffee        - Authentication flow tests (including session race conditions)
│   └── timer.coffee       - Timer system tests
├── services/              - Unit tests for services
└── helper.coffee          - Test utilities
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
Uses SQLite (via node:sqlite) with tables for projects, tasks, work_sessions, work_events, work_logs, timer_state, rent_periods, rent_events, audit_logs, recurring_events, recurring_event_logs, rent_configuration, auth_sessions, and pii_tokens. Designed with proper foreign key constraints and indexes for performance.

See [docs/architecture.md](docs/architecture.md) for the data model with
computed-vs-authoritative column notes.

### Core Domains

#### Timer System
- Multi-worker support (robert, lyndzie)
- Session-based work tracking with start/pause/resume/stop
- Real-time status updates via polling API
- Automatic session timeout after 8 hours
- Manual work entry via POST /work-logs endpoint
- **Bug Fix** (2025-12-29): Fixed SQL parameter binding for `billable` field — must pass 0/1 integers, not JavaScript booleans

#### Rent Coordination

**Business Rules:**
- Base rent: $1600/month (due on the 15th)
- Agreed payment: $950/month from Lyndzie
- Hourly credit: $50/hour worked (max 8 hours/month creditable = $400)
- Excess hours roll over to next month
- Comprehensive event tracking system (payments, adjustments, manual entries)
- Rent calculation based on work logs with manual adjustments
- Audit logging for all rent events

**Display Logic (event-sourced, 2026-06):**
- Past months: show the real amount owed (calculated from work credits;
  if the landlord pinned a different value via an `override` event, that
  pinned value shows instead). The temporary $950 agreement that ran
  through Feb 2026 lives in history as `override` events on those
  specific months — there is no global "$950 mask" on past months.
- Current month: $0 before the 15th, agreed_payment after.
- Future months: full calculation.
- Payment status: NOT DUE (current month before 15th), PAID (paid ≥
  display_amount_due), PARTIAL, UNPAID.
- Constants: AGREED_MONTHLY_PAYMENT = 950, RENT_DUE_DAY = 15.

The server-side implementation lives in
`lib/services/period.coffee::computeMonth` and is the source of truth.
The route handlers (`lib/routes/rent.coffee`) consume it via
`period_viewer`. The client must not duplicate this logic — fetch
`display_amount_due` from the period payload instead.

See `docs/event-model.md` for the full event model.

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
- `PORT` — Server port (default: 3000)
- `NODE_ENV` — Environment mode (development/production)
- `DB_PATH` — SQLite database path (default: ./tenant-coordinator.db)
- `SESSION_SECRET` — Secret for session encryption (required for production)
- `SMTP_HOST` — SMTP server for sending verification emails (optional in dev)
- `SMTP_PORT` — SMTP port (default: 587)
- `SMTP_USER` — SMTP username
- `SMTP_PASS` — SMTP password
- `EMAIL_FROM` — From address for emails (default: noreply@thatsnice.org)
- `STRIPE_SECRET_KEY` — Stripe API secret key (sk_test_... or sk_live_...)
- `STRIPE_PUBLISHABLE_KEY` — Stripe publishable key (pk_test_... or pk_live_...)

### Backup and Disaster Recovery

**Backups:**
- There is no `npm run backup`. Backups are triggered via API or shell scripts.
- Local backups land in `./backups/` as timestamped SQLite files
- S3 backups auto-upload to `rent-coordinator-backups-822812818413` (us-west-2), 30-day retention
- **TODO:** Daily automated backups are not yet implemented — currently manual only

```bash
:# Trigger a backup via API (requires auth session cookie)
curl -X POST https://rent.thatsnice.org/api/backup \
  -H "Cookie: <session-cookie>"

:# Or from the server directly (bypasses auth)
curl -X POST http://localhost:3000/api/backup

:# Check backup status
curl https://rent.thatsnice.org/api/backup/status

:# List all S3 backups
curl https://rent.thatsnice.org/api/backup/list

:# Shell script alternative (runs on the server)
./scripts/backup-now.sh
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

See `docs/disaster-recovery.md` for complete restoration procedures.

### Startup Process
1. Server startup compiles client-side CoffeeScript to `static/js/`
2. Server runs directly from source via `coffee main.coffee`
3. Static files served from `static/`
4. Recurring events scheduler initializes and processes any due events

No separate build step needed — compilation happens automatically on startup.

## Development Notes

- **Node.js Version**: Uses nvm with Node 24 LTS (`.nvmrc` file in repo root)
- **Client-side**: CoffeeScript compiled to JavaScript on server startup
- **Server-side**: CoffeeScript runs directly via coffee command
- **Database**: Uses SQLite via Node.js built-in `node:sqlite` module (Node 22+)
- **Workers**: Hardcoded as ['robert', 'lyndzie'] in config
- **Frontend**: Loads compiled JavaScript, polls `/timer/status` every second for live updates

### Local Development Setup
```bash
:# Install nvm (if not already installed)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

:# Use the project's Node version
nvm install
nvm use

:# Install dependencies and run
npm install
npm start
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

The active list lives in [docs/bugs/](docs/bugs/). At time of last review
(2026-05-19) the open bugs were:

- **01** — Periods table shows raw amount instead of stress-free display
- **02** — Cannot delete rent period (FK constraint)
- **03** — Soft-delete UI wired to hard-delete model
- **04** — Lyndzie's work hours not appearing in rent periods (the 48.75-hour case)
- **05** — Recalculate-all discards retroactive logic

Each has a proposed fix in [docs/fixes/](docs/fixes/).

A full-codebase audit on 2026-08-15 added bugs **06–48** — see the
[docs/bugs/](docs/bugs/) index (each has its diagnosis and an inline fix
sketch; none have a `docs/fixes/` file yet). Highlights worth knowing
before you touch the rent code:

- **06** — Work hours never credit rent: nothing emits a `work-reported`
  event, so the event-sourced dashboard always shows 0 hours. This is the
  live cause of bug 04's symptom (whose old case/timezone suspects no
  longer apply).
- **09 / 10** — ACH payments are never recorded (no Stripe webhook), and
  payment confirmation isn't idempotent (double-credits on retry).
- **11 / 12 / 13** — Auth: `SESSION_SECRET` falls back to a public default
  in production; the verification code has no brute-force lockout and uses
  `Math.random()`.

The recurring structural cause (underlies 06, 09, 26, 27) is that the app
still runs two parallel "what's owed" models — the event-sourced `events`
table the dashboard reads, and the legacy `rent_periods`/`rent_events`
tables that work/payment/recurring writes still update — with nothing
reconciling them. A durable fix picks one model and routes all writes
through it.

When a new issue is discovered, add a file to `docs/bugs/` rather than
appending to this list — that way the index stays the source of truth and
this section doesn't drift out of date.
