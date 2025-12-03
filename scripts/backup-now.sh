#!/bin/bash
# Create an immediate database backup to S3
# Usage: ./scripts/backup-now.sh [backup-directory]

set -e

BACKUP_DIR="${1:-./backups}"

cd "$(dirname "$0")/.."

# Load environment if .env exists
if [ -f .env ]; then
  export $(cat .env | grep -v '^#' | xargs)
fi

# Ensure we're using the right node version
if [ -f ~/.nvm/nvm.sh ]; then
  . ~/.nvm/nvm.sh
  nvm use
fi

echo "Creating backup..."
npx coffee -e "
  backup = require('./lib/services/backup.coffee')
  result = await backup.createBackup('${BACKUP_DIR}')
  console.log('Backup created:', JSON.stringify(result, null, 2))
"
