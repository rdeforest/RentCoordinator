# claude.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RentCoordinator is a Node.js-based tenant coordination application for tracking work hours, calculating rent credits, and managing reimbursements between Robert and Lyndzie. Built with CoffeeScript on both server and client sides.

## Development Commands

### Essential Commands
```bash
:# Development (builds, watches files, runs server)
npm run dev

:# Build only (compiles CoffeeScript to dist/)
npm run build

:# Start production server (requires prior build)
npm run start

:# Local installation (current machine)
./scripts/install.sh

:# Remote deployment (to production server)
./scripts/deploy-install.sh vault2.thatsnice.org
./scripts/deploy-upgrade.sh vault2.thatsnice.org
./scripts/deploy-uninstall.sh vault2.thatsnice.org
```

### Build System
The build system (scripts/build.ts) compiles CoffeeScript files to JavaScript, handles import path rewriting (.coffee → .js), and copies static assets to dist/. Watch mode rebuilds on changes and restarts the server automatically.

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
```

### Database Design
Uses SQLite (via node:sqlite) with tables for projects, tasks, work_sessions, work_events, work_logs, timer_state, rent_periods, rent_events, audit_logs, recurring_events, and auth_sessions. Designed with proper foreign key constraints and indexes for performance.

### Core Domains

#### Timer System
- Multi-worker support (robert, lyndzie)
- Session-based work tracking with start/pause/resume/stop
- Real-time status updates via polling API
- Automatic session timeout after 8 hours

#### Rent Coordination
- Base rent: $1600/month
- Hourly credit: $50/hour worked (max 8 hours/month creditable)
- Excess hours roll over to next month
- Comprehensive event tracking system (payments, adjustments, manual entries)
- Rent calculation based on work logs with manual adjustments
- Audit logging for all rent events

#### Authentication System
- Email-based verification code authentication (6-digit codes, 10-minute expiration)
- Session management with 30-day cookie expiration
- Whitelist-based access control (robert@defore.st, lynz57@hotmail.com)
- All routes protected except `/login.html`, `/auth/*`, and `/health`
- Browser requests redirect to login page, API requests return 401 JSON
- Console logging in development, SMTP-ready for production

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

### Build Process
1. Compiles all server-side `.coffee` files to `dist/*.js`
2. Fixes import paths (`.coffee` → `.js`)
3. Compiles client-side CoffeeScript to JavaScript
4. Copies static assets and compiled JS to `dist/static/`
5. In watch mode: restarts server on changes

## Development Notes

- **Node.js Version**: Uses nvm with Node 24 LTS (`.nvmrc` file in repo root)
- **Client-side**: CoffeeScript is now pre-compiled to JavaScript for better reliability
- **Server-side**: CoffeeScript files run directly via coffee command (no compilation needed for server)
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
