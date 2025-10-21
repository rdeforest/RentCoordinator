#!/bin/bash
# scripts/deploy-uninstall.sh
# Run from dev machine to uninstall RentCoordinator from remote server

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib/deploy-common.sh"

# Usage
if [ $# -lt 1 ]; then
    print_error "Usage: $0 <host> [--force]"
    print_info "Examples:"
    print_info "  $0 vault2.thatsnice.org          # Interactive confirmation"
    print_info "  $0 admin@vault2 --force          # Skip confirmation"
    exit 1
fi

REMOTE_HOST=$(parse_remote_host "$1")
FORCE_FLAG=""

if [ "$2" = "--force" ]; then
    FORCE_FLAG="--force"
fi

print_warning "========================================"
print_warning "RentCoordinator Remote Uninstallation"
print_warning "========================================"
print_warning "Target: $REMOTE_HOST"
print_info ""

# Validate environment
print_info "Step 1/4: Validating environment..."
ENV_INFO=$(validate_deploy_environment "$REMOTE_HOST")
eval "$ENV_INFO"

if [ "$INSTALL_EXISTS" != "true" ]; then
    print_info "No installation found on $REMOTE_HOST"
    exit 0
fi

# Push uninstall script (we only need the remote scripts, not the whole package)
print_info "Step 2/4: Pushing uninstall script..."
ssh "$REMOTE_HOST" "mkdir -p ~/rent-coordinator-deploy/scripts"
rsync -az "$SCRIPT_DIR/remote/" "$REMOTE_HOST:~/rent-coordinator-deploy/scripts/remote/" || {
    print_error "Failed to push uninstall script"
    exit 1
}
rsync -az "$SCRIPT_DIR/lib/" "$REMOTE_HOST:~/rent-coordinator-deploy/scripts/lib/" || {
    print_error "Failed to push lib scripts"
    exit 1
}

# Execute remote uninstall script
print_info "Step 3/4: Executing remote uninstallation..."
print_warning "This will:"
print_warning "  - Stop the service"
print_warning "  - Remove application files"
print_warning "  - Remove system service"
print_warning "  - Remove service user"
print_warning "  - Preserve database and backups"
print_info ""

ssh -t "$REMOTE_HOST" "cd ~/rent-coordinator-deploy && bash scripts/remote/uninstall-remote.sh $FORCE_FLAG" || {
    print_error "Remote uninstallation failed"
    exit 1
}

# Cleanup
print_info "Step 4/4: Cleaning up..."
ssh "$REMOTE_HOST" "rm -rf ~/rent-coordinator-deploy"

print_success "========================================"
print_success "Uninstallation complete!"
print_success "========================================"
print_info ""
print_info "Database and backups may still exist on $REMOTE_HOST"
print_info "To check: ssh $REMOTE_HOST 'ls -la ~/rent-coordinator/'"
print_info "To remove all data: ssh $REMOTE_HOST 'rm -rf ~/rent-coordinator/'"
