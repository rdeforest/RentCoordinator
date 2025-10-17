#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

is_present() {
    [ -f /sbin/openrc-run ] || [ -f /sbin/openrc ]
}

install() {
    local config_file="$1"

    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        print_error "Config file required: $0 install <config_file>"
        return 1
    fi

    source "$config_file"

    local init_script="/etc/init.d/${SERVICE_NAME}"

    print_info "Installing OpenRC service..."

    run_as_root tee "$init_script" > /dev/null << EOF
#!/sbin/openrc-run

name="$SERVICE_NAME"
description="$SERVICE_DESCRIPTION"

PREFIX="$PREFIX"
APP_USER="$APP_USER"
LOG_DIR="$LOG_DIR"
DB_PATH="$DB_PATH"
PORT="$PORT"

USER_HOME="$USER_HOME"
DENO_INSTALL="$DENO_INSTALL"
pidfile="\$PREFIX/\${name}.pid"
command="\$DENO_INSTALL/bin/deno"
command_args="run --allow-read --allow-write --allow-env --allow-net --unstable-kv \$PREFIX/dist/main.js"
command_user="\$APP_USER"
command_background=true
directory="\$PREFIX"

[ -f "\$PREFIX/.env" ] && . "\$PREFIX/.env"

export DENO_INSTALL="\$DENO_INSTALL"
export PATH="\$DENO_INSTALL/bin:\$PATH"

output_log="\$LOG_DIR/app.log"
error_log="\$LOG_DIR/app.log"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath --directory --owner "\$APP_USER:\$APP_USER" --mode 0755 "\$LOG_DIR"
    checkpath --directory --owner "\$APP_USER:\$APP_USER" --mode 0755 "\$(dirname "\$DB_PATH")"
}

stop_post() {
    rm -f "\$pidfile"
}
EOF

    run_as_root chmod +x "$init_script"

    print_success "OpenRC service installed"
    print_info "To add to default runlevel: sudo rc-update add $SERVICE_NAME default"
    print_info "To start now: sudo rc-service $SERVICE_NAME start"
    return 0
}

uninstall() {
    local config_file="$1"

    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        print_error "Config file required: $0 uninstall <config_file>"
        return 1
    fi

    source "$config_file"

    local init_script="/etc/init.d/${SERVICE_NAME}"

    print_info "Uninstalling OpenRC service..."

    run_as_root rc-service "$SERVICE_NAME" stop 2>/dev/null || true
    run_as_root rc-update del "$SERVICE_NAME" 2>/dev/null || true

    if [ -f "$init_script" ]; then
        run_as_root rm -f "$init_script"
    fi

    print_success "OpenRC service uninstalled"
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
