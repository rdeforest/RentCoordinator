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

# The app refuses to start without SESSION_SECRET (lib/config.coffee) rather
# than fall back to a shared default — but start-stop-daemon --background
# returns 0 whether or not the process it launched stayed up, so a missing
# secret used to surface only as a silent failed restart in step 6 of
# docs/deployment.md, with nothing here to say why (bug 53). Same check, same
# message shape, as the one the instance bootstrap already runs against a
# fresh .env.
if [ -z "${env_file:-}" ] || [ ! -f "$env_file" ] || ! grep -q '^SESSION_SECRET=.\+' "$env_file"; then
  echo "FATAL: SESSION_SECRET missing from .env (or config.sh) — check the rent-coordinator/config secret" >&2
  exit 1
fi

# Whether DB_PATH was chosen or defaulted decides what a missing file means.
if [ -n "${DB_PATH:-}" ]; then
  DB_PATH_SUPPLIED=1
else
  DB_PATH_SUPPLIED=0
  DB_PATH=./tenant-coordinator.db
fi
export DB_PATH

if [ ! -f "$DB_PATH" ]; then
  if [ "$DB_PATH_SUPPLIED" = "1" ]; then
    # Somebody named this path. Reporting success against a database that is
    # not there is how migrations came to be skipped in the first place.
    echo "ERROR: no database at ${DB_PATH}." >&2
    echo "Set DB_PATH to the database you mean to migrate." >&2
    exit 1
  fi

  # Nothing named it and nothing is there: a first boot before the app has
  # created its schema. The app migrates on startup, so this is not an error —
  # and failing here would abort cloud-init before the service is installed.
  echo "No database at ${DB_PATH} yet; the app will create and migrate it on startup."
  exit 0
fi

echo "Applying migrations against ${DB_PATH}"

# The same script ships in the compiled artifact, where the runner is .js and
# there is no CoffeeScript to run it with.
if [ -f scripts/run-migrations.coffee ]; then
  npx coffee scripts/run-migrations.coffee
else
  node scripts/run-migrations.js
fi
