# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Core Development Tasks
- `deno task build` - Compile CoffeeScript to JavaScript in dist/
- `deno task dev` - Build and run with file watching, hot reload
- `deno task start` - Run production build from dist/

### Build System
The build system (scripts/build.ts) compiles CoffeeScript files to JavaScript, handles import path rewriting (.coffee → .js), and copies static assets to dist/. Watch mode rebuilds on changes and restarts the server automatically.

## Architecture Overview

### Technology Stack
- **Runtime**: Deno with TypeScript/CoffeeScript hybrid
- **Backend**: Express.js server with CoffeeScript source
- **Frontend**: Vanilla JavaScript/CoffeeScript with in-browser compilation
- **Database**: Deno KV (key-value store), with schema designed for future SQLite migration
- **Build**: Custom TypeScript build script that compiles CoffeeScript

### Project Structure
```
lib/
├── config.coffee          - Environment config and constants
├── db/schema.coffee       - Database initialization and KV setup
├── middleware.coffee      - Express middleware setup
├── routing.coffee         - Main route definitions and timer API
├── services/             - Business logic layer
│   ├── timer.coffee      - Timer operations and session management
│   └── rent.coffee       - Rent calculation logic
├── models/               - Data access layer
│   ├── work_session.coffee - Work session CRUD operations
│   ├── work_log.coffee   - Work log management
│   └── rent.coffee       - Rent calculation models
└── routes/               - Route handlers
    ├── work.coffee       - Work management routes
    └── rent.coffee       - Rent-related endpoints

static/                   - Frontend assets
├── coffee/               - Frontend CoffeeScript (browser-compiled)
├── css/                  - Stylesheets
└── *.html               - HTML pages (index, work, rent)
```

### Database Design
Uses Deno KV with keys like `['timer_state', worker]` and `['work_session', session_id]`. Schema includes projects, tasks, work_logs, and timer_state tables designed for eventual SQLite migration.

### Core Domains

#### Timer System
- Multi-worker support (robert, lyndzie)
- Session-based work tracking with start/pause/resume/stop
- Real-time status updates via polling API
- Automatic session timeout after 8 hours

#### Rent Coordination
- Base rent: $1600/month
- Hourly credit: $50/hour worked
- Max monthly hours: 8 (excess rolls over)
- Rent calculation based on work logs

### Key Configuration
- Workers defined in `config.WORKERS` array
- Database path configurable via `DB_PATH` environment variable
- Default port 3000, configurable via `PORT` environment variable
- Timer polling interval: 1000ms client-side

### Development Notes
- CoffeeScript used throughout for consistency with user preferences
- Frontend uses in-browser CoffeeScript compilation
- Build system handles import path rewriting for ES modules
- Static assets copied to dist/ during build
- Hot reload available in dev mode with file watching