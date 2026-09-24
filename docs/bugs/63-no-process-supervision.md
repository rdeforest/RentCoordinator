# Bug 63 — A crash is not restarted, so any crash loses data since the last backup

**Reported:** 2026-09-24 by the pre-deploy review of the 2026-09 sweep
**Status:** open

## Symptom

If the Node process exits for any reason, nothing restarts it. `/health`
fails, the ALB marks the instance unhealthy, the ASG replaces it, and the
replacement restores the database from the newest S3 backup. Everything
written since that backup is lost.

## Root cause

The sysvinit script (`/etc/init.d/rent-coordinator`, from the Launch
Template UserData) starts the app once with `start-stop-daemon --background`
and has no respawn. With `HealthCheckType: ELB` and `ReplaceUnhealthy`
active, the ASG treats a dead process as a dead instance, and replacement
means restore-from-backup.

Bug 50 closed one way to crash the process; this bug is about the next one,
whatever it is.

## Proposed fix

Supervise the process so a crash is a restart, not a replacement. Options on
Devuan without systemd: an `inittab` `respawn` entry, runit/daemontools, or a
small restart loop in the init script. Any of these lives in UserData, so it
needs `deploy.sh deploy` to reach new instances as well as a manual change on
the running one.

Related: backup frequency bounds the loss when replacement does happen.
