#!/bin/bash
# scripts/remote/install-remote.sh
# Runs ON the remote server to perform initial installation

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
print_info "RentCoordinator Installation (Remote)"
print_info "================================================"
print_info "Install directory: $INSTALL_DIR"
print_info "Service name: $SERVICE_NAME"
print_info "Service user: $SERVICE_USER"
print_info ""

# Check if already installed
if [ -d "$INSTALL_DIR/dist" ]; then
    print_error "Installation already exists at $INSTALL_DIR"
    print_info "Use upgrade-remote.sh to update existing installation"
    exit 1
fi

# Verify deployment package exists
if [ ! -d "$DEPLOY_TMP/dist" ]; then
    print_error "Deployment package not found at $DEPLOY_TMP"
    print_info "Did you push the package from the dev machine?"
    exit 1
fi

# Create service user if it doesn't exist
print_info "Setting up service user..."
if ! user_exists "$SERVICE_USER"; then
    create_user "$SERVICE_USER" || exit 1
else
    print_success "Service user already exists"
fi

# Install Deno for service user
install_deno "$SERVICE_USER" || exit 1

# Create installation directory
print_info "Creating installation directory..."
create_directory "$INSTALL_DIR" "$USER" || exit 1

# Copy distribution files
print_info "Installing application files..."
cp -r "$DEPLOY_TMP/dist" "$INSTALL_DIR/" || {
    print_error "Failed to copy distribution files"
    exit 1
}

# Copy Deno configuration files
cp "$DEPLOY_TMP/deno.json" "$INSTALL_DIR/" 2>/dev/null || true
cp "$DEPLOY_TMP/package.json" "$INSTALL_DIR/" 2>/dev/null || true

# Create subdirectories
mkdir -p "$INSTALL_DIR/backups"
mkdir -p "$INSTALL_DIR/logs"
mkdir -p "$INSTALL_DIR/node_modules"

# Create default config if it doesn't exist
if [ ! -f "$INSTALL_DIR/config.sh" ]; then
    print_info "Creating default configuration..."
    # Generate a random session secret
    SESSION_SECRET=$(openssl rand -hex 32)
    # Get the actual Deno install path for the service user
    DENO_INSTALL_PATH=$(get_deno_install_path "$SERVICE_USER")

    # Note: systemd's EnvironmentFile doesn't support "export" keyword
    # Use simple KEY=VALUE format
    cat > "$INSTALL_DIR/config.sh" <<EOF
# RentCoordinator Configuration
# Note: This file is loaded by systemd - use KEY=VALUE format (no export)

# Server configuration
PORT=8080
NODE_ENV=production

# Database
DB_PATH=$INSTALL_DIR/tenant-coordinator.db

# Authentication
SESSION_SECRET=$SESSION_SECRET

# SMTP Configuration (required for email verification codes)
# Uncomment and configure when ready to go live:
# SMTP_HOST=smtp.example.com
# SMTP_PORT=587
# SMTP_USER=your-smtp-username
# SMTP_PASS=your-smtp-password
# EMAIL_FROM=noreply@thatsnice.org

# Deno configuration (set by install script)
DENO_INSTALL=$DENO_INSTALL_PATH
PATH=$DENO_INSTALL_PATH/bin:/usr/local/bin:/usr/bin:/bin
EOF
    print_success "Configuration created at $INSTALL_DIR/config.sh"
    print_success "Generated random SESSION_SECRET"
    print_warning "IMPORTANT: Configure SMTP settings when ready to go live"
else
    print_success "Using existing configuration"
fi

# Create deployment metadata
cat > "$INSTALL_DIR/.deployed" <<EOF
INSTALLED=$(date -Iseconds)
VERSION=$(cd "$DEPLOY_TMP" && git rev-parse HEAD 2>/dev/null || echo "unknown")
INSTALLED_BY=$USER
EOF

# Fix ownership - the service user needs to be able to write to this directory
print_info "Setting ownership to $SERVICE_USER..."
run_as_root chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR" || {
    print_error "Failed to set ownership"
    exit 1
}
print_success "Ownership set to $SERVICE_USER"

# Create service configuration for init-manager
DENO_INSTALL_PATH=$(get_deno_install_path "$SERVICE_USER")
cat > /tmp/rent-coordinator-service-config.sh <<EOF
SERVICE_NAME=$SERVICE_NAME
APP_USER=$SERVICE_USER
PREFIX=$INSTALL_DIR
DENO_INSTALL=$DENO_INSTALL_PATH
LOG_DIR=$INSTALL_DIR/logs
SERVICE_DESCRIPTION="RentCoordinator - Tenant work tracking and rent coordination"
SERVICE_DOCUMENTATION=""
DB_PATH=$INSTALL_DIR/tenant-coordinator.db
EOF

# Install and start service
print_info "Installing service..."
install_init_service /tmp/rent-coordinator-service-config.sh || {
    print_error "Failed to install service"
    exit 1
}

# Start service
print_info "Starting service..."
case $(detect_init_system) in
    systemd)
        run_as_root systemctl daemon-reload
        run_as_root systemctl enable $SERVICE_NAME
        run_as_root systemctl start $SERVICE_NAME
        sleep 3
        if run_as_root systemctl is-active --quiet $SERVICE_NAME; then
            print_success "Service started successfully"
        else
            print_error "Service failed to start"
            run_as_root systemctl status $SERVICE_NAME --no-pager || true
            exit 1
        fi
        ;;
    openrc)
        run_as_root rc-update add $SERVICE_NAME default
        run_as_root rc-service $SERVICE_NAME start
        sleep 3
        if run_as_root rc-service $SERVICE_NAME status | grep -q "started"; then
            print_success "Service started successfully"
        else
            print_error "Service failed to start"
            exit 1
        fi
        ;;
    sysvinit)
        run_as_root /etc/init.d/$SERVICE_NAME start
        sleep 3
        print_warning "Please verify service is running manually"
        ;;
esac

# Health check
print_info "Running health check..."
sleep 2
PORT=$(grep "^export PORT=" "$INSTALL_DIR/config.sh" | cut -d= -f2 || echo "8080")
if curl -sf "http://localhost:$PORT/health" > /dev/null 2>&1; then
    print_success "Health check passed"
else
    print_warning "Health check failed (service may still be starting)"
fi

# Cleanup
rm -f /tmp/rent-coordinator-service-config.sh

print_success "================================================"
print_success "Installation complete!"
print_success "================================================"
print_info ""
print_info "Installation directory: $INSTALL_DIR"
print_info "Configuration: $INSTALL_DIR/config.sh"
print_info "Database: $INSTALL_DIR/tenant-coordinator.db"
print_info "Logs: journalctl -u $SERVICE_NAME -f (systemd)"
print_info ""
print_info "Next steps:"
print_info "1. Edit $INSTALL_DIR/config.sh"
print_info "2. Set a secure SESSION_SECRET"
print_info "3. Configure SMTP settings when ready"
print_info "4. Restart service after config changes"
print_info ""
print_info "Service commands:"
print_info "  Status:  sudo systemctl status $SERVICE_NAME"
print_info "  Stop:    sudo systemctl stop $SERVICE_NAME"
print_info "  Start:   sudo systemctl start $SERVICE_NAME"
print_info "  Restart: sudo systemctl restart $SERVICE_NAME"
print_info "  Logs:    sudo journalctl -u $SERVICE_NAME -f"
