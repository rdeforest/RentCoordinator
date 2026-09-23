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

# The server holds one long-lived SQLite connection. A restore swaps the file
# underneath it, and an open handle follows the inode, not the name — so a
# restore run while the service is up leaves it answering from the old
# database and failing every write, with /health still reporting healthy.
# Nothing in this process can reopen that connection.
PIDFILE="${PIDFILE:-/var/run/rent-coordinator.pid}"

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "ERROR: rent-coordinator is running (pid $(cat "$PIDFILE"))." >&2
  echo "Stop it first, restore, then start it again:" >&2
  echo "  sudo /etc/init.d/rent-coordinator stop" >&2
  echo "  $0" >&2
  echo "  sudo /etc/init.d/rent-coordinator start" >&2
  exit 1
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
