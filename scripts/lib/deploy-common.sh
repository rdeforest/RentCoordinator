#!/bin/bash
# scripts/lib/deploy-common.sh
# Deployment-specific functions

# Source base common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Parse host argument (supports user@host or just host)
parse_remote_host() {
    local host_arg="$1"

    if [[ -z "$host_arg" ]]; then
        print_error "No host specified. Usage: $0 <host> or $0 <user@host>"
        exit 1
    fi

    echo "$host_arg"
}

# Validate SSH connection
validate_ssh() {
    local host="$1"

    print_info "Validating SSH connection to $host..." >&2

    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" "echo 'SSH OK'" &>/dev/null; then
        print_error "Cannot connect to $host via SSH" >&2
        print_info "Check your SSH keys and ~/.ssh/config" >&2
        exit 1
    fi

    print_success "SSH connection verified" >&2
}

# Validate passwordless sudo on remote
validate_remote_sudo() {
    local host="$1"

    print_info "Validating passwordless sudo on $host..." >&2

    if ! ssh "$host" "sudo -n true" 2>/dev/null; then
        print_error "Passwordless sudo not configured on $host" >&2
        print_info "Add to /etc/sudoers: $(ssh "$host" "whoami") ALL=(ALL) NOPASSWD: ALL" >&2
        exit 1
    fi

    print_success "Passwordless sudo verified" >&2
}

# Probe remote system information
probe_remote() {
    local host="$1"

    print_info "Probing remote system..." >&2

    # Get remote home directory
    local remote_home
    remote_home=$(ssh "$host" "echo \$HOME")

    # Detect init system
    local init_system="none"
    if ssh "$host" "command -v systemctl &>/dev/null"; then
        init_system="systemd"
    elif ssh "$host" "command -v rc-service &>/dev/null"; then
        init_system="openrc"
    elif ssh "$host" "test -d /etc/init.d"; then
        init_system="sysvinit"
    fi

    # Check if service exists
    local service_exists="false"
    case "$init_system" in
        systemd)
            if ssh "$host" "systemctl list-unit-files 2>/dev/null | grep -q '^rent-coordinator.service'"; then
                service_exists="true"
            fi
            ;;
        openrc)
            if ssh "$host" "rc-service --list 2>/dev/null | grep -q rent-coordinator"; then
                service_exists="true"
            fi
            ;;
        sysvinit)
            if ssh "$host" "test -f /etc/init.d/rent-coordinator"; then
                service_exists="true"
            fi
            ;;
    esac

    # Check if installation directory exists
    local install_exists="false"
    if ssh "$host" "test -d '$remote_home/rent-coordinator'"; then
        install_exists="true"
    fi

    # Check if service user exists
    local service_user_exists="false"
    if ssh "$host" "id rent-coordinator &>/dev/null"; then
        service_user_exists="true"
    fi

    print_info "  Remote home: $remote_home" >&2
    print_info "  Init system: $init_system" >&2
    print_info "  Service exists: $service_exists" >&2
    print_info "  Installation exists: $install_exists" >&2
    print_info "  Service user exists: $service_user_exists" >&2

    # Export as environment variables (only this goes to stdout)
    cat <<EOF
REMOTE_HOME=$remote_home
INIT_SYSTEM=$init_system
SERVICE_EXISTS=$service_exists
INSTALL_EXISTS=$install_exists
SERVICE_USER_EXISTS=$service_user_exists
EOF
}

# Validate deployment environment
validate_deploy_environment() {
    local host="$1"

    print_info "===================================" >&2
    print_info "Validating deployment environment" >&2
    print_info "===================================" >&2

    validate_ssh "$host"
    validate_remote_sudo "$host"

    # Probe and set environment variables
    local probe_output
    probe_output=$(probe_remote "$host")
    eval "$probe_output"

    print_success "Environment validation complete" >&2
    echo "" >&2

    # Return probe results (only this goes to stdout)
    echo "$probe_output"
}

# Build project locally
build_project() {
    local project_dir="$1"

    print_info "Building project locally..."

    cd "$project_dir" || {
        print_error "Cannot change to project directory: $project_dir"
        exit 1
    }

    if [ ! -f "package.json" ]; then
        print_error "Not a valid project directory (no package.json)"
        exit 1
    fi

    npm run build || {
        print_error "Build failed"
        exit 1
    }

    if [ ! -d "dist" ]; then
        print_error "Build did not create dist/ directory"
        exit 1
    fi

    print_success "Build complete"
}

# Create deployment package
create_deploy_package() {
    local project_dir="$1"
    local package_dir="/tmp/rent-coordinator-deploy-$$"

    print_info "Creating deployment package..." >&2

    mkdir -p "$package_dir" || {
        print_error "Cannot create temp directory" >&2
        exit 1
    }

    # Copy dist directory
    cp -r "$project_dir/dist" "$package_dir/" || {
        print_error "Cannot copy dist/" >&2
        rm -rf "$package_dir"
        exit 1
    }

    # Copy remote scripts
    mkdir -p "$package_dir/scripts"
    cp -r "$project_dir/scripts/remote" "$package_dir/scripts/" || {
        print_error "Cannot copy remote scripts" >&2
        rm -rf "$package_dir"
        exit 1
    }

    # Copy lib scripts (needed by remote scripts)
    cp -r "$project_dir/scripts/lib" "$package_dir/scripts/" || {
        print_error "Cannot copy lib scripts" >&2
        rm -rf "$package_dir"
        exit 1
    }

    # Copy package files
    cp "$project_dir/package.json" "$package_dir/" 2>/dev/null || true
    cp "$project_dir/deno.json" "$package_dir/" 2>/dev/null || true

    print_success "Deployment package created" >&2
    # Only output the path to stdout
    echo "$package_dir"
}

# Push deployment package to remote
push_to_remote() {
    local host="$1"
    local package_dir="$2"
    local remote_tmp="/tmp/rent-coordinator-deploy"

    print_info "Pushing deployment package to $host..."

    # Clean remote tmp if exists
    ssh "$host" "rm -rf $remote_tmp" || true

    # Push via rsync (creates remote directory)
    rsync -az --delete "$package_dir/" "$host:$remote_tmp/" || {
        print_error "Failed to push deployment package"
        exit 1
    }

    print_success "Deployment package pushed to $host:$remote_tmp"
    echo "$remote_tmp"
}

# Execute remote script
execute_remote_script() {
    local host="$1"
    local script_path="$2"
    shift 2
    local args="$@"

    print_info "Executing remote script: $(basename "$script_path")"

    ssh -t "$host" "bash $script_path $args"
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        print_error "Remote script failed with exit code: $exit_code"
        return $exit_code
    fi

    print_success "Remote script completed successfully"
    return 0
}

# Cleanup local temp files
cleanup_local_package() {
    local package_dir="$1"

    if [ -n "$package_dir" ] && [ -d "$package_dir" ]; then
        rm -rf "$package_dir"
    fi
}

# Export functions
export -f parse_remote_host validate_ssh validate_remote_sudo
export -f probe_remote validate_deploy_environment
export -f build_project create_deploy_package push_to_remote
export -f execute_remote_script cleanup_local_package
