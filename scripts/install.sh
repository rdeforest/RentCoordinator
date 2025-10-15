#!/bin/bash

set -e


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/init-manager.sh"


PREFIX="/opt/rentcoordinator"
APP_USER="rentcoordinator"
PORT="3000"
DB_PATH="/var/lib/rentcoordinator/db.kv"
LOG_DIR="/var/log/rentcoordinator"
SKIP_USER=false
REPO_URL="git@github.com:rdeforest/RentCoordinator.git"


show_help() {
    cat << EOF
RentCoordinator Installation Script

Usage: $0 [OPTIONS]

NOTE: Script will automatically request sudo when needed.
      Your SSH agent will be preserved for private git repositories.

Options:
    --prefix PATH      Installation directory (default: /opt/rentcoordinator)
    --user USER        Application user (default: rentcoordinator)
    --port PORT        Application port (default: 3000)
    --db-path PATH     Database path (default: /var/lib/rentcoordinator/db.kv)
    --skip-user        Skip user creation, use current user
    --help             Show this help message

Examples:
    $0                                    # Install with defaults
    $0 --prefix /usr/local --port 8080   # Custom directory and port
    $0 --skip-user                        # Install for current user
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
            --port)
                PORT="$2"
                shift 2
                ;;
            --db-path)
                DB_PATH="$2"
                shift 2
                ;;
            --skip-user)
                SKIP_USER=true
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

run_as_root() {
    if is_root; then
        "$@"
    else
        sudo "$@"
    fi
}

configure_sudo_for_ssh() {
    local sudoers_file="/etc/sudoers.d/ssh-agent-preserve"

    if [ -f "$sudoers_file" ]; then
        return 0
    fi

    print_info "Configuring sudo to preserve SSH agent..."

    local content='# Preserve SSH agent socket for git operations with SSH keys
Defaults env_keep += "SSH_AUTH_SOCK"'

    echo "$content" | run_as_root tee "$sudoers_file" > /dev/null
    run_as_root chmod 440 "$sudoers_file"

    print_success "Sudo configured to preserve SSH agent"
}


create_initial_directories() {
    print_info "Creating initial directories..."

    create_directory "$LOG_DIR" "$APP_USER:$APP_USER" || {
        print_error "Failed to create log directory"
        exit 1
    }

    create_directory "$(dirname "$DB_PATH")" "$APP_USER:$APP_USER" || {
        print_error "Failed to create database directory"
        exit 1
    }

    print_success "Initial directories created"
}

clone_repository() {
    print_info "Cloning repository..."

    require_command git "Git is required but not installed"

    if [ -d "$PREFIX/.git" ]; then
        print_warning "Repository already exists, pulling latest changes..."
        cd "$PREFIX" || exit 1
        git pull || {
            print_error "Failed to pull repository updates"
            exit 1
        }
    else
        git clone "$REPO_URL" "$PREFIX" || {
            print_error "Failed to clone repository from $REPO_URL"
            exit 1
        }
    fi

    set_ownership "$PREFIX" "$APP_USER:$APP_USER"

    # Verify
    if [ ! -d "$PREFIX/.git" ]; then
        print_error "Repository clone verification failed - .git directory not found"
        exit 1
    fi

    if [ ! -f "$PREFIX/deno.json" ]; then
        print_error "Repository verification failed - deno.json not found"
        exit 1
    fi

    print_success "Repository cloned and verified"
}

create_additional_directories() {
    print_info "Creating additional directories..."

    create_directory "$PREFIX/bin"
    create_directory "$PREFIX/scripts"
    create_directory "$PREFIX/dist"

    set_ownership "$PREFIX" "$APP_USER:$APP_USER"

    print_success "Additional directories created"
}

build_application() {
    print_info "Building application..."

    local deno_install=$(get_deno_install_path "$APP_USER")

    if [ "$(get_current_user)" = "$APP_USER" ]; then
        cd "$PREFIX" || exit 1
        export DENO_INSTALL="$deno_install"
        export PATH="$deno_install/bin:$PATH"
        deno task build || {
            print_error "Build failed"
            exit 1
        }
    else
        su "$APP_USER" -c "cd '$PREFIX' && export DENO_INSTALL='$deno_install' && export PATH=\$DENO_INSTALL/bin:\$PATH && deno task build" || {
            print_error "Build failed"
            exit 1
        }
    fi

    if [ ! -f "$PREFIX/dist/main.js" ]; then
        print_error "Build verification failed - dist/main.js not found"
        exit 1
    fi

    if [ ! -d "$PREFIX/dist/static" ]; then
        print_warning "dist/static directory not found - static assets may be missing"
    fi

    print_success "Application built and verified"
}

create_config() {
    print_info "Creating configuration..."

    cat > "$PREFIX/.env" << EOF
# RentCoordinator Configuration
# Generated by install script on $(date)

# Server Configuration
PORT=$PORT
HOST=0.0.0.0

# Database Configuration
DB_PATH=$DB_PATH

# Logging
LOG_LEVEL=info
LOG_DIR=$LOG_DIR

# Environment
NODE_ENV=production
EOF

    set_ownership "$PREFIX/.env" "$APP_USER:$APP_USER"
    print_success "Configuration created at $PREFIX/.env"
}

create_management_script() {
    print_info "Creating management script..."

    cp "$SCRIPT_DIR/lib/rentcoordinator.template" "$PREFIX/bin/rentcoordinator"

    sed -i "s|PREFIX_PLACEHOLDER|$PREFIX|g" "$PREFIX/bin/rentcoordinator"
    sed -i "s|LOG_DIR_PLACEHOLDER|$LOG_DIR|g" "$PREFIX/bin/rentcoordinator"
    sed -i "s|USER_PLACEHOLDER|$APP_USER|g" "$PREFIX/bin/rentcoordinator"

    chmod +x "$PREFIX/bin/rentcoordinator"

    if is_root; then
        ln -sf "$PREFIX/bin/rentcoordinator" /usr/local/bin/rentcoordinator
        print_info "Created symlink in /usr/local/bin"
    fi

    print_success "Management script created"
}

create_service_config() {
    local config_file="$SCRIPT_DIR/lib/.rentcoordinator-service.conf"

    cat > "$config_file" << EOF
#!/bin/bash
# RentCoordinator Service Configuration
# Generated by install script on $(date)

export PREFIX="$PREFIX"
export APP_USER="$APP_USER"
export PORT="$PORT"
export DB_PATH="$DB_PATH"
export LOG_DIR="$LOG_DIR"
export USER_HOME="$(get_user_home "$APP_USER")"
export DENO_INSTALL="\$USER_HOME/.deno"

source "$SCRIPT_DIR/lib/rentcoordinator-service.conf.sh"
EOF

    echo "$config_file"
}

show_summary() {
    echo
    print_success "Installation completed successfully!"
    echo
    echo "Installation Summary:"
    echo "  • Installed to: $PREFIX"
    echo "  • User: $APP_USER"
    echo "  • Port: $PORT"
    echo "  • Database: $DB_PATH"
    echo "  • Logs: $LOG_DIR"
    echo
    echo "Next steps:"
    echo "1. Start the application: $PREFIX/bin/rentcoordinator start"
    echo "2. Check status: $PREFIX/bin/rentcoordinator status"
    echo "3. View logs: $PREFIX/bin/rentcoordinator logs"
    echo
}


main() {
    echo "===================================="
    echo " RentCoordinator Installation Script"
    echo "===================================="
    echo

    parse_arguments "$@"

    configure_sudo_for_ssh

    detect_os
    print_info "Detected OS: $OS (family: ${OS_FAMILY:-none})"

    if [ "$SKIP_USER" = true ]; then
        APP_USER=$(get_current_user)
        print_info "Using current user: $APP_USER"
    else
        create_user "$APP_USER" || exit 1
    fi

    create_initial_directories
    install_deno "$APP_USER" || exit 1
    clone_repository
    create_additional_directories
    build_application
    create_config
    create_management_script

    local service_config=$(create_service_config)
    install_init_service "$service_config"

    show_summary
}

main "$@"
