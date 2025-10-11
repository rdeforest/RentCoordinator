#!/bin/bash

# RentCoordinator Automated Uninstall Script
# Safely removes RentCoordinator installation

set -e

# Default values (should match install defaults)
PREFIX="/opt/rentcoordinator"
APP_USER="rentcoordinator"
DB_PATH="/var/lib/rentcoordinator/db.kv"
LOG_DIR="/var/log/rentcoordinator"

# Uninstall options
KEEP_DATA=false
KEEP_LOGS=false
KEEP_USER=false
FORCE=false
DRY_RUN=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_dry_run() { echo -e "${BLUE}[DRY RUN]${NC} $1"; }

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        --user)
            APP_USER="$2"
            shift 2
            ;;
        --db-path)
            DB_PATH="$2"
            shift 2
            ;;
        --keep-data)
            KEEP_DATA=true
            shift
            ;;
        --keep-logs)
            KEEP_LOGS=true
            shift
            ;;
        --keep-user)
            KEEP_USER=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            cat << EOF
RentCoordinator Uninstall Script

Usage: $0 [OPTIONS]

Options:
    --prefix PATH      Installation directory (default: /opt/rentcoordinator)
    --user USER        Application user (default: rentcoordinator)
    --db-path PATH     Database path (default: /var/lib/rentcoordinator/db.kv)
    --keep-data        Keep database files
    --keep-logs        Keep log files
    --keep-user        Don't remove application user
    --force            Skip confirmation prompt
    --dry-run          Show what would be removed without removing
    --help             Show this help message

Examples:
    $0                                # Uninstall with confirmation
    $0 --force                        # Uninstall without confirmation
    $0 --keep-data --keep-logs        # Remove app but keep data and logs
    $0 --dry-run                      # Preview what would be removed
EOF
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Detect init system
detect_init_system() {
    if [ -d /run/systemd/system ]; then
        echo "systemd"
    elif [ -f /sbin/openrc ]; then
        echo "openrc"
    elif [ -d /etc/init.d ]; then
        echo "sysvinit"
    elif [ -d /etc/sv ]; then
        echo "runit"
    elif [ -d /etc/init ]; then
        echo "upstart"
    else
        echo "unknown"
    fi
}

# Stop the application
stop_application() {
    print_info "Stopping RentCoordinator..."

    # Try management script first
    if [ -x "$PREFIX/bin/rentcoordinator" ]; then
        if [ "$DRY_RUN" = true ]; then
            print_dry_run "Would run: $PREFIX/bin/rentcoordinator stop"
        else
            "$PREFIX/bin/rentcoordinator" stop 2>/dev/null || print_warning "Management script stop failed or not running"
        fi
    fi

    # Check for PID file in PREFIX
    if [ -f "$PREFIX/rentcoordinator.pid" ]; then
        PID=$(cat "$PREFIX/rentcoordinator.pid")
        if kill -0 "$PID" 2>/dev/null; then
            if [ "$DRY_RUN" = true ]; then
                print_dry_run "Would kill process $PID"
            else
                print_info "Stopping process $PID..."
                kill "$PID" 2>/dev/null || true
                sleep 2
                kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null || true
            fi
        fi
    fi

    # Check for PID file in /var/run (legacy location)
    if [ -f "/var/run/rentcoordinator.pid" ]; then
        PID=$(cat "/var/run/rentcoordinator.pid")
        if kill -0 "$PID" 2>/dev/null; then
            if [ "$DRY_RUN" = true ]; then
                print_dry_run "Would kill process $PID"
            else
                print_info "Stopping process $PID..."
                kill "$PID" 2>/dev/null || true
                sleep 2
                kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null || true
            fi
        fi
    fi

    # Fallback: find and kill any running deno processes running main.js
    RUNNING_PIDS=$(pgrep -f "deno.*rentcoordinator.*main.js" 2>/dev/null || true)
    if [ -n "$RUNNING_PIDS" ]; then
        if [ "$DRY_RUN" = true ]; then
            print_dry_run "Would kill processes: $RUNNING_PIDS"
        else
            print_info "Stopping processes: $RUNNING_PIDS"
            kill $RUNNING_PIDS 2>/dev/null || true
            sleep 2
            pkill -9 -f "deno.*rentcoordinator.*main.js" 2>/dev/null || true
        fi
    fi

    print_success "Application stopped"
}

# Remove systemd service
remove_systemd_service() {
    if [ ! -f "/etc/systemd/system/rentcoordinator.service" ]; then
        return 0
    fi

    print_info "Removing systemd service..."

    if [ "$DRY_RUN" = true ]; then
        print_dry_run "Would stop and disable systemd service"
        print_dry_run "Would remove /etc/systemd/system/rentcoordinator.service"
        return 0
    fi

    # Stop and disable service
    systemctl stop rentcoordinator 2>/dev/null || true
    systemctl disable rentcoordinator 2>/dev/null || true

    # Remove service file
    rm -f /etc/systemd/system/rentcoordinator.service

    # Reload systemd
    systemctl daemon-reload 2>/dev/null || true

    print_success "Systemd service removed"
}

# Remove OpenRC service
remove_openrc_service() {
    if [ ! -f "/etc/init.d/rentcoordinator" ]; then
        return 0
    fi

    print_info "Removing OpenRC service..."

    if [ "$DRY_RUN" = true ]; then
        print_dry_run "Would stop OpenRC service"
        print_dry_run "Would remove from runlevels"
        print_dry_run "Would remove /etc/init.d/rentcoordinator"
        return 0
    fi

    # Stop service
    rc-service rentcoordinator stop 2>/dev/null || true

    # Remove from runlevels
    rc-update del rentcoordinator 2>/dev/null || true

    # Remove init script
    rm -f /etc/init.d/rentcoordinator

    print_success "OpenRC service removed"
}

# Remove init system service
remove_init_service() {
    INIT_SYSTEM=$(detect_init_system)

    case $INIT_SYSTEM in
        systemd)
            remove_systemd_service
            ;;
        openrc)
            remove_openrc_service
            ;;
        *)
            print_info "No known init system service to remove"
            ;;
    esac
}

# Remove application files
remove_application() {
    print_info "Removing application files..."

    # Remove symlink
    if [ -L "/usr/local/bin/rentcoordinator" ]; then
        if [ "$DRY_RUN" = true ]; then
            print_dry_run "Would remove /usr/local/bin/rentcoordinator"
        else
            rm -f /usr/local/bin/rentcoordinator
            print_success "Removed symlink from /usr/local/bin"
        fi
    fi

    # Remove installation directory
    if [ -d "$PREFIX" ]; then
        if [ "$DRY_RUN" = true ]; then
            print_dry_run "Would remove directory: $PREFIX"
            du -sh "$PREFIX" 2>/dev/null | awk '{print "  Size: " $1}'
        else
            rm -rf "$PREFIX"
            print_success "Removed installation directory: $PREFIX"
        fi
    else
        print_info "Installation directory not found: $PREFIX"
    fi
}

# Remove data files
remove_data() {
    if [ "$KEEP_DATA" = true ]; then
        print_info "Keeping database files (--keep-data specified)"
        return 0
    fi

    print_info "Removing database files..."

    DB_DIR=$(dirname "$DB_PATH")
    if [ -d "$DB_DIR" ]; then
        if [ "$DRY_RUN" = true ]; then
            print_dry_run "Would remove directory: $DB_DIR"
            du -sh "$DB_DIR" 2>/dev/null | awk '{print "  Size: " $1}'
        else
            rm -rf "$DB_DIR"
            print_success "Removed database directory: $DB_DIR"
        fi
    else
        print_info "Database directory not found: $DB_DIR"
    fi
}

# Remove log files
remove_logs() {
    if [ "$KEEP_LOGS" = true ]; then
        print_info "Keeping log files (--keep-logs specified)"
        return 0
    fi

    print_info "Removing log files..."

    if [ -d "$LOG_DIR" ]; then
        if [ "$DRY_RUN" = true ]; then
            print_dry_run "Would remove directory: $LOG_DIR"
            du -sh "$LOG_DIR" 2>/dev/null | awk '{print "  Size: " $1}'
        else
            rm -rf "$LOG_DIR"
            print_success "Removed log directory: $LOG_DIR"
        fi
    else
        print_info "Log directory not found: $LOG_DIR"
    fi
}

# Remove user
remove_user() {
    if [ "$KEEP_USER" = true ]; then
        print_info "Keeping user account (--keep-user specified)"
        return 0
    fi

    # Don't remove if user doesn't exist
    if ! id "$APP_USER" &>/dev/null; then
        print_info "User $APP_USER does not exist"
        return 0
    fi

    # Don't remove current user
    if [ "$(whoami)" = "$APP_USER" ]; then
        print_warning "Cannot remove current user, skipping user removal"
        return 0
    fi

    print_info "Removing user: $APP_USER"

    if [ "$DRY_RUN" = true ]; then
        print_dry_run "Would remove user: $APP_USER"
        return 0
    fi

    # Try userdel first
    if command -v userdel &>/dev/null; then
        userdel -r "$APP_USER" 2>/dev/null || userdel "$APP_USER" 2>/dev/null || true
        print_success "User removed: $APP_USER"
    elif command -v deluser &>/dev/null; then
        deluser --remove-home "$APP_USER" 2>/dev/null || deluser "$APP_USER" 2>/dev/null || true
        print_success "User removed: $APP_USER"
    else
        print_warning "Cannot remove user: no userdel or deluser command found"
    fi
}

# Show what will be removed
show_removal_plan() {
    echo
    echo "========================================"
    echo " RentCoordinator Uninstall Plan"
    echo "========================================"
    echo
    echo "The following will be removed:"
    echo

    [ -d "$PREFIX" ] && echo "  • Application: $PREFIX"
    [ -L "/usr/local/bin/rentcoordinator" ] && echo "  • Symlink: /usr/local/bin/rentcoordinator"
    [ -f "/etc/systemd/system/rentcoordinator.service" ] && echo "  • Systemd service: /etc/systemd/system/rentcoordinator.service"
    [ -f "/etc/init.d/rentcoordinator" ] && echo "  • OpenRC service: /etc/init.d/rentcoordinator"

    if [ "$KEEP_DATA" = false ] && [ -d "$(dirname "$DB_PATH")" ]; then
        echo "  • Database: $(dirname "$DB_PATH")"
    fi

    if [ "$KEEP_LOGS" = false ] && [ -d "$LOG_DIR" ]; then
        echo "  • Logs: $LOG_DIR"
    fi

    if [ "$KEEP_USER" = false ] && id "$APP_USER" &>/dev/null; then
        echo "  • User: $APP_USER"
    fi

    echo
    echo "The following will be kept:"
    echo

    if [ "$KEEP_DATA" = true ]; then
        echo "  • Database: $(dirname "$DB_PATH") (--keep-data)"
    fi

    if [ "$KEEP_LOGS" = true ]; then
        echo "  • Logs: $LOG_DIR (--keep-logs)"
    fi

    if [ "$KEEP_USER" = true ]; then
        echo "  • User: $APP_USER (--keep-user)"
    fi

    echo
}

# Confirm uninstall
confirm_uninstall() {
    if [ "$FORCE" = true ]; then
        return 0
    fi

    read -p "Do you want to continue? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Uninstall cancelled"
        exit 0
    fi
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        if [ "$DRY_RUN" = true ]; then
            print_warning "Not running as root - some operations may fail in actual run"
            return 0
        fi

        # Check if we need root
        NEEDS_ROOT=false
        [ -d "$PREFIX" ] && [ ! -w "$PREFIX" ] && NEEDS_ROOT=true
        [ -f "/etc/systemd/system/rentcoordinator.service" ] && NEEDS_ROOT=true
        [ -f "/etc/init.d/rentcoordinator" ] && NEEDS_ROOT=true
        [ "$KEEP_USER" = false ] && id "$APP_USER" &>/dev/null && NEEDS_ROOT=true

        if [ "$NEEDS_ROOT" = true ]; then
            print_error "This script must be run as root for the current configuration"
            print_info "Try: sudo $0"
            exit 1
        fi
    fi
}

# Main uninstall process
main() {
    echo "========================================"
    echo " RentCoordinator Uninstall Script"
    echo "========================================"
    echo

    if [ "$DRY_RUN" = true ]; then
        print_info "DRY RUN MODE - No changes will be made"
        echo
    fi

    check_root
    show_removal_plan
    confirm_uninstall

    echo
    print_info "Starting uninstall..."
    echo

    stop_application
    remove_init_service
    remove_application
    remove_data
    remove_logs
    remove_user

    echo
    if [ "$DRY_RUN" = true ]; then
        print_info "Dry run completed - no changes were made"
    else
        print_success "Uninstall completed successfully!"
    fi
    echo
}

# Run main uninstall
main
