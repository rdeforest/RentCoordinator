#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

is_present() {
    # Check if we're using traditional SysVinit
    # Not systemd (PID 1 is not systemd), not OpenRC
    if [ -d /run/systemd/system ]; then
        return 1
    fi

    if [ -f /sbin/openrc-run ] || [ -f /sbin/openrc ]; then
        return 1
    fi

    # Check for traditional init
    if [ -d /etc/init.d ] && [ -x /sbin/init ]; then
        return 0
    fi

    return 1
}

install() {
    local config_file="$1"

    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        print_error "Config file required: $0 install <config_file>"
        return 1
    fi

    source "$config_file"

    local init_script="/etc/init.d/${SERVICE_NAME}"

    print_info "Installing SysVinit service..."

    run_as_root tee "$init_script" > /dev/null << EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          $SERVICE_NAME
# Required-Start:    \$remote_fs \$syslog \$network
# Required-Stop:     \$remote_fs \$syslog \$network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: $SERVICE_DESCRIPTION
# Description:       $SERVICE_DESCRIPTION
#                    $SERVICE_DOCUMENTATION
### END INIT INFO

PREFIX="$PREFIX"
APP_USER="$APP_USER"
LOG_DIR="$LOG_DIR"
DB_PATH="$DB_PATH"
PORT="$PORT"

USER_HOME="$USER_HOME"
DENO_INSTALL="$DENO_INSTALL"
PIDFILE="\$PREFIX/\$SERVICE_NAME.pid"

[ -f "\$PREFIX/.env" ] && . "\$PREFIX/.env"

export DENO_INSTALL="\$DENO_INSTALL"
export PATH="\$DENO_INSTALL/bin:\$PATH"

# Source LSB init functions
. /lib/lsb/init-functions

do_start() {
    log_daemon_msg "Starting $SERVICE_NAME"

    if [ -f "\$PIDFILE" ] && kill -0 \$(cat "\$PIDFILE") 2>/dev/null; then
        log_end_msg 1
        echo "$SERVICE_NAME is already running"
        return 1
    fi

    start-stop-daemon --start --quiet \\
        --pidfile "\$PIDFILE" \\
        --make-pidfile \\
        --chuid "\$APP_USER" \\
        --chdir "\$PREFIX" \\
        --background \\
        --startas /bin/sh -- -c "\\
            exec \$DENO_INSTALL/bin/deno run \\
                --allow-read --allow-write --allow-env --allow-net --unstable-kv \\
                \$PREFIX/dist/main.js >> \$LOG_DIR/app.log 2>&1"

    if [ \$? -eq 0 ]; then
        log_end_msg 0
        return 0
    else
        log_end_msg 1
        return 1
    fi
}

do_stop() {
    log_daemon_msg "Stopping $SERVICE_NAME"

    if [ ! -f "\$PIDFILE" ]; then
        log_end_msg 0
        echo "$SERVICE_NAME is not running"
        return 0
    fi

    start-stop-daemon --stop --quiet \\
        --pidfile "\$PIDFILE" \\
        --retry=TERM/30/KILL/5

    RETVAL=\$?
    rm -f "\$PIDFILE"
    log_end_msg \$RETVAL
    return \$RETVAL
}

do_status() {
    if [ -f "\$PIDFILE" ] && kill -0 \$(cat "\$PIDFILE") 2>/dev/null; then
        echo "$SERVICE_NAME is running (PID: \$(cat \$PIDFILE))"
        return 0
    else
        echo "$SERVICE_NAME is not running"
        [ -f "\$PIDFILE" ] && rm -f "\$PIDFILE"
        return 3
    fi
}

case "\$1" in
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    restart|reload|force-reload)
        do_stop
        sleep 2
        do_start
        ;;
    status)
        do_status
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|reload|force-reload|status}"
        exit 1
        ;;
esac

exit \$?
EOF

    run_as_root chmod +x "$init_script"

    # Install service for default runlevels
    if command -v update-rc.d >/dev/null 2>&1; then
        run_as_root update-rc.d "$SERVICE_NAME" defaults || {
            print_error "Failed to install service with update-rc.d"
            return 1
        }
    elif command -v chkconfig >/dev/null 2>&1; then
        run_as_root chkconfig --add "$SERVICE_NAME" || {
            print_error "Failed to install service with chkconfig"
            return 1
        }
    else
        print_warning "No service management tool found (update-rc.d or chkconfig)"
        print_info "Service script installed but not enabled for boot"
    fi

    print_success "SysVinit service installed"
    print_info "To start now: sudo service $SERVICE_NAME start"
    print_info "Or: sudo /etc/init.d/$SERVICE_NAME start"
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

    print_info "Uninstalling SysVinit service..."

    # Stop service
    if [ -x "$init_script" ]; then
        run_as_root "$init_script" stop 2>/dev/null || true
    fi

    # Remove from runlevels
    if command -v update-rc.d >/dev/null 2>&1; then
        run_as_root update-rc.d -f "$SERVICE_NAME" remove 2>/dev/null || true
    elif command -v chkconfig >/dev/null 2>&1; then
        run_as_root chkconfig --del "$SERVICE_NAME" 2>/dev/null || true
    fi

    # Remove init script
    if [ -f "$init_script" ]; then
        run_as_root rm -f "$init_script"
    fi

    print_success "SysVinit service uninstalled"
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
