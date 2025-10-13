#!/bin/bash

readonly INIT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INIT_SYSTEMS_DIR="$INIT_LIB_DIR/init-systems"

detect_init_system() {
    for init_script in "$INIT_SYSTEMS_DIR"/*.sh; do
        if [ -x "$init_script" ] && "$init_script" is_present 2>/dev/null; then
            basename "$init_script" .sh
            return 0
        fi
    done
    echo "none"
}

install_init_service() {
    local config_file="$1"

    local init_system=$(detect_init_system)

    if [ "$init_system" = "none" ]; then
        print_warning "No supported init system detected - service not installed"
        print_info "You can start the application manually using: $PREFIX/bin/rentcoordinator start"
        return 0
    fi

    print_info "Detected init system: $init_system"

    local init_script="$INIT_SYSTEMS_DIR/${init_system}.sh"
    "$init_script" install "$config_file"
}

uninstall_init_service() {
    local config_file="$1"

    local init_system=$(detect_init_system)

    if [ "$init_system" = "none" ]; then
        return 0
    fi

    print_info "Detected init system: $init_system"

    local init_script="$INIT_SYSTEMS_DIR/${init_system}.sh"
    "$init_script" uninstall "$config_file"
}
