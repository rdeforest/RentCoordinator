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

# The installed tree keeps its environment in .env (CloudFormation) or
# config.sh (the systemd unit's EnvironmentFile); a copy of this script also
# ships inside dist/, one directory below both of them.
for env_file in .env ../.env config.sh ../config.sh; do
  if [ -f "$env_file" ]; then
    set -a
    . "$env_file"
    set +a
    break
  fi
done

export DB_PATH="${DB_PATH:-./tenant-coordinator.db}"

if [ ! -f "$DB_PATH" ]; then
  echo "ERROR: no database at ${DB_PATH}." >&2
  echo "Set DB_PATH to the database you mean to migrate — reporting success" >&2
  echo "against a database that isn't there is how migrations got skipped." >&2
  exit 1
fi

echo "Applying migrations against ${DB_PATH}"

# The same script ships in the compiled artifact, where the runner is .js and
# there is no CoffeeScript to run it with.
if [ -f scripts/run-migrations.coffee ]; then
  npx coffee scripts/run-migrations.coffee
else
  node scripts/run-migrations.js
fi
