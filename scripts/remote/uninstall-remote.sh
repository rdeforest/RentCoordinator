#!/bin/bash
# scripts/remote/uninstall-remote.sh
# Runs ON the remote server to completely remove installation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/init-manager.sh"

# Configuration
SERVICE_NAME="rent-coordinator"
SERVICE_USER="$SERVICE_NAME"
INSTALL_DIR="$HOME/rent-coordinator"

print_warning "================================================"
print_warning "RentCoordinator Uninstallation (Remote)"
print_warning "================================================"
print_warning "This will completely remove RentCoordinator"
print_warning "Installation directory: $INSTALL_DIR"
print_warning ""

# Check if installation exists
if [ ! -d "$INSTALL_DIR" ]; then
    print_info "No installation found at $INSTALL_DIR"
    exit 0
fi

# Confirm if not forced
if [ "$1" != "--force" ]; then
    print_warning "This will DELETE:"
    print_warning "  - Application files"
    print_warning "  - System service"
    print_warning "  - Service user: $SERVICE_USER"
    print_warning ""
    print_info "Database and backups will be preserved unless you manually delete:"
    print_info "  $INSTALL_DIR/tenant-coordinator.db"
    print_info "  $INSTALL_DIR/backups/"
    print_warning ""

    if ! confirm "Proceed with uninstallation?"; then
        print_info "Uninstallation cancelled"
        exit 0
    fi
fi

# Stop and remove service
INIT_SYSTEM=$(detect_init_system)
if [ "$INIT_SYSTEM" != "none" ]; then
    print_info "Stopping and removing service..."

    case "$INIT_SYSTEM" in
        systemd)
            if run_as_root systemctl is-active --quiet $SERVICE_NAME 2>/dev/null; then
                run_as_root systemctl stop $SERVICE_NAME || true
            fi
            run_as_root systemctl disable $SERVICE_NAME 2>/dev/null || true
            run_as_root rm -f /etc/systemd/system/$SERVICE_NAME.service
            run_as_root systemctl daemon-reload
            ;;
        openrc)
            run_as_root rc-service $SERVICE_NAME stop 2>/dev/null || true
            run_as_root rc-update del $SERVICE_NAME default 2>/dev/null || true
            run_as_root rm -f /etc/init.d/$SERVICE_NAME
            ;;
        sysvinit)
            run_as_root /etc/init.d/$SERVICE_NAME stop 2>/dev/null || true
            run_as_root rm -f /etc/init.d/$SERVICE_NAME
            run_as_root update-rc.d $SERVICE_NAME remove 2>/dev/null || true
            ;;
    esac

    print_success "Service removed"
fi

# Remove application files (but preserve database and backups)
print_info "Removing application files..."
rm -rf "$INSTALL_DIR/dist"
rm -rf "$INSTALL_DIR/dist.old"
rm -rf "$INSTALL_DIR/dist.new"
rm -rf "$INSTALL_DIR/logs"
rm -f "$INSTALL_DIR/config.sh"
rm -f "$INSTALL_DIR/.deployed"
print_success "Application files removed"

# Check if database and backups remain
DB_EXISTS=false
BACKUPS_EXIST=false

if [ -f "$INSTALL_DIR/tenant-coordinator.db" ]; then
    DB_EXISTS=true
fi

if [ -d "$INSTALL_DIR/backups" ] && [ -n "$(ls -A "$INSTALL_DIR/backups" 2>/dev/null)" ]; then
    BACKUPS_EXIST=true
fi

# If only database/backups remain, inform user
if [ "$DB_EXISTS" = "true" ] || [ "$BACKUPS_EXIST" = "true" ]; then
    print_info ""
    print_info "Database and backups preserved at:"
    [ "$DB_EXISTS" = "true" ] && print_info "  $INSTALL_DIR/tenant-coordinator.db"
    [ "$BACKUPS_EXIST" = "true" ] && print_info "  $INSTALL_DIR/backups/"
    print_info ""
    print_info "To completely remove all data, run:"
    print_info "  rm -rf $INSTALL_DIR"
else
    # Nothing left, remove directory
    if [ -d "$INSTALL_DIR" ]; then
        rmdir "$INSTALL_DIR" 2>/dev/null || true
    fi
fi

# Remove service user
if user_exists "$SERVICE_USER"; then
    print_info "Removing service user: $SERVICE_USER"

    # Check if user has running processes
    if pgrep -u "$SERVICE_USER" >/dev/null 2>&1; then
        print_warning "User $SERVICE_USER has running processes, stopping them..."
        run_as_root pkill -u "$SERVICE_USER" || true
        sleep 2
    fi

    remove_user "$SERVICE_USER" || {
        print_warning "Could not remove user $SERVICE_USER (may have active processes)"
    }
fi

print_success "================================================"
print_success "Uninstallation complete!"
print_success "================================================"

if [ "$DB_EXISTS" = "true" ] || [ "$BACKUPS_EXIST" = "true" ]; then
    print_info ""
    print_info "Data preserved in $INSTALL_DIR"
    print_info "To reinstall with existing data, run install.sh again"
fi
