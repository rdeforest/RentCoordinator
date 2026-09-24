#!/bin/bash
# Restore database from latest S3 backup
# Usage: ./scripts/backup-restore.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

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
. "$SCRIPT_DIR/lib/service.sh"

if service_is_running; then
  echo "ERROR: rent-coordinator appears to be running." >&2
  echo "Stop it first, restore, then start it again:" >&2
  echo "  sudo systemctl stop rent-coordinator   # or /etc/init.d/rent-coordinator stop" >&2
  echo "  $0" >&2
  echo "  sudo systemctl start rent-coordinator" >&2
  echo >&2
  echo "Set RESTORE_ANYWAY=1 to override (the running process will keep serving" >&2
  echo "the pre-restore database and fail every write until it restarts)." >&2
  [ "${RESTORE_ANYWAY:-}" = "1" ] || exit 1
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
