#!/bin/bash


readonly SERVICE_NAME="rentcoordinator"
readonly INIT_SCRIPT="/etc/init.d/${SERVICE_NAME}"

# ============================================================================
# INTERFACE FUNCTIONS
# ============================================================================

openrc_is_available() {
    [ -f /sbin/openrc-run ] || [ -f /sbin/openrc ]
}

openrc_install_service() {
    local prefix="$1"
    local user="$2"
    local log_dir="$3"
    local db_path="$4"
    local port="$5"

    local user_home=$(get_user_home "$user")
    local deno_install="$user_home/.deno"
    local pid_file="$prefix/rentcoordinator.pid"

    print_info "Installing OpenRC service..."

    # Create init script
    cat > "$INIT_SCRIPT" << 'EOF'
#!/sbin/openrc-run

# RentCoordinator OpenRC init script

name="RentCoordinator"
description="Tenant coordination and rent tracking application"

# These will be replaced by sed
PREFIX="PREFIX_PLACEHOLDER"
USER="USER_PLACEHOLDER"
LOG_DIR="LOG_DIR_PLACEHOLDER"
DB_PATH="DB_PATH_PLACEHOLDER"
PORT="PORT_PLACEHOLDER"

USER_HOME=$(eval echo ~"$USER")
DENO_INSTALL="$USER_HOME/.deno"
pidfile="$PREFIX/rentcoordinator.pid"
command="$DENO_INSTALL/bin/deno"
command_args="run --allow-read --allow-write --allow-env --allow-net --unstable-kv $PREFIX/dist/main.js"
command_user="$USER"
command_background=true
directory="$PREFIX"

# Environment variables
export DENO_INSTALL="$DENO_INSTALL"
export PATH="$DENO_INSTALL/bin:$PATH"
export PORT="$PORT"
export DB_PATH="$DB_PATH"
export LOG_DIR="$LOG_DIR"
export NODE_ENV="production"

# Output redirection
output_log="$LOG_DIR/app.log"
error_log="$LOG_DIR/app.log"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath --directory --owner "$USER:$USER" --mode 0755 "$LOG_DIR"
    checkpath --directory --owner "$USER:$USER" --mode 0755 "$(dirname "$DB_PATH")"
}

stop_post() {
    rm -f "$pidfile"
}
EOF

    # Replace placeholders
    sed -i "s|PREFIX_PLACEHOLDER|$prefix|g" "$INIT_SCRIPT"
    sed -i "s|USER_PLACEHOLDER|$user|g" "$INIT_SCRIPT"
    sed -i "s|LOG_DIR_PLACEHOLDER|$log_dir|g" "$INIT_SCRIPT"
    sed -i "s|DB_PATH_PLACEHOLDER|$db_path|g" "$INIT_SCRIPT"
    sed -i "s|PORT_PLACEHOLDER|$port|g" "$INIT_SCRIPT"

    # Make executable
    chmod +x "$INIT_SCRIPT"

    print_success "OpenRC service installed"
    print_info "To add to default runlevel: sudo rc-update add $SERVICE_NAME default"
    print_info "To start now: sudo rc-service $SERVICE_NAME start"
    return 0
}

openrc_uninstall_service() {
    print_info "Uninstalling OpenRC service..."

    # Stop if running
    openrc_stop_service

    # Remove from all runlevels
    rc-update del "$SERVICE_NAME" 2>/dev/null || true

    # Remove init script
    if [ -f "$INIT_SCRIPT" ]; then
        rm -f "$INIT_SCRIPT"
    fi

    print_success "OpenRC service uninstalled"
    return 0
}

openrc_start_service() {
    print_info "Starting $SERVICE_NAME service..."

    if ! rc-service "$SERVICE_NAME" start; then
        print_error "Failed to start service"
        return 1
    fi

    print_success "Service started"
    return 0
}

openrc_stop_service() {
    if ! rc-service "$SERVICE_NAME" status &>/dev/null; then
        return 0
    fi

    print_info "Stopping $SERVICE_NAME service..."
    rc-service "$SERVICE_NAME" stop 2>/dev/null || true
    return 0
}

openrc_get_service_status() {
    rc-service "$SERVICE_NAME" status &>/dev/null
}

openrc_enable_service() {
    print_info "Adding $SERVICE_NAME to default runlevel..."

    if ! rc-update add "$SERVICE_NAME" default; then
        print_error "Failed to add service to default runlevel"
        return 1
    fi

    print_success "Service added to default runlevel"
    return 0
}

openrc_disable_service() {
    rc-update del "$SERVICE_NAME" default 2>/dev/null || true
    return 0
}

openrc_show_logs() {
    local lines="${1:-50}"
    local log_dir=$(grep "LOG_DIR=" "$INIT_SCRIPT" 2>/dev/null | cut -d'"' -f2)
    if [ -f "$log_dir/app.log" ]; then
        tail -n "$lines" "$log_dir/app.log"
    else
        print_warning "Log file not found"
    fi
}

openrc_follow_logs() {
    local log_dir=$(grep "LOG_DIR=" "$INIT_SCRIPT" 2>/dev/null | cut -d'"' -f2)
    if [ -f "$log_dir/app.log" ]; then
        tail -f "$log_dir/app.log"
    else
        print_warning "Log file not found"
    fi
}
