#!/bin/bash

set -e


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/init-manager.sh"


# Default values (should match install defaults)
PREFIX="/opt/rentcoordinator"
APP_USER="rentcoordinator"
DB_PATH="/var/lib/rentcoordinator/db.kv"
LOG_DIR="/var/log/rentcoordinator"

KEEP_DATA=false
KEEP_LOGS=false
KEEP_USER=false
FORCE=false
DRY_RUN=false


show_help() {
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
}

parse_arguments() {
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
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}


stop_application() {
    print_info "Stopping RentCoordinator..."

    if [ -x "$PREFIX/bin/rentcoordinator" ]; then
        if [ "$DRY_RUN" = true ]; then
            print_dry_run "Would run: $PREFIX/bin/rentcoordinator stop"
        else
            "$PREFIX/bin/rentcoordinator" stop 2>/dev/null || print_warning "Management script stop failed or not running"
        fi
    fi

    local pid_file="$PREFIX/rentcoordinator.pid"
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if process_running "$pid"; then
            if [ "$DRY_RUN" = true ]; then
                print_dry_run "Would kill process $pid"
            else
                stop_process "$pid"
            fi
        fi
    fi

    if [ "$DRY_RUN" = true ]; then
        local pids=$(find_processes "deno.*rentcoordinator.*main.js")
        if [ -n "$pids" ]; then
            print_dry_run "Would kill processes: $pids"
        fi
    else
        stop_processes_matching "deno.*rentcoordinator.*main.js"
    fi

    print_success "Application stopped"
}

remove_application() {
    print_info "Removing application files..."

    if [ -L "/usr/local/bin/rentcoordinator" ]; then
        if [ "$DRY_RUN" = true ]; then
            print_dry_run "Would remove /usr/local/bin/rentcoordinator"
        else
            rm -f /usr/local/bin/rentcoordinator
            print_success "Removed symlink from /usr/local/bin"
        fi
    fi

    if [ -d "$PREFIX" ]; then
        safe_remove "$PREFIX" "$DRY_RUN"
        if [ "$DRY_RUN" != true ]; then
            print_success "Removed installation directory: $PREFIX"
        fi
    else
        print_info "Installation directory not found: $PREFIX"
    fi
}

remove_data_files() {
    if [ "$KEEP_DATA" = true ]; then
        print_info "Keeping database files (--keep-data specified)"
        return 0
    fi

    print_info "Removing database files..."

    local db_dir=$(dirname "$DB_PATH")
    if [ -d "$db_dir" ]; then
        safe_remove "$db_dir" "$DRY_RUN"
        if [ "$DRY_RUN" != true ]; then
            print_success "Removed database directory: $db_dir"
        fi
    else
        print_info "Database directory not found: $db_dir"
    fi
}

remove_log_files() {
    if [ "$KEEP_LOGS" = true ]; then
        print_info "Keeping log files (--keep-logs specified)"
        return 0
    fi

    print_info "Removing log files..."

    if [ -d "$LOG_DIR" ]; then
        safe_remove "$LOG_DIR" "$DRY_RUN"
        if [ "$DRY_RUN" != true ]; then
            print_success "Removed log directory: $LOG_DIR"
        fi
    else
        print_info "Log directory not found: $LOG_DIR"
    fi
}

# Show what will be removed
create_service_config() {
    local config_file="$SCRIPT_DIR/lib/.rentcoordinator-service.conf"

    local user_home=""
    if user_exists "$APP_USER"; then
        user_home=$(get_user_home "$APP_USER")
    else
        user_home="/var/lib/$APP_USER"
    fi

    cat > "$config_file" << EOF
#!/bin/bash
# RentCoordinator Service Configuration

export PREFIX="$PREFIX"
export APP_USER="$APP_USER"
export PORT="${PORT:-3000}"
export DB_PATH="$DB_PATH"
export LOG_DIR="$LOG_DIR"
export USER_HOME="$user_home"
export DENO_INSTALL="\$USER_HOME/.deno"

source "$SCRIPT_DIR/lib/rentcoordinator-service.conf.sh"
EOF

    echo "$config_file"
}

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

    local init_system=$(detect_init_system)
    if [ "$init_system" != "none" ]; then
        echo "  • $init_system service"
    fi

    if [ "$KEEP_DATA" = false ] && [ -d "$(dirname "$DB_PATH")" ]; then
        echo "  • Database: $(dirname "$DB_PATH")"
    fi

    if [ "$KEEP_LOGS" = false ] && [ -d "$LOG_DIR" ]; then
        echo "  • Logs: $LOG_DIR"
    fi

    if [ "$KEEP_USER" = false ] && user_exists "$APP_USER"; then
        echo "  • User: $APP_USER"
    fi

    echo
    echo "The following will be kept:"
    echo

    [ "$KEEP_DATA" = true ] && echo "  • Database: $(dirname "$DB_PATH") (--keep-data)"
    [ "$KEEP_LOGS" = true ] && echo "  • Logs: $LOG_DIR (--keep-logs)"
    [ "$KEEP_USER" = true ] && echo "  • User: $APP_USER (--keep-user)"

    echo
}


main() {
    echo "========================================"
    echo " RentCoordinator Uninstall Script"
    echo "========================================"
    echo

    parse_arguments "$@"

    if [ "$DRY_RUN" = true ]; then
        print_info "DRY RUN MODE - No changes will be made"
        echo
    fi

    local needs_root=false
    [ -d "$PREFIX" ] && [ ! -w "$PREFIX" ] && needs_root=true
    [ "$KEEP_USER" = false ] && user_exists "$APP_USER" && needs_root=true

    if [ "$needs_root" = true ] && ! is_root; then
        if [ "$DRY_RUN" = true ]; then
            print_warning "Not running as root - some operations may fail in actual run"
        else
            check_root "This uninstallation" || exit 1
        fi
    fi

    show_removal_plan
    confirm "Do you want to continue?" "$FORCE" || {
        echo "Uninstall cancelled"
        exit 0
    }

    echo
    print_info "Starting uninstall..."
    echo

    stop_application

    local service_config=$(create_service_config)
    if [ "$DRY_RUN" != true ]; then
        uninstall_init_service "$service_config"
    else
        print_dry_run "Would uninstall init system service"
    fi

    remove_application
    remove_data_files
    remove_log_files

    if [ "$KEEP_USER" = false ]; then
        if [ "$DRY_RUN" = true ]; then
            if user_exists "$APP_USER"; then
                print_dry_run "Would remove user: $APP_USER"
            fi
        else
            remove_user "$APP_USER"
        fi
    else
        print_info "Keeping user account (--keep-user specified)"
    fi

    echo
    if [ "$DRY_RUN" = true ]; then
        print_info "Dry run completed - no changes were made"
    else
        print_success "Uninstall completed successfully!"
    fi
    echo
}

main "$@"
