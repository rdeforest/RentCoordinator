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
```

Deploying to production is a procedure, not a one-liner (AWS ASG, in-place
`git pull` + restart, init-system and ASG-suspend specifics) — see
[docs/deployment.md](docs/deployment.md). SSH user is `admin` on the current
Devuan AMI.

### Build System
The server automatically compiles client-side CoffeeScript to JavaScript on startup. Server-side CoffeeScript runs directly via the `coffee` command. No separate build step needed — just start the server.

### Deployment System

Production is AWS CloudFormation + an Auto Scaling Group behind an ALB;
instances pull `main` from GitHub on boot. The full procedure — including the
in-place upgrade path and the ASG/restart specifics — lives in the canonical
docs, not here:

- **[docs/deployment.md](docs/deployment.md)** — deployment procedure
- **[infrastructure/README.md](infrastructure/README.md)** — CloudFormation / infra
- **[migrations/README.md](migrations/README.md)** — DB migrations
- **[docs/disaster-recovery.md](docs/disaster-recovery.md)** — disaster recovery

There is also a legacy remote-install ("vault2") path under `scripts/`; it is
not how production runs today.

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

See [docs/architecture.md](docs/architecture.md) for the current
layer-by-layer layout and data flow — it's the source of truth. In brief:
`lib/` is the server (config, middleware, routing, plus the `db/`,
`services/`, `models/`, `routes/` layers), `static/` is the frontend
(`coffee/` source compiled to `js/`), `docs/` the documentation,
`migrations/` the manual DB migrations, and `test/` the suite. (A
hand-maintained file tree lived here and drifted out of date, so it now
points at architecture.md rather than duplicating it.)

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
- `STRIPE_WEBHOOK_SECRET` — Stripe webhook signing secret (whsec_...); required for `POST /payment/webhook` to accept ACH settlement events

### Backup and Disaster Recovery

- No `npm run backup`. Server-side backups run via `./scripts/backup-now.sh`,
  which calls the backup service directly — the `/api/backup` endpoint is
  auth-gated (for the UI/authenticated callers), so cron and scripts use the
  shell path, not curl. Local copies land in `./backups/`; S3 uploads to
  `rent-coordinator-backups-822812818413` (us-west-2, 30-day retention).
- Automated: a nightly cron (02:00 UTC) and an in-app idle-backup (after ~1h
  of write-inactivity) both run `backup-now.sh`.
- Secrets live in AWS Secrets Manager (`rent-coordinator/config`, us-west-2),
  written into each instance's `.env` at boot; `./scripts/restore-secrets.sh`
  pushes them to a running host.

Canonical references: backup API in
[scripts/BACKUP-API.md](scripts/BACKUP-API.md); restoration and DR in
[docs/disaster-recovery.md](docs/disaster-recovery.md). Log review — since
CloudWatch shipping is dead on the Devuan AMI — is the `/admin/logs` page.

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

The live bug index is [docs/bugs/](docs/bugs/) — per-bug files with status,
plus Active / Resolved tables in the [README](docs/bugs/README.md), and
proposed patches for the pre-audit bugs in [docs/fixes/](docs/fixes/). That
index is the source of truth; this file deliberately does **not** re-list
bugs or their statuses (that duplication is exactly what used to drift).

One structural note worth having before you touch the rent code: the app
still runs two "what's owed" models — the event-sourced `events` table the
dashboard reads, and the legacy `rent_periods` / `rent_events` tables that
the recurring-events and payment-history paths still write — with nothing
reconciling them. Picking one model and routing all writes through it is the
durable fix (see docs/bugs 26 and 27).
