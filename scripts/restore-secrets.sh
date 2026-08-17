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

# The single source of truth for which secrets we manage. Add a key here and
# it flows through parse, delete, and append automatically — on both sides.
# Anything present in Secrets Manager but absent from this list is ignored;
# anything in this list but absent from the secret is skipped (not written as
# the literal "null", which the old per-key version did).
SECRET_KEYS=(
  SESSION_SECRET
  SMTP_HOST
  SMTP_PORT
  SMTP_USER
  SMTP_PASS
  EMAIL_FROM
  STRIPE_SECRET_KEY
  STRIPE_PUBLISHABLE_KEY
  STRIPE_WEBHOOK_SECRET
)

# Step 2: Parse secrets
info "Step 2/3: Parsing secrets..."

# Build the KEY=VALUE block to write, skipping any key not in the secret.
SECRET_BLOCK=""
for key in "${SECRET_KEYS[@]}"; do
  value=$(echo "$SECRETS" | jq -r --arg k "$key" '.[$k] // empty')
  if [ -z "$value" ]; then
    warn "  $key not present in secret — skipping"
    continue
  fi
  SECRET_BLOCK+="${key}=${value}"$'\n'
done

if ! printf '%s' "$SECRET_BLOCK" | grep -q '^SESSION_SECRET='; then
  error "Failed to parse SESSION_SECRET from secrets"
  exit 1
fi

success "Secrets parsed successfully"

# Step 3: Deploy to server
info "Step 3/3: Deploying secrets to $SERVER..."

# Ship the block base64-encoded: a single shell-safe line, so values with
# spaces or special characters survive the trip (the old per-var command
# line broke on those), and the remote script derives the key list from the
# block itself — no second copy to keep in sync.
SECRETS_B64=$(printf '%s' "$SECRET_BLOCK" | base64 | tr -d '\n')

if ! ssh "$SERVER" SECRETS_B64="$SECRETS_B64" bash -s <<'EOFREMOTE'
set -euo pipefail

CONFIG_FILE="/home/admin/rent-coordinator/config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: $CONFIG_FILE not found"
  exit 1
fi

SECRET_BLOCK=$(printf '%s' "$SECRETS_B64" | base64 -d)

# Backup existing config
sudo -u rent-coordinator cp "$CONFIG_FILE" "$CONFIG_FILE.backup-$(date +%Y%m%d-%H%M%S)"

# Remove any existing line for each key we're about to set
while IFS= read -r line; do
  [ -z "$line" ] && continue
  key="${line%%=*}"
  sudo -u rent-coordinator sed -i "/^${key}=/d" "$CONFIG_FILE"
done <<< "$SECRET_BLOCK"

# Append the fresh values
{
  echo ""
  echo "# Secrets from AWS Secrets Manager (restored $(date))"
  printf '%s\n' "$SECRET_BLOCK"
} | sudo -u rent-coordinator tee -a "$CONFIG_FILE" > /dev/null

echo "Secrets configured successfully"
EOFREMOTE
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
