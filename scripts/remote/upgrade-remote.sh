#!/bin/bash
# scripts/remote/upgrade-remote.sh
# Runs ON the remote server to upgrade existing installation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/init-manager.sh"

# Configuration
SERVICE_NAME="rent-coordinator"
SERVICE_USER="$SERVICE_NAME"
DEPLOY_TMP="$HOME/rent-coordinator-deploy"
INSTALL_DIR="$HOME/rent-coordinator"

print_info "================================================"
print_info "RentCoordinator Upgrade (Remote)"
print_info "================================================"

# Check if installation exists
if [ ! -d "$INSTALL_DIR/dist" ]; then
    print_error "No installation found at $INSTALL_DIR"
    print_info "Use install-remote.sh for first-time installation"
    exit 1
fi

# Verify deployment package exists
if [ ! -d "$DEPLOY_TMP/dist" ]; then
    print_error "Deployment package not found at $DEPLOY_TMP"
    exit 1
fi

# Read current deployment info
if [ -f "$INSTALL_DIR/.deployed" ]; then
    source "$INSTALL_DIR/.deployed"
    print_info "Current version: ${VERSION:-unknown}"
    print_info "Installed: ${INSTALLED:-unknown}"
fi

# Backup database
print_info "Backing up database..."
BACKUP_DIR="$INSTALL_DIR/backups"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/backup-$(date +%Y-%m-%d_%H-%M-%S).json"

if [ -f "$INSTALL_DIR/tenant-coordinator.db" ]; then
    # Source config to get DENO_INSTALL path
    if [ -f "$INSTALL_DIR/config.sh" ]; then
        source "$INSTALL_DIR/config.sh"
    fi

    DENO_PATH=$(get_deno_install_path "$SERVICE_USER")/bin/deno

    # Create backup using Deno task if available
    if [ -f "$INSTALL_DIR/dist/scripts/backup.ts" ]; then
        cd "$INSTALL_DIR"
        sudo -u "$SERVICE_USER" "$DENO_PATH" run --allow-read --allow-env --unstable-kv \
            dist/scripts/backup.ts > "$BACKUP_FILE" 2>/dev/null || {
            print_warning "Backup script failed, but continuing..."
        }
        if [ -s "$BACKUP_FILE" ]; then
            print_success "Database backed up to $BACKUP_FILE"
        else
            rm -f "$BACKUP_FILE"
            print_warning "Backup file empty, skipping"
        fi
    else
        print_warning "Backup script not found, skipping database backup"
    fi
else
    print_warning "No database file found, skipping backup"
fi

# Stop service
print_info "Stopping service..."
INIT_SYSTEM=$(detect_init_system)
case "$INIT_SYSTEM" in
    systemd)
        if run_as_root systemctl is-active --quiet $SERVICE_NAME; then
            run_as_root systemctl stop $SERVICE_NAME || {
                print_error "Failed to stop service"
                exit 1
            }
            print_success "Service stopped"
        else
            print_info "Service was not running"
        fi
        ;;
    openrc)
        run_as_root rc-service $SERVICE_NAME stop || {
            print_error "Failed to stop service"
            exit 1
        }
        print_success "Service stopped"
        ;;
    sysvinit)
        run_as_root /etc/init.d/$SERVICE_NAME stop || {
            print_error "Failed to stop service"
            exit 1
        }
        print_success "Service stopped"
        ;;
esac

# Deploy new version to dist.new
print_info "Deploying new version..."
sudo -u "$SERVICE_USER" rm -rf "$INSTALL_DIR/dist.new"
sudo -u "$SERVICE_USER" cp -r "$DEPLOY_TMP/dist" "$INSTALL_DIR/dist.new" || {
    print_error "Failed to copy new distribution"
    print_info "Restarting old version..."
    case "$INIT_SYSTEM" in
        systemd) run_as_root systemctl start $SERVICE_NAME ;;
        openrc) run_as_root rc-service $SERVICE_NAME start ;;
        sysvinit) run_as_root /etc/init.d/$SERVICE_NAME start ;;
    esac
    exit 1
}

# Also copy deno.json and package.json if they exist
if [ -f "$DEPLOY_TMP/deno.json" ]; then
    sudo -u "$SERVICE_USER" cp "$DEPLOY_TMP/deno.json" "$INSTALL_DIR/" 2>/dev/null || true
fi
if [ -f "$DEPLOY_TMP/package.json" ]; then
    sudo -u "$SERVICE_USER" cp "$DEPLOY_TMP/package.json" "$INSTALL_DIR/" 2>/dev/null || true
fi

# Atomic swap: dist -> dist.old, dist.new -> dist
print_info "Swapping to new version..."
sudo -u "$SERVICE_USER" rm -rf "$INSTALL_DIR/dist.old"
sudo -u "$SERVICE_USER" mv "$INSTALL_DIR/dist" "$INSTALL_DIR/dist.old" || {
    print_error "Failed to backup old version"
    sudo -u "$SERVICE_USER" rm -rf "$INSTALL_DIR/dist.new"
    exit 1
}

sudo -u "$SERVICE_USER" mv "$INSTALL_DIR/dist.new" "$INSTALL_DIR/dist" || {
    print_error "Failed to activate new version"
    print_info "Rolling back..."
    sudo -u "$SERVICE_USER" mv "$INSTALL_DIR/dist.old" "$INSTALL_DIR/dist"
    exit 1
}

# Update deployment metadata
sudo -u "$SERVICE_USER" tee "$INSTALL_DIR/.deployed" > /dev/null <<EOF
INSTALLED=$(date -Iseconds)
VERSION=$(cd "$DEPLOY_TMP" && git rev-parse HEAD 2>/dev/null || echo "unknown")
UPGRADED_BY=$USER
PREVIOUS_VERSION=${VERSION:-unknown}
EOF

# Start service
print_info "Starting service..."
case "$INIT_SYSTEM" in
    systemd)
        run_as_root systemctl start $SERVICE_NAME || {
            print_error "Failed to start service with new version"
            print_info "Rolling back..."
            rm -rf "$INSTALL_DIR/dist"
            mv "$INSTALL_DIR/dist.old" "$INSTALL_DIR/dist"
            run_as_root systemctl start $SERVICE_NAME
            exit 1
        }
        ;;
    openrc)
        run_as_root rc-service $SERVICE_NAME start || {
            print_error "Failed to start service with new version"
            print_info "Rolling back..."
            rm -rf "$INSTALL_DIR/dist"
            mv "$INSTALL_DIR/dist.old" "$INSTALL_DIR/dist"
            run_as_root rc-service $SERVICE_NAME start
            exit 1
        }
        ;;
    sysvinit)
        run_as_root /etc/init.d/$SERVICE_NAME start || {
            print_error "Failed to start service with new version"
            print_info "Rolling back..."
            rm -rf "$INSTALL_DIR/dist"
            mv "$INSTALL_DIR/dist.old" "$INSTALL_DIR/dist"
            run_as_root /etc/init.d/$SERVICE_NAME start
            exit 1
        }
        ;;
esac

# Health check
print_info "Running health check..."
PORT=$(grep "^PORT=" "$INSTALL_DIR/config.sh" | cut -d= -f2 || echo "8080")
PORT=$(echo $PORT | tr -d '"' | tr -d "'")

# Wait for service to start (retry up to 10 times with 2 second intervals)
RETRY_COUNT=0
MAX_RETRIES=10
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    sleep 2
    if curl -sf "http://localhost:$PORT/health" > /dev/null 2>&1; then
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
done

if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
    print_success "Health check passed"
    print_info "Cleaning up old version..."
    sudo -u "$SERVICE_USER" rm -rf "$INSTALL_DIR/dist.old"
    print_success "Old version removed"
else
    print_error "Health check failed!"
    print_warning "Rolling back to previous version..."

    # Stop failed service
    case "$INIT_SYSTEM" in
        systemd) run_as_root systemctl stop $SERVICE_NAME ;;
        openrc) run_as_root rc-service $SERVICE_NAME stop ;;
        sysvinit) run_as_root /etc/init.d/$SERVICE_NAME stop ;;
    esac

    # Rollback
    sudo -u "$SERVICE_USER" rm -rf "$INSTALL_DIR/dist"
    sudo -u "$SERVICE_USER" mv "$INSTALL_DIR/dist.old" "$INSTALL_DIR/dist"

    # Start old version
    case "$INIT_SYSTEM" in
        systemd) run_as_root systemctl start $SERVICE_NAME ;;
        openrc) run_as_root rc-service $SERVICE_NAME start ;;
        sysvinit) run_as_root /etc/init.d/$SERVICE_NAME start ;;
    esac

    print_error "Rollback complete - running previous version"
    print_info "Check logs for errors: journalctl -u $SERVICE_NAME -n 50"
    exit 1
fi

print_success "================================================"
print_success "Upgrade complete!"
print_success "================================================"
print_info ""
print_info "Previous version: ${VERSION:-unknown}"
print_info "Current version: $(cd "$DEPLOY_TMP" && git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
    print_info "Backup: $BACKUP_FILE"
fi
print_info ""
print_info "Service status: sudo systemctl status $SERVICE_NAME"
print_info "View logs: sudo journalctl -u $SERVICE_NAME -f"
