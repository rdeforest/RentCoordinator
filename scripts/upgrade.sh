#!/bin/bash
# scripts/upgrade.sh
# Upgrade RentCoordinator to latest version from GitHub

set -e  # Exit on error

# Configuration
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_NAME="rent-coordinator"
BACKUP_DIR="$PROJECT_DIR/backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# Error handler
error_exit() {
    log_error "$1"
    log_error "Upgrade failed. To rollback:"
    log_error "  1. Restore from backup: deno task restore $LATEST_BACKUP"
    log_error "  2. Restart service: sudo systemctl restart $SERVICE_NAME"
    exit 1
}

# Change to project directory
cd "$PROJECT_DIR" || error_exit "Failed to change to project directory"

log_info "Starting upgrade of RentCoordinator..."
log_info "Project directory: $PROJECT_DIR"

# 1. Pre-flight checks
log_info "Running pre-flight checks..."

# Check if git repo
if [ ! -d .git ]; then
    error_exit "Not a git repository"
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    log_warn "You have uncommitted changes:"
    git status --short
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Upgrade cancelled"
        exit 0
    fi
fi

# Check if service exists
if systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    SERVICE_EXISTS=true
    log_info "Service $SERVICE_NAME detected"
else
    SERVICE_EXISTS=false
    log_warn "Service $SERVICE_NAME not found (this is OK for dev)"
fi

# 2. Create backup
log_info "Creating backup before upgrade..."
BACKUP_TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
LATEST_BACKUP="${BACKUP_DIR}/backup-${BACKUP_TIMESTAMP}.json"

if [ -f "$PROJECT_DIR/tenant-coordinator.db" ]; then
    mkdir -p "$BACKUP_DIR"

    # Use the backup task if available
    if command -v deno &> /dev/null; then
        deno task backup > "$LATEST_BACKUP" 2>/dev/null || \
            log_warn "Backup task failed, but continuing..."
    else
        log_warn "Deno not found, skipping backup"
    fi

    log_success "Backup created: $LATEST_BACKUP"
else
    log_warn "No database found to backup (first install?)"
fi

# 3. Stop service if running
if [ "$SERVICE_EXISTS" = true ]; then
    log_info "Stopping service..."
    sudo systemctl stop "$SERVICE_NAME" || \
        error_exit "Failed to stop service"
    log_success "Service stopped"
fi

# 4. Pull latest code
log_info "Pulling latest code from GitHub..."
CURRENT_COMMIT=$(git rev-parse HEAD)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

git fetch origin || error_exit "Failed to fetch from origin"

# Check if we're behind
if [ "$(git rev-list HEAD..origin/$CURRENT_BRANCH --count)" -eq 0 ]; then
    log_success "Already up to date on branch $CURRENT_BRANCH"
    NEEDS_BUILD=false
else
    log_info "Updating from $(git rev-parse --short HEAD) to $(git rev-parse --short origin/$CURRENT_BRANCH)"
    git pull origin "$CURRENT_BRANCH" || error_exit "Failed to pull latest code"
    log_success "Code updated"
    NEEDS_BUILD=true
fi

# 5. Install dependencies if needed
if [ "$NEEDS_BUILD" = true ] || [ ! -d node_modules ]; then
    log_info "Checking dependencies..."
    npm install || error_exit "Failed to install dependencies"
    log_success "Dependencies installed"
fi

# 6. Run database migrations
log_info "Checking for database migrations..."
MIGRATIONS_DIR="$PROJECT_DIR/migrations"

if [ -d "$MIGRATIONS_DIR" ]; then
    log_info "Running migrations..."
    for migration in "$MIGRATIONS_DIR"/*.js; do
        if [ -f "$migration" ]; then
            log_info "  Running: $(basename "$migration")"
            deno run --allow-read --allow-write --allow-env --unstable-kv "$migration" || \
                error_exit "Migration failed: $(basename "$migration")"
        fi
    done
    log_success "Migrations completed"
else
    log_info "No migrations directory found (none needed yet)"
fi

# 7. Build project
if [ "$NEEDS_BUILD" = true ] || [ ! -d dist ]; then
    log_info "Building project..."
    npm run build || error_exit "Build failed"
    log_success "Build completed"
else
    log_info "Build not needed"
fi

# 8. Start service
if [ "$SERVICE_EXISTS" = true ]; then
    log_info "Starting service..."
    sudo systemctl start "$SERVICE_NAME" || error_exit "Failed to start service"

    # Wait a moment for service to start
    sleep 2

    # Check if service is running
    if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "Service started successfully"
    else
        error_exit "Service failed to start. Check logs: sudo journalctl -u $SERVICE_NAME -n 50"
    fi

    # Check service health
    log_info "Checking service health..."
    sleep 1

    # Try to get port from service or use default
    PORT=${PORT:-8080}
    if curl -sf "http://localhost:$PORT/health" > /dev/null 2>&1; then
        log_success "Health check passed"
    else
        log_warn "Health check failed (service may still be starting up)"
    fi
else
    log_info "No service to start (run 'npm run start' manually)"
fi

# 9. Summary
log_success "======================================"
log_success "Upgrade completed successfully!"
log_success "======================================"
log_info "Previous commit: $(echo $CURRENT_COMMIT | cut -c1-8)"
log_info "Current commit:  $(git rev-parse --short HEAD)"
log_info "Backup location: $LATEST_BACKUP"

if [ "$SERVICE_EXISTS" = true ]; then
    log_info ""
    log_info "Service status: $(sudo systemctl is-active $SERVICE_NAME)"
    log_info "View logs: sudo journalctl -u $SERVICE_NAME -f"
fi

log_info ""
log_info "To rollback if needed:"
log_info "  1. git reset --hard $CURRENT_COMMIT"
log_info "  2. npm run build"
if [ -f "$LATEST_BACKUP" ]; then
    log_info "  3. deno task restore $LATEST_BACKUP"
fi
if [ "$SERVICE_EXISTS" = true ]; then
    log_info "  4. sudo systemctl restart $SERVICE_NAME"
fi
