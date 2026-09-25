#!/bin/bash
#
# service_is_running: is rent-coordinator up right now?
#
# Shared by scripts/backup-restore.sh and scripts/upgrade.sh, both of which
# need to refuse to run against a live database (bug 52; the restore case
# predates it, from bug 34). Asked three ways, because only one of them works
# on any given host: the CloudFormation SysVInit script writes a pidfile, the
# systemd unit the installer writes is Type=simple with no PIDFile=, and a
# process may be running under neither.
#
# Usage: source this file, then set PIDFILE / PORT (both have defaults) and
# call service_is_running.

PIDFILE="${PIDFILE:-/var/run/rent-coordinator/rent-coordinator.pid}"
PORT="${PORT:-8080}"

service_is_running() {
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then return 0; fi
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet rent-coordinator; then return 0; fi
  if command -v lsof >/dev/null 2>&1 && lsof -ti ":${PORT}" >/dev/null 2>&1; then return 0; fi
  return 1
}
