#!/bin/bash

readonly INIT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INIT_SYSTEMS_DIR="$INIT_LIB_DIR/init-systems"

# ============================================================================
# SOURCE ALL INIT SYSTEM MODULES
# ============================================================================

for init_module in "$INIT_SYSTEMS_DIR"/*.sh; do
    if [ -f "$init_module" ]; then
        source "$init_module"
    fi
done

# ============================================================================
# DETECTION & DELEGATION
# ============================================================================

detect_init_system() {
    if systemd_is_available 2>/dev/null; then
        echo "systemd"
    elif openrc_is_available 2>/dev/null; then
        echo "openrc"
    else
        echo "none"
    fi
}

require_init_system() {
    local init_system=$(detect_init_system)

    if [ "$init_system" = "none" ]; then
        print_error "No supported init system detected"
        print_info "Supported: systemd, OpenRC"
        exit 1
    fi

    echo "$init_system"
}

# ============================================================================
# UNIFIED INTERFACE
# ============================================================================

install_init_service() {
    local init_system=$(detect_init_system)

    if [ "$init_system" = "none" ]; then
        print_warning "No supported init system detected - service not installed"
        print_info "You can start the application manually using: $1/bin/rentcoordinator start"
        return 0
    fi

    print_info "Detected init system: $init_system"

    case "$init_system" in
        systemd)
            systemd_install_service "$@"
            ;;
        openrc)
            openrc_install_service "$@"
            ;;
        *)
            print_warning "Init system $init_system not yet supported"
            return 1
            ;;
    esac
}

uninstall_init_service() {
    local init_system=$(detect_init_system)

    if [ "$init_system" = "none" ]; then
        return 0
    fi

    print_info "Detected init system: $init_system"

    case "$init_system" in
        systemd)
            systemd_uninstall_service
            ;;
        openrc)
            openrc_uninstall_service
            ;;
        *)
            print_info "No service to uninstall for $init_system"
            return 0
            ;;
    esac
}

start_init_service() {
    local init_system=$(require_init_system)

    case "$init_system" in
        systemd)
            systemd_start_service
            ;;
        openrc)
            openrc_start_service
            ;;
        *)
            return 1
            ;;
    esac
}

stop_init_service() {
    local init_system=$(detect_init_system)

    if [ "$init_system" = "none" ]; then
        return 0
    fi

    case "$init_system" in
        systemd)
            systemd_stop_service
            ;;
        openrc)
            openrc_stop_service
            ;;
    esac

    return 0
}

get_init_service_status() {
    local init_system=$(detect_init_system)

    if [ "$init_system" = "none" ]; then
        return 1
    fi

    case "$init_system" in
        systemd)
            systemd_get_service_status
            ;;
        openrc)
            openrc_get_service_status
            ;;
        *)
            return 1
            ;;
    esac
}

enable_init_service() {
    local init_system=$(require_init_system)

    case "$init_system" in
        systemd)
            systemd_enable_service
            ;;
        openrc)
            openrc_enable_service
            ;;
        *)
            return 1
            ;;
    esac
}

disable_init_service() {
    local init_system=$(detect_init_system)

    if [ "$init_system" = "none" ]; then
        return 0
    fi

    case "$init_system" in
        systemd)
            systemd_disable_service
            ;;
        openrc)
            openrc_disable_service
            ;;
    esac

    return 0
}

show_init_service_logs() {
    local init_system=$(require_init_system)
    local lines="${1:-50}"

    case "$init_system" in
        systemd)
            systemd_show_logs "$lines"
            ;;
        openrc)
            openrc_show_logs "$lines"
            ;;
    esac
}

follow_init_service_logs() {
    local init_system=$(require_init_system)

    case "$init_system" in
        systemd)
            systemd_follow_logs
            ;;
        openrc)
            openrc_follow_logs
            ;;
    esac
}
