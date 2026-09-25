# Bug 63 — A crash is not restarted, so any crash loses data since the last backup

**Reported:** 2026-09-24 by the pre-deploy review of the 2026-09 sweep
**Status:** resolved 2026-09-24

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

## Resolution

`daemon(1)` (Devuan package `daemon`) supervises the app from the existing
init script, so `/etc/init.d/rent-coordinator start|stop|restart|status` is
unchanged. `--acceptable=10 --delay=10`: the 300 s defaults would count any
crash in the first five minutes as a failed start and then pause long enough
for the ALB to declare the instance dead. `stop` waits for the node process
itself, because `daemon --stop` returns once it has signalled. daemon runs as
the app user, so pidfiles moved to `/var/run/rent-coordinator/` (created on
each start; `/var/run` is tmpfs), and `scripts/lib/service.sh` follows.

Chosen over runit because it keeps the init-script interface the deploy
procedure uses, and one service per VM is policy, so a supervision tree buys
nothing. inittab `respawn` was rejected because stopping for a deploy would
mean editing inittab.

Verified on production 2026-09-25: `kill -9` of the node process was back and
healthy within seconds under a new pid; `upgrade.sh` refuses while it runs and
proceeds after `stop`; restart cycles cleanly. Launch Template updated via a
change set whose only direct change was `LaunchTemplateData`.
