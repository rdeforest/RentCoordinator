#!/bin/bash

# RentCoordinator Automated Installation Script
# Supports multiple Linux distributions and init systems

set -e

# Default values
PREFIX="/opt/rentcoordinator"
APP_USER="rentcoordinator"
PORT="3000"
DB_PATH="/var/lib/rentcoordinator/db.kv"
LOG_DIR="/var/log/rentcoordinator"
SKIP_USER=false
REPO_URL="https://github.com/rdeforest/RentCoordinator.git"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "  $1"; }

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
            cat << EOF
RentCoordinator Installation Script

Usage: $0 [OPTIONS]

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
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        OS_FAMILY=$ID_LIKE
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        OS_FAMILY="rhel fedora"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        OS_FAMILY="debian"
    else
        OS=$(uname -s)
        OS_FAMILY=""
    fi

    print_info "Detected OS: $OS (family: ${OS_FAMILY:-none})"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        if [ "$SKIP_USER" = false ]; then
            print_error "This script must be run as root for user creation"
            print_info "Use --skip-user to install for current user, or run with sudo"
            exit 1
        fi
    fi
}

# Create application user
create_user() {
    if [ "$SKIP_USER" = true ]; then
        APP_USER=$(whoami)
        print_info "Using current user: $APP_USER"
        return
    fi

    if id "$APP_USER" &>/dev/null; then
        print_warning "User $APP_USER already exists"
    else
        print_info "Creating user: $APP_USER"
        if command -v useradd &>/dev/null; then
            useradd -m -s /bin/bash "$APP_USER"
        elif command -v adduser &>/dev/null; then
            adduser --disabled-password --gecos "" "$APP_USER"
        else
            print_error "Cannot create user: no useradd or adduser command found"
            exit 1
        fi
        print_success "User created: $APP_USER"
    fi
}

# Create initial directories (before git clone)
create_initial_directories() {
    print_info "Creating initial directories..."

    # Create non-PREFIX directories only
    mkdir -p "$LOG_DIR"
    mkdir -p "$(dirname "$DB_PATH")"

    # Set ownership
    if [ "$SKIP_USER" = false ] && [ "$EUID" -eq 0 ]; then
        chown -R "$APP_USER:$APP_USER" "$LOG_DIR"
        chown -R "$APP_USER:$APP_USER" "$(dirname "$DB_PATH")"
    fi

    print_success "Initial directories created"
}

# Create additional directories (after git clone)
create_additional_directories() {
    print_info "Creating additional directories..."

    # Create subdirectories if they don't exist
    mkdir -p "$PREFIX/bin"
    mkdir -p "$PREFIX/scripts"
    mkdir -p "$PREFIX/dist"

    # Set ownership
    if [ "$SKIP_USER" = false ] && [ "$EUID" -eq 0 ]; then
        chown -R "$APP_USER:$APP_USER" "$PREFIX"
    fi

    print_success "Additional directories created"
}

# Install Deno
install_deno() {
    print_info "Installing Deno..."

    # Determine Deno install location and user home directory
    if [ "$SKIP_USER" = true ] || [ "$EUID" -ne 0 ]; then
        USER_HOME="$HOME"
        DENO_INSTALL="$HOME/.deno"
    else
        # Get actual home directory from passwd, not hardcoded /home
        USER_HOME=$(eval echo ~"$APP_USER")
        DENO_INSTALL="$USER_HOME/.deno"
    fi

    # Check if Deno is already installed
    if [ -f "$DENO_INSTALL/bin/deno" ]; then
        print_warning "Deno already installed at $DENO_INSTALL"
        # Verify it works
        if "$DENO_INSTALL/bin/deno" --version &>/dev/null; then
            print_success "Deno verified working"
            return
        else
            print_warning "Deno exists but not working, reinstalling..."
        fi
    fi

    # Download and install Deno
    # Note: Deno installer may try to access /dev/tty and fail, but still successfully install
    # So we allow non-zero exit and verify installation afterward
    if command -v curl &>/dev/null; then
        if [ "$SKIP_USER" = true ] || [ "$EUID" -ne 0 ]; then
            curl -fsSL https://deno.land/install.sh | sh < /dev/null || true
        else
            su - "$APP_USER" -c "curl -fsSL https://deno.land/install.sh | sh < /dev/null" || true
        fi
    elif command -v wget &>/dev/null; then
        if [ "$SKIP_USER" = true ] || [ "$EUID" -ne 0 ]; then
            wget -qO- https://deno.land/install.sh | sh < /dev/null || true
        else
            su - "$APP_USER" -c "wget -qO- https://deno.land/install.sh | sh < /dev/null" || true
        fi
    else
        print_error "Neither curl nor wget found. Please install one of them."
        exit 1
    fi

    # Verify installation succeeded
    if [ ! -f "$DENO_INSTALL/bin/deno" ]; then
        print_error "Deno installation failed - binary not found at $DENO_INSTALL/bin/deno"
        exit 1
    fi

    # Test that Deno actually runs
    if ! "$DENO_INSTALL/bin/deno" --version &>/dev/null; then
        print_error "Deno installed but does not execute properly"
        exit 1
    fi

    # Add to PATH in user's profile
    if [ "$SKIP_USER" = false ] && [ "$EUID" -eq 0 ]; then
        echo "export DENO_INSTALL=\"$DENO_INSTALL\"" >> "$USER_HOME/.bashrc"
        echo "export PATH=\"\$DENO_INSTALL/bin:\$PATH\"" >> "$USER_HOME/.bashrc"
    fi

    print_success "Deno installed and verified at $DENO_INSTALL"
}

# Clone repository
clone_repository() {
    print_info "Cloning repository..."

    # Check if git is available
    if ! command -v git &>/dev/null; then
        print_error "Git is not installed. Please install git first."
        exit 1
    fi

    if [ -d "$PREFIX/.git" ]; then
        print_warning "Repository already exists, pulling latest changes..."
        if [ "$SKIP_USER" = true ] || [ "$EUID" -ne 0 ]; then
            cd "$PREFIX" || exit 1
            git pull || {
                print_error "Failed to pull repository updates"
                exit 1
            }
        else
            su "$APP_USER" -c "cd '$PREFIX' && git pull" || {
                print_error "Failed to pull repository updates"
                exit 1
            }
        fi
    else
        # Clone the repository
        if [ "$SKIP_USER" = true ] || [ "$EUID" -ne 0 ]; then
            git clone "$REPO_URL" "$PREFIX" || {
                print_error "Failed to clone repository from $REPO_URL"
                exit 1
            }
        else
            # Create parent directory with correct ownership if needed
            PARENT_DIR=$(dirname "$PREFIX")
            if [ ! -d "$PARENT_DIR" ]; then
                mkdir -p "$PARENT_DIR"
            fi

            su "$APP_USER" -c "git clone '$REPO_URL' '$PREFIX'" || {
                print_error "Failed to clone repository from $REPO_URL"
                exit 1
            }
        fi
    fi

    # Verify the repository was cloned/updated successfully
    if [ ! -d "$PREFIX/.git" ]; then
        print_error "Repository clone verification failed - .git directory not found"
        exit 1
    fi

    # Verify essential files exist
    if [ ! -f "$PREFIX/deno.json" ]; then
        print_error "Repository verification failed - deno.json not found"
        exit 1
    fi

    print_success "Repository cloned and verified"
}

# Build application
build_application() {
    print_info "Building application..."

    # Determine paths
    if [ "$SKIP_USER" = true ] || [ "$EUID" -ne 0 ]; then
        USER_HOME="$HOME"
        DENO_INSTALL="$HOME/.deno"
    else
        USER_HOME=$(eval echo ~"$APP_USER")
        DENO_INSTALL="$USER_HOME/.deno"
    fi

    # Ensure dist directory exists
    mkdir -p "$PREFIX/dist"

    # Build the application
    if [ "$SKIP_USER" = true ] || [ "$EUID" -ne 0 ]; then
        cd "$PREFIX" || exit 1
        export DENO_INSTALL="$DENO_INSTALL"
        export PATH="$DENO_INSTALL/bin:$PATH"
        deno task build || {
            print_error "Build failed"
            exit 1
        }
    else
        su "$APP_USER" -c "cd '$PREFIX' && export DENO_INSTALL='$DENO_INSTALL' && export PATH=\$DENO_INSTALL/bin:\$PATH && deno task build" || {
            print_error "Build failed"
            exit 1
        }
    fi

    # Verify build output exists
    if [ ! -f "$PREFIX/dist/main.js" ]; then
        print_error "Build verification failed - dist/main.js not found"
        print_info "Build may have completed but output is missing"
        exit 1
    fi

    # Check if dist has other expected files
    if [ ! -d "$PREFIX/dist/static" ]; then
        print_warning "dist/static directory not found - static assets may be missing"
    fi

    print_success "Application built and verified"
}

# Create configuration file
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

    # Set ownership
    if [ "$SKIP_USER" = false ] && [ "$EUID" -eq 0 ]; then
        chown "$APP_USER:$APP_USER" "$PREFIX/.env"
    fi

    print_success "Configuration created at $PREFIX/.env"
}

# Create management script
create_management_script() {
    print_info "Creating management script..."

    cat > "$PREFIX/bin/rentcoordinator" << 'EOF'
#!/bin/bash

# RentCoordinator Management Script
APP_DIR="PREFIX_PLACEHOLDER"
PID_FILE="PREFIX_PLACEHOLDER/rentcoordinator.pid"
LOG_FILE="LOG_DIR_PLACEHOLDER/app.log"
USER="USER_PLACEHOLDER"
USER_HOME=$(eval echo ~"$USER")
DENO_INSTALL="$USER_HOME/.deno"

# Source environment if exists
if [ -f "$APP_DIR/.env" ]; then
    set -a
    . "$APP_DIR/.env"
    set +a
fi

start() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "RentCoordinator is already running (PID: $(cat $PID_FILE))"
        return 1
    fi

    echo "Starting RentCoordinator..."
    cd "$APP_DIR" || exit 1

    if [ "$(whoami)" = "$USER" ]; then
        export PATH="$DENO_INSTALL/bin:$PATH"
        nohup deno run --allow-read --allow-write --allow-env --allow-net --unstable-kv dist/main.js > "$LOG_FILE" 2>&1 &
        echo $! > "$PID_FILE"
    else
        # Run as the application user and capture PID
        PID=$(su "$USER" -c "cd '$APP_DIR' && export PATH='$DENO_INSTALL/bin:\$PATH' && nohup deno run --allow-read --allow-write --allow-env --allow-net --unstable-kv dist/main.js > '$LOG_FILE' 2>&1 & echo \$!")
        echo "$PID" > "$PID_FILE"
    fi

    sleep 2
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "RentCoordinator started successfully (PID: $(cat $PID_FILE))"
    else
        echo "Failed to start RentCoordinator"
        rm -f "$PID_FILE"
        return 1
    fi
}

stop() {
    if [ ! -f "$PID_FILE" ]; then
        echo "RentCoordinator is not running"
        return 1
    fi

    echo "Stopping RentCoordinator..."
    kill $(cat "$PID_FILE") 2>/dev/null
    rm -f "$PID_FILE"
    echo "RentCoordinator stopped"
}

restart() {
    stop
    sleep 2
    start
}

status() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "RentCoordinator is running (PID: $(cat $PID_FILE))"
    else
        echo "RentCoordinator is not running"
        [ -f "$PID_FILE" ] && rm -f "$PID_FILE"
    fi
}

logs() {
    tail -f "$LOG_FILE"
}

case "$1" in
    start)   start ;;
    stop)    stop ;;
    restart) restart ;;
    status)  status ;;
    logs)    logs ;;
    *)       echo "Usage: $0 {start|stop|restart|status|logs}" ;;
esac
EOF

    # Replace placeholders
    sed -i "s|PREFIX_PLACEHOLDER|$PREFIX|g" "$PREFIX/bin/rentcoordinator"
    sed -i "s|LOG_DIR_PLACEHOLDER|$LOG_DIR|g" "$PREFIX/bin/rentcoordinator"
    sed -i "s|USER_PLACEHOLDER|$APP_USER|g" "$PREFIX/bin/rentcoordinator"

    chmod +x "$PREFIX/bin/rentcoordinator"

    # Create symlink in /usr/local/bin if running as root
    if [ "$EUID" -eq 0 ]; then
        ln -sf "$PREFIX/bin/rentcoordinator" /usr/local/bin/rentcoordinator
        print_info "Created symlink in /usr/local/bin"
    fi

    print_success "Management script created"
}

# Detect and suggest init system
suggest_init_system() {
    print_info "Detecting init system..."

    if [ -d /run/systemd/system ]; then
        INIT_SYSTEM="systemd"
    elif [ -f /sbin/openrc ]; then
        INIT_SYSTEM="openrc"
    elif [ -d /etc/init.d ]; then
        INIT_SYSTEM="sysvinit"
    elif [ -d /etc/sv ]; then
        INIT_SYSTEM="runit"
    elif [ -d /etc/init ]; then
        INIT_SYSTEM="upstart"
    else
        INIT_SYSTEM="unknown"
    fi

    print_info "Detected init system: $INIT_SYSTEM"

    case $INIT_SYSTEM in
        systemd)
            cat << EOF

To configure auto-start with systemd:
1. Review the systemd guide: $PREFIX/docs/init-systems/systemd.md
2. Copy the service file: sudo cp $PREFIX/docs/init-systems/systemd.service /etc/systemd/system/rentcoordinator.service
3. Enable the service: sudo systemctl enable rentcoordinator
4. Start the service: sudo systemctl start rentcoordinator
EOF
            ;;
        openrc)
            cat << EOF

To configure auto-start with OpenRC:
1. Review the OpenRC guide: $PREFIX/docs/init-systems/openrc.md
2. Copy the init script: sudo cp $PREFIX/docs/init-systems/openrc.init /etc/init.d/rentcoordinator
3. Add to default runlevel: sudo rc-update add rentcoordinator default
4. Start the service: sudo rc-service rentcoordinator start
EOF
            ;;
        *)
            cat << EOF

For auto-start configuration, see:
$PREFIX/docs/init-systems/

Available guides for various init systems and process managers.
EOF
            ;;
    esac
}

# Main installation process
main() {
    echo "===================================="
    echo " RentCoordinator Installation Script"
    echo "===================================="
    echo

    detect_os
    check_root
    create_user
    create_initial_directories
    install_deno
    clone_repository
    create_additional_directories
    build_application
    create_config
    create_management_script

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

    suggest_init_system

    echo
    echo "For more information, see: $PREFIX/docs/DEPLOYMENT.md"
}

# Run main installation
main