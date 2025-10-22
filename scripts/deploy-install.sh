#!/bin/bash
# scripts/deploy-install.sh
# Run from dev machine to install RentCoordinator on remote server

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
print_info "RentCoordinator Remote Installation"
print_info "========================================"
print_info "Target: $REMOTE_HOST"
print_info "Project: $PROJECT_DIR"
print_info ""

# Validate environment
print_info "Step 1/7: Validating environment..."
ENV_INFO=$(validate_deploy_environment "$REMOTE_HOST")
eval "$ENV_INFO"

if [ "$INSTALL_EXISTS" = "true" ]; then
    print_error "Installation already exists on $REMOTE_HOST"
    print_info "Use deploy-upgrade.sh to update existing installation"
    exit 1
fi

# Build project
print_info "Step 2/7: Building project..."
build_project "$PROJECT_DIR"

# Create deployment package
print_info "Step 3/7: Creating deployment package..."
PACKAGE_DIR=$(create_deploy_package "$PROJECT_DIR")

# Push to remote home directory
print_info "Step 4/7: Pushing to remote..."
ssh "$REMOTE_HOST" "rm -rf ~/rent-coordinator-deploy"
rsync -az --delete "$PACKAGE_DIR/" "$REMOTE_HOST:~/rent-coordinator-deploy/" || {
    print_error "Failed to push deployment package"
    cleanup_local_package "$PACKAGE_DIR"
    exit 1
}
print_success "Deployed to $REMOTE_HOST:~/rent-coordinator-deploy"

# Execute remote install script
print_info "Step 5/7: Executing remote installation..."
ssh -t "$REMOTE_HOST" "cd ~/rent-coordinator-deploy && bash scripts/remote/install-remote.sh" || {
    print_error "Remote installation failed"
    cleanup_local_package "$PACKAGE_DIR"
    exit 1
}

# Try to restore secrets from AWS Secrets Manager (if available)
print_info "Step 6/7: Checking for secrets in AWS Secrets Manager..."
if command -v aws &> /dev/null; then
    SECRET_NAME="rent-coordinator/config"
    REGION="us-west-2"

    # Check if secret exists and we have access
    if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$REGION" &> /dev/null; then
        print_info "Found secrets in AWS Secrets Manager, restoring..."
        if "$SCRIPT_DIR/restore-secrets.sh" "$REMOTE_HOST"; then
            print_success "Secrets restored from AWS Secrets Manager"
            # Restart service to pick up new secrets
            ssh "$REMOTE_HOST" "sudo systemctl restart rent-coordinator" || true
        else
            print_warning "Failed to restore secrets, you'll need to configure manually"
        fi
    else
        print_info "No secrets found in AWS Secrets Manager (or no access)"
        print_info "You can configure secrets manually or run: ./scripts/restore-secrets.sh $REMOTE_HOST"
    fi
else
    print_info "AWS CLI not available, skipping automatic secret restoration"
    print_info "Install AWS CLI and run: ./scripts/restore-secrets.sh $REMOTE_HOST"
fi

# Cleanup
print_info "Step 7/7: Cleaning up..."
cleanup_local_package "$PACKAGE_DIR"
ssh "$REMOTE_HOST" "rm -rf ~/rent-coordinator-deploy"

print_success "========================================"
print_success "Installation complete!"
print_success "========================================"
print_info ""
print_info "Service is running at: https://rent.thatsnice.org"
print_info ""
print_info "If secrets were not auto-restored, configure manually:"
print_info "  1. SSH to server: ssh $REMOTE_HOST"
print_info "  2. Edit config: nano ~/rent-coordinator/config.sh"
print_info "  3. Configure SMTP and Stripe settings"
print_info "  4. Restart: sudo systemctl restart rent-coordinator"
print_info ""
print_info "Or restore from AWS Secrets Manager:"
print_info "  ./scripts/restore-secrets.sh $REMOTE_HOST"
print_info ""
print_info "View logs: ssh $REMOTE_HOST 'sudo journalctl -u rent-coordinator -f'"
