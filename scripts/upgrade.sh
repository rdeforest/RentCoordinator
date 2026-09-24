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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

# Under sudo, PATH is secure_path and node lives only in the app user's nvm.
if ! command -v node >/dev/null && [ -f ~/.nvm/nvm.sh ]; then
  . ~/.nvm/nvm.sh
  nvm use >/dev/null
fi

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

# The app refuses to start without SESSION_SECRET unless NODE_ENV is
# development or test (lib/config.coffee), and start-stop-daemon --background
# reports success either way (bug 53). Same rule, checked here, where the
# operator is watching.
case "${NODE_ENV:-}" in
  development|test) ;;
  *)
    if [ -z "${SESSION_SECRET:-}" ]; then
      echo "FATAL: SESSION_SECRET is not set and NODE_ENV is '${NODE_ENV:-unset}' — check the rent-coordinator/config secret" >&2
      exit 1
    fi
    ;;
esac

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

# A migration that fails partway restores its pre-migration snapshot with
# copyFileSync (scripts/run-migrations.coffee), which writes into the
# existing file rather than replacing it — deliberately, so a connection the
# application already holds follows the restored content. That means a
# migration run against a live database doesn't just risk missing the running
# process's writes; a rollback overwrites them, discarding anything written
# after the snapshot was taken (bug 52). docs/deployment.md's procedure now
# stops the service before this step; this is the check for when that step
# was skipped.
. "$SCRIPT_DIR/lib/service.sh"

if service_is_running; then
  echo "ERROR: rent-coordinator appears to be running." >&2
  echo "Stop it first, migrate, then start it again:" >&2
  echo "  sudo /etc/init.d/rent-coordinator stop   # or systemctl stop rent-coordinator" >&2
  echo "  $0" >&2
  echo "  sudo /etc/init.d/rent-coordinator start" >&2
  echo >&2
  echo "Set UPGRADE_ANYWAY=1 to override (a failed migration's rollback would" >&2
  echo "discard any writes the running process made after the snapshot)." >&2
  [ "${UPGRADE_ANYWAY:-}" = "1" ] || exit 1
fi

echo "Applying migrations against ${DB_PATH}"

# The same script ships in the compiled artifact, where the runner is .js and
# there is no CoffeeScript to run it with.
if [ -f scripts/run-migrations.coffee ]; then
  npx coffee scripts/run-migrations.coffee
else
  node scripts/run-migrations.js
fi
