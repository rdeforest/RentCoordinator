#!/bin/bash
# Restore database from latest S3 backup
# Usage: ./scripts/backup-restore.sh

set -e

cd "$(dirname "$0")/.."

# Load environment if .env exists
if [ -f .env ]; then
  # `xargs` word-splits and strips quotes, so any value containing a space,
  # quote or '#' — Stripe keys, SMTP_PASS, SESSION_SECRET — arrived mangled
  # and the backup authenticated with a corrupted credential (bug 45).
  set -a && . ./.env && set +a
fi

# Ensure we're using the right node version
if [ -f ~/.nvm/nvm.sh ]; then
  . ~/.nvm/nvm.sh
  nvm use
fi

echo "Restoring from latest S3 backup..."
npx coffee -e "
  backup = require('./lib/services/backup.coffee')
  result = await backup.restoreFromS3()
  if result
    console.log('Database restored from:', result.backup.filename)
    console.log('Last modified:', result.backup.lastModified)
  else
    console.log('No backups found in S3')
"
