#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

is_present() {
    [ -d /run/systemd/system ]
}

install() {
    local config_file="$1"

    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        print_error "Config file required: $0 install <config_file>"
        return 1
    fi

    source "$config_file"

    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"

    print_info "Installing systemd service..."

    run_as_root tee "$service_file" > /dev/null << EOF
[Unit]
Description=$SERVICE_DESCRIPTION
After=network.target
Documentation=$SERVICE_DOCUMENTATION

[Service]
Type=simple
User=$APP_USER
WorkingDirectory=$PREFIX
Environment="DENO_INSTALL=$DENO_INSTALL"
Environment="PATH=$DENO_INSTALL/bin:/usr/local/bin:/usr/bin:/bin"
Environment="PORT=$PORT"
Environment="DB_PATH=$DB_PATH"
Environment="LOG_DIR=$LOG_DIR"
Environment="NODE_ENV=production"
ExecStart=$DENO_INSTALL/bin/deno run --allow-read --allow-write --allow-env --allow-net --unstable-kv $PREFIX/dist/main.js
Restart=on-failure
RestartSec=10
StandardOutput=append:$LOG_DIR/app.log
StandardError=append:$LOG_DIR/app.log

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$LOG_DIR $(dirname "$DB_PATH")

[Install]
WantedBy=multi-user.target
EOF

    if [ $? -ne 0 ]; then
        print_error "Failed to create service file"
        return 1
    fi

    run_as_root chmod 644 "$service_file"

    run_as_root systemctl daemon-reload || {
        print_error "Failed to reload systemd"
        return 1
    }

    print_success "Systemd service installed"
    print_info "To enable on boot: sudo systemctl enable $SERVICE_NAME"
    print_info "To start now: sudo systemctl start $SERVICE_NAME"
    return 0
}

uninstall() {
    local config_file="$1"

    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        print_error "Config file required: $0 uninstall <config_file>"
        return 1
    fi

    source "$config_file"

    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"

    print_info "Uninstalling systemd service..."

    run_as_root systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    run_as_root systemctl disable "$SERVICE_NAME" 2>/dev/null || true

    if [ -f "$service_file" ]; then
        run_as_root rm -f "$service_file"
    fi

    run_as_root systemctl daemon-reload 2>/dev/null || true

    print_success "Systemd service uninstalled"
    return 0
}

case "$1" in
    is_present)
        is_present
        ;;
    install)
        install "$2"
        ;;
    uninstall)
        uninstall "$2"
        ;;
    *)
        echo "Usage: $0 {is_present|install|uninstall} [config_file]" >&2
        exit 1
        ;;
esac
