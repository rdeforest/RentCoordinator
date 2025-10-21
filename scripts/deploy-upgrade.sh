#!/bin/bash
# scripts/deploy-upgrade.sh
# Run from dev machine to upgrade RentCoordinator on remote server

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib/deploy-common.sh"

# Usage
if [ $# -lt 1 ]; then
    print_error "Usage: $0 <host>"
    print_info "Examples:"
    print_info "  $0 vault2.thatsnice.org"
    print_info "  $0 admin@vault2.thatsnice.org"
    exit 1
fi

REMOTE_HOST=$(parse_remote_host "$1")

print_info "========================================"
print_info "RentCoordinator Remote Upgrade"
print_info "========================================"
print_info "Target: $REMOTE_HOST"
print_info "Project: $PROJECT_DIR"
print_info ""

# Validate environment
print_info "Step 1/6: Validating environment..."
ENV_INFO=$(validate_deploy_environment "$REMOTE_HOST")
eval "$ENV_INFO"

if [ "$INSTALL_EXISTS" != "true" ]; then
    print_error "No installation found on $REMOTE_HOST"
    print_info "Use deploy-install.sh for first-time installation"
    exit 1
fi

# Build project
print_info "Step 2/6: Building project..."
build_project "$PROJECT_DIR"

# Create deployment package
print_info "Step 3/6: Creating deployment package..."
PACKAGE_DIR=$(create_deploy_package "$PROJECT_DIR")

# Push to remote home directory
print_info "Step 4/6: Pushing to remote..."
ssh "$REMOTE_HOST" "rm -rf ~/rent-coordinator-deploy"
rsync -az --delete "$PACKAGE_DIR/" "$REMOTE_HOST:~/rent-coordinator-deploy/" || {
    print_error "Failed to push deployment package"
    cleanup_local_package "$PACKAGE_DIR"
    exit 1
}
print_success "Deployed to $REMOTE_HOST:~/rent-coordinator-deploy"

# Execute remote upgrade script
print_info "Step 5/6: Executing remote upgrade..."
print_warning "This will:"
print_warning "  - Backup the database"
print_warning "  - Stop the service"
print_warning "  - Deploy new version"
print_warning "  - Restart and verify"
print_warning "  - Rollback automatically if verification fails"
print_info ""

ssh -t "$REMOTE_HOST" "cd ~/rent-coordinator-deploy && bash scripts/remote/upgrade-remote.sh" || {
    print_error "Remote upgrade failed"
    print_info "The remote server may have rolled back to the previous version"
    cleanup_local_package "$PACKAGE_DIR"
    exit 1
}

# Cleanup
print_info "Step 6/6: Cleaning up..."
cleanup_local_package "$PACKAGE_DIR"
ssh "$REMOTE_HOST" "rm -rf ~/rent-coordinator-deploy"

print_success "========================================"
print_success "Upgrade complete!"
print_success "========================================"
print_info ""
print_info "Check status: ssh $REMOTE_HOST 'sudo systemctl status rent-coordinator'"
print_info "View logs: ssh $REMOTE_HOST 'sudo journalctl -u rent-coordinator -f'"
