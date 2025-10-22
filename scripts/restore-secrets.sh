#!/usr/bin/env bash
# scripts/restore-secrets.sh
# Restore application secrets from AWS Secrets Manager to a server

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}ℹ${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*"; }

# Usage
if [ $# -eq 0 ]; then
  echo "Usage: $0 <server>"
  echo ""
  echo "Retrieves secrets from AWS Secrets Manager and configures them on the target server."
  echo ""
  echo "Example:"
  echo "  $0 vault2"
  echo ""
  exit 1
fi

SERVER="$1"
SECRET_NAME="rent-coordinator/config"
REGION="us-west-2"

info "========================================="
info "RentCoordinator Secrets Restore"
info "========================================="
info "Target: $SERVER"
info "Secret: $SECRET_NAME"
info ""

# Step 1: Retrieve secrets from AWS Secrets Manager
info "Step 1/3: Retrieving secrets from AWS Secrets Manager..."

if ! SECRETS=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --region "$REGION" \
  --query 'SecretString' \
  --output text 2>&1); then
  error "Failed to retrieve secrets from AWS Secrets Manager"
  error "$SECRETS"
  exit 1
fi

success "Secrets retrieved"

# Step 2: Parse secrets
info "Step 2/3: Parsing secrets..."

SESSION_SECRET=$(echo "$SECRETS" | jq -r '.SESSION_SECRET')
SMTP_HOST=$(echo "$SECRETS" | jq -r '.SMTP_HOST')
SMTP_PORT=$(echo "$SECRETS" | jq -r '.SMTP_PORT')
SMTP_USER=$(echo "$SECRETS" | jq -r '.SMTP_USER')
SMTP_PASS=$(echo "$SECRETS" | jq -r '.SMTP_PASS')
EMAIL_FROM=$(echo "$SECRETS" | jq -r '.EMAIL_FROM')
STRIPE_SECRET_KEY=$(echo "$SECRETS" | jq -r '.STRIPE_SECRET_KEY')
STRIPE_PUBLISHABLE_KEY=$(echo "$SECRETS" | jq -r '.STRIPE_PUBLISHABLE_KEY')

if [ "$SESSION_SECRET" = "null" ] || [ -z "$SESSION_SECRET" ]; then
  error "Failed to parse SESSION_SECRET from secrets"
  exit 1
fi

success "Secrets parsed successfully"

# Step 3: Deploy to server
info "Step 3/3: Deploying secrets to $SERVER..."

# Create temporary script to run on remote server
REMOTE_SCRIPT=$(cat <<'EOFREMOTE'
#!/bin/bash
set -euo pipefail

# Read secrets from stdin
read -r SESSION_SECRET
read -r SMTP_HOST
read -r SMTP_PORT
read -r SMTP_USER
read -r SMTP_PASS
read -r EMAIL_FROM
read -r STRIPE_SECRET_KEY
read -r STRIPE_PUBLISHABLE_KEY

# Check if config.sh exists
CONFIG_FILE="/home/admin/rent-coordinator/config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: $CONFIG_FILE not found"
  exit 1
fi

# Backup existing config
sudo -u rent-coordinator cp "$CONFIG_FILE" "$CONFIG_FILE.backup-$(date +%Y%m%d-%H%M%S)"

# Remove old secret lines if they exist
sudo -u rent-coordinator sed -i '/^SESSION_SECRET=/d' "$CONFIG_FILE"
sudo -u rent-coordinator sed -i '/^SMTP_HOST=/d' "$CONFIG_FILE"
sudo -u rent-coordinator sed -i '/^SMTP_PORT=/d' "$CONFIG_FILE"
sudo -u rent-coordinator sed -i '/^SMTP_USER=/d' "$CONFIG_FILE"
sudo -u rent-coordinator sed -i '/^SMTP_PASS=/d' "$CONFIG_FILE"
sudo -u rent-coordinator sed -i '/^EMAIL_FROM=/d' "$CONFIG_FILE"
sudo -u rent-coordinator sed -i '/^STRIPE_SECRET_KEY=/d' "$CONFIG_FILE"
sudo -u rent-coordinator sed -i '/^STRIPE_PUBLISHABLE_KEY=/d' "$CONFIG_FILE"

# Append new secrets
{
  echo ""
  echo "# Secrets from AWS Secrets Manager (restored $(date))"
  echo "SESSION_SECRET=$SESSION_SECRET"
  echo "SMTP_HOST=$SMTP_HOST"
  echo "SMTP_PORT=$SMTP_PORT"
  echo "SMTP_USER=$SMTP_USER"
  echo "SMTP_PASS=$SMTP_PASS"
  echo "EMAIL_FROM=$EMAIL_FROM"
  echo "STRIPE_SECRET_KEY=$STRIPE_SECRET_KEY"
  echo "STRIPE_PUBLISHABLE_KEY=$STRIPE_PUBLISHABLE_KEY"
} | sudo -u rent-coordinator tee -a "$CONFIG_FILE" > /dev/null

echo "Secrets configured successfully"
EOFREMOTE
)

# Execute on remote server - send secrets as environment variables
if ! ssh "$SERVER" \
  SESSION_SECRET="$SESSION_SECRET" \
  SMTP_HOST="$SMTP_HOST" \
  SMTP_PORT="$SMTP_PORT" \
  SMTP_USER="$SMTP_USER" \
  SMTP_PASS="$SMTP_PASS" \
  EMAIL_FROM="$EMAIL_FROM" \
  STRIPE_SECRET_KEY="$STRIPE_SECRET_KEY" \
  STRIPE_PUBLISHABLE_KEY="$STRIPE_PUBLISHABLE_KEY" \
  bash -s <<'EOFREMOTE2'
#!/bin/bash
set -euo pipefail

# Check if config.sh exists
CONFIG_FILE="/home/admin/rent-coordinator/config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: $CONFIG_FILE not found"
  exit 1
fi

# Backup existing config
sudo -u rent-coordinator cp "$CONFIG_FILE" "$CONFIG_FILE.backup-$(date +%Y%m%d-%H%M%S)"

# Remove old secret lines if they exist
sudo -u rent-coordinator sed -i '/^SESSION_SECRET=/d' "$CONFIG_FILE"
sudo -u rent-coordinator sed -i '/^SMTP_HOST=/d' "$CONFIG_FILE"
sudo -u rent-coordinator sed -i '/^SMTP_PORT=/d' "$CONFIG_FILE"
sudo -u rent-coordinator sed -i '/^SMTP_USER=/d' "$CONFIG_FILE"
sudo -u rent-coordinator sed -i '/^SMTP_PASS=/d' "$CONFIG_FILE"
sudo -u rent-coordinator sed -i '/^EMAIL_FROM=/d' "$CONFIG_FILE"
sudo -u rent-coordinator sed -i '/^STRIPE_SECRET_KEY=/d' "$CONFIG_FILE"
sudo -u rent-coordinator sed -i '/^STRIPE_PUBLISHABLE_KEY=/d' "$CONFIG_FILE"

# Append new secrets
{
  echo ""
  echo "# Secrets from AWS Secrets Manager (restored $(date))"
  echo "SESSION_SECRET=$SESSION_SECRET"
  echo "SMTP_HOST=$SMTP_HOST"
  echo "SMTP_PORT=$SMTP_PORT"
  echo "SMTP_USER=$SMTP_USER"
  echo "SMTP_PASS=$SMTP_PASS"
  echo "EMAIL_FROM=$EMAIL_FROM"
  echo "STRIPE_SECRET_KEY=$STRIPE_SECRET_KEY"
  echo "STRIPE_PUBLISHABLE_KEY=$STRIPE_PUBLISHABLE_KEY"
} | sudo -u rent-coordinator tee -a "$CONFIG_FILE" > /dev/null

echo "Secrets configured successfully"
EOFREMOTE2
then
  error "Failed to deploy secrets to $SERVER"
  exit 1
fi

success "Secrets deployed to $SERVER"
info ""
success "========================================="
success "Secrets restore complete!"
success "========================================="
info ""
info "Next steps:"
info "  1. Restart the service: ssh $SERVER 'sudo systemctl restart rent-coordinator'"
info "  2. Verify health: curl https://rent.thatsnice.org/health"
