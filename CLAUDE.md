# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RentCoordinator is a Deno-based tenant coordination application for tracking work hours, calculating rent credits, and managing reimbursements between Robert and Lyndzie. Built with CoffeeScript on both server and client sides.

## Development Commands

### Essential Commands
```bash
# Development (builds, watches files, runs server)
npm run dev
# or
deno task dev

# Build only (compiles CoffeeScript to dist/)
npm run build
# or
deno task build

# Start production server (requires prior build)
npm run start
# or
deno task start
```

### Build System
The build system (scripts/build.ts) compiles CoffeeScript files to JavaScript, handles import path rewriting (.coffee → .js), and copies static assets to dist/. Watch mode rebuilds on changes and restarts the server automatically.

## Technology Stack

- **Runtime**: Deno with TypeScript/CoffeeScript hybrid
- **Backend**: Express.js server with CoffeeScript source, compiled to JavaScript
- **Frontend**: Compiled JavaScript (from CoffeeScript) - no longer browser-compiled
- **Database**: Deno KV (key-value store), with schema designed for future SQLite migration
- **Build**: Custom TypeScript build script that compiles CoffeeScript

## Architecture

### Project Structure
```
lib/
├── config.coffee          - Environment config and constants
├── db/schema.coffee       - Database initialization and KV setup
├── middleware.coffee      - Express middleware setup
├── routing.coffee         - Main route definitions and timer API
├── services/             - Business logic layer
│   ├── timer.coffee      - Timer operations and session management
│   ├── rent.coffee       - Rent calculation logic
│   └── recurring_events.coffee - Recurring events processing
├── models/               - Data access layer
│   ├── work_session.coffee - Work session CRUD operations
│   ├── work_log.coffee   - Work log management
│   └── rent.coffee       - Rent periods, events, audit logs
└── routes/               - Route handlers
    ├── work.coffee       - Work management routes
    ├── rent.coffee       - Rent-related endpoints
    └── recurring_events.coffee - Recurring events API

static/                   - Frontend assets
├── coffee/               - Frontend CoffeeScript (source)
├── js/                   - Compiled JavaScript (served to browser)
├── css/                  - Stylesheets
└── *.html               - HTML pages (index, work, rent)
```

### Database Design
Uses Deno KV with keys like `['timer_state', worker]`, `['work_session', session_id]`, and `['rent_events', id]`. Schema includes projects, tasks, work_logs, timer_state, and rent tracking designed for eventual SQLite migration.

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

### Key Configuration
- Workers defined in `config.WORKERS` array
- Database path configurable via `DB_PATH` environment variable
- Default port 3000, configurable via `PORT` environment variable
- Timer polling interval: 1000ms client-side

### Build Process
1. Compiles all server-side `.coffee` files to `dist/*.js`
2. Fixes import paths (`.coffee` → `.js`)
3. Compiles client-side CoffeeScript to JavaScript
4. Copies static assets and compiled JS to `dist/static/`
5. In watch mode: restarts server on changes

## Development Notes

- **Client-side**: CoffeeScript is now pre-compiled to JavaScript for better reliability
- **Server-side**: All CoffeeScript must be compiled before running
- **Database**: Uses Deno KV (requires `--unstable-kv` flag)
- **Workers**: Hardcoded as ['robert', 'lyndzie'] in config
- **Frontend**: Loads compiled JavaScript, polls `/timer/status` every second for live updates
- **Hot Reload**: Available in dev mode with file watching
