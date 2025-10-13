#!/bin/bash


readonly SERVICE_NAME="rentcoordinator"
readonly SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# ============================================================================
# INTERFACE FUNCTIONS
# ============================================================================

systemd_is_available() {
    [ -d /run/systemd/system ]
}

systemd_install_service() {
    local prefix="$1"
    local user="$2"
    local log_dir="$3"
    local db_path="$4"
    local port="$5"

    local user_home=$(get_user_home "$user")
    local deno_install="$user_home/.deno"

    print_info "Installing systemd service..."

    # Create service file
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=RentCoordinator - Tenant coordination and rent tracking
After=network.target
Documentation=https://github.com/rdeforest/RentCoordinator

[Service]
Type=simple
User=$user
WorkingDirectory=$prefix
Environment="DENO_INSTALL=$deno_install"
Environment="PATH=$deno_install/bin:/usr/local/bin:/usr/bin:/bin"
Environment="PORT=$port"
Environment="DB_PATH=$db_path"
Environment="LOG_DIR=$log_dir"
Environment="NODE_ENV=production"
ExecStart=$deno_install/bin/deno run --allow-read --allow-write --allow-env --allow-net --unstable-kv $prefix/dist/main.js
Restart=on-failure
RestartSec=10
StandardOutput=append:$log_dir/app.log
StandardError=append:$log_dir/app.log

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$log_dir $db_path $(dirname "$db_path")

[Install]
WantedBy=multi-user.target
EOF

    if [ $? -ne 0 ]; then
        print_error "Failed to create service file"
        return 1
    fi

    # Set permissions
    chmod 644 "$SERVICE_FILE"

    # Reload systemd
    systemctl daemon-reload || {
        print_error "Failed to reload systemd"
        return 1
    }

    print_success "Systemd service installed"
    print_info "To enable on boot: sudo systemctl enable $SERVICE_NAME"
    print_info "To start now: sudo systemctl start $SERVICE_NAME"
    return 0
}

systemd_uninstall_service() {
    print_info "Uninstalling systemd service..."

    # Stop if running
    systemd_stop_service

    # Disable if enabled
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true

    # Remove service file
    if [ -f "$SERVICE_FILE" ]; then
        rm -f "$SERVICE_FILE"
    fi

    # Reload systemd
    systemctl daemon-reload 2>/dev/null || true

    print_success "Systemd service uninstalled"
    return 0
}

systemd_start_service() {
    print_info "Starting $SERVICE_NAME service..."

    if ! systemctl start "$SERVICE_NAME"; then
        print_error "Failed to start service"
        print_info "Check logs: sudo journalctl -u $SERVICE_NAME -n 50"
        return 1
    fi

    print_success "Service started"
    return 0
}

systemd_stop_service() {
    if ! systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        return 0
    fi

    print_info "Stopping $SERVICE_NAME service..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    return 0
}

systemd_get_service_status() {
    if ! systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        return 1
    fi
    return 0
}

systemd_enable_service() {
    print_info "Enabling $SERVICE_NAME to start on boot..."

    if ! systemctl enable "$SERVICE_NAME"; then
        print_error "Failed to enable service"
        return 1
    fi

    print_success "Service enabled"
    return 0
}

systemd_disable_service() {
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    return 0
}

systemd_show_logs() {
    local lines="${1:-50}"
    journalctl -u "$SERVICE_NAME" -n "$lines" --no-pager
}

systemd_follow_logs() {
    journalctl -u "$SERVICE_NAME" -f
}
