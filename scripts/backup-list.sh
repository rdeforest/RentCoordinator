#!/bin/bash
# List all backups in S3
# Usage: ./scripts/backup-list.sh

set -e

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

echo "Listing backups in S3..."
npx coffee -e "
  backup = require('./lib/services/backup.coffee')
  backups = await backup.listS3Backups()
  if backups.length > 0
    console.log('Found', backups.length, 'backups:')
    for b in backups
      console.log('  -', b.filename, '(', b.size, 'bytes,', b.lastModified, ')')
  else
    console.log('No backups found in S3')
"
