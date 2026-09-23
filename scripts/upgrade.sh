#!/usr/bin/env bash
#
# Applies pending database migrations. Called by the in-place upgrade
# procedure in docs/deployment.md and by the instance bootstrap; safe to run
# repeatedly (scripts/run-migrations.coffee records what it has applied).
#
# This file was previously empty while migrations/README.md claimed it ran
# migrations, so following the documented procedure silently did nothing
# (bug 47).

set -euo pipefail

cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a
  . ./.env
  set +a
fi

export DB_PATH="${DB_PATH:-./tenant-coordinator.db}"

echo "Applying migrations against ${DB_PATH}"

# The same script ships in the compiled artifact, where the runner is .js and
# there is no CoffeeScript to run it with.
if [ -f scripts/run-migrations.coffee ]; then
  npx coffee scripts/run-migrations.coffee
else
  node scripts/run-migrations.js
fi
