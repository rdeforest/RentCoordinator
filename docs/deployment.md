# RentCoordinator Deployment Guide

Canonical deployment procedure. CloudFormation/infrastructure details live in
[infrastructure/README.md](../infrastructure/README.md); disaster recovery in
[disaster-recovery.md](disaster-recovery.md); DB migrations in
[migrations/README.md](../migrations/README.md).

## What production is

AWS CloudFormation + an Auto Scaling Group behind an Application Load
Balancer. Key facts that shape the procedure below:

- **Devuan AMI → sysvinit, not systemd.** The service is
  `/etc/init.d/rent-coordinator` (`start|stop|restart|status`). There is no
  `systemctl`. The app runs under `daemon --respawn`, so if the process dies
  it is restarted within seconds (bug 63); `stop` stops supervision too.
  Pidfiles live in `/var/run/rent-coordinator/`.
- App lives at `/opt/rent-coordinator` (git clone of `main`, pulled on boot),
  runs as user `rent-coordinator` on **port 8080**. DB at
  `/var/lib/rent-coordinator/tenant-coordinator.db`. Env at
  `/opt/rent-coordinator/.env`, written from Secrets Manager at boot.
- ASG health-check type is **ELB**, desired count 1. `ReplaceUnhealthy` is
  currently **active** — a failing `/health` gets the instance replaced (this
  is how the 2026-09-03 outage self-healed). Suspend it during manual
  restarts (below) so a blip can't trigger a replacement mid-deploy.
- A fresh instance **restores its DB from the latest S3 backup** and runs
  migrations before starting. So a replacement loses anything written since
  the last backup — **always back up first** (see Backups).
- The Devuan AMI intermittently skips cloud-init's user-data at boot, so a
  fresh instance sometimes comes up with no app installed. Workaround in
  [disaster-recovery.md](disaster-recovery.md).

## Deploying code — in-place upgrade (preferred)

Because a replacement restores from S3 and cloud-init is flaky, the default
is to upgrade the running instance in place (preserves the live DB):

Stop before you pull, migrate before you start. The pull can change
`.nvmrc` and `package-lock.json`, so nothing should read the new tree while
the old service is still up to respawn from it. `scripts/upgrade.sh` now
refuses to run against a live database (bug 52) — a migration that fails
partway restores its pre-migration snapshot by writing into the existing
file, which an open connection follows; a rollback while the old process is
still up would discard whatever it wrote after the snapshot was taken, not
just leave it stale. The order below keeps that from ever coming up rather
than relying on the refusal to catch it.

```bash
# 1. Back up prod first (see Backups) and confirm it's in S3.

# 2. Ship code to main (instances track main).
#    If this change touches UserData, refresh the Launch Template first (see
#    Deploying infrastructure).
git push origin <branch>:main

# 3a. From your workstation, guard against replacement while the service is
#     down. The box cannot do this: its instance role has no autoscaling
#     permissions. Do not stop the service until the second command lists
#     both HealthCheck and ReplaceUnhealthy.
aws autoscaling suspend-processes --auto-scaling-group-name RentCoordinator-production \
  --scaling-processes HealthCheck ReplaceUnhealthy
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names RentCoordinator-production \
  --query 'AutoScalingGroups[0].SuspendedProcesses'

# 3b. On the instance (find IP below), note the current commit (the rollback
#     point), then stop the service:
ssh -i ~/.ssh/id_aws_rdeforest admin@<INSTANCE_IP>
cd /opt/rent-coordinator
sudo -u rent-coordinator git log -1 --oneline
sudo /etc/init.d/rent-coordinator stop

# 4. Pull:
sudo -u rent-coordinator git pull --ff-only

# 5. If Secrets Manager gained a new key since the instance booted, append it
#    to .env (a running instance's .env is only written once, at boot).
#    SESSION_SECRET must be present: upgrade.sh and the app both refuse to
#    proceed without it, rather than fall back to a shared default.

# 6. Install the Node version the pulled .nvmrc names, and the dependencies.
#    npm ci deletes node_modules first. If this fails at any point (nvm
#    install or npm ci), re-run it, or roll back with
#    `sudo -u rent-coordinator git reset --hard <commit noted in 3b>` and
#    re-run it. (Not ORIG_HEAD: a repeated pull overwrites it.) Do not start
#    the service until it succeeds.
sudo -u rent-coordinator -H ./scripts/install-runtime.sh

# 7. Apply any pending database migrations. Safe to run when there are none;
#    the server also applies pending migrations at boot, so this is belt and
#    braces — but running it here means a bad migration fails while you are
#    watching, rather than during startup.
#
#    A run is all-or-nothing: the runner snapshots the database first and
#    restores it if any migration fails, leaving the snapshot as
#    <db>.pre-migration-<timestamp> (the newest 3 are kept; older ones are
#    pruned on a successful run). To find that out before touching the
#    instance at all, run the migrations against a backup from your
#    workstation first:
#      DB_PATH=./backups/<latest>.db npm run migrate:check
sudo -u rent-coordinator ./scripts/upgrade.sh

# 8. Start the service back up:
sudo /etc/init.d/rent-coordinator start

# 9. Verify on the box, then resume from your workstation:
curl -s http://localhost:8080/health
aws autoscaling resume-processes --auto-scaling-group-name RentCoordinator-production \
  --scaling-processes HealthCheck ReplaceUnhealthy

# 10. Once verified, remove the Node version step 6 replaced, if any, and
#     nvm's download cache:
sudo -u rent-coordinator -H bash -c '. ~/.nvm/nvm.sh && nvm ls --no-colors'
sudo -u rent-coordinator -H bash -c '. ~/.nvm/nvm.sh && nvm uninstall <old version> && nvm cache clear'
```

Verify externally too: `curl https://rent.thatsnice.org/health` and, for a
payment deploy, `POST /payment/webhook` with no signature should return 400.

## Deploying infrastructure / replacing the instance

`deploy.sh deploy` updates the CloudFormation stack (and the Launch Template,
so future instances pick up UserData changes). It does **not** replace the
running instance:

```bash
cd infrastructure && ./deploy.sh deploy
```

To roll a new instance (e.g. after an AMI or UserData change), terminate the
current one so the ASG relaunches from the new Launch Template. **Back up
first** — the replacement restores from S3 — and watch for the cloud-init
bug. Full detail in [infrastructure/README.md](../infrastructure/README.md).

## Patching

Three things need security updates, and each has its own channel.

| What | Detected by | Applied by |
|---|---|---|
| Node.js | Renovate PR bumping `.nvmrc`, 3 days after release | test, merge, then the in-place deploy (step 6) |
| npm packages | Renovate: a security PR as soon as an advisory names a version in the lockfile; otherwise one grouped PR a month holding only releases at least 90 days old | test, merge, then the in-place deploy (step 6) |
| OS packages | `unattended-upgrades` (daily, security only) | `unattended-upgrades` installs them daily, from `/etc/cron.daily/apt-compat`; libraries the running node process maps take effect at its next restart, kernels at the next reboot |

Any change to how UserData installs Node or reads `.nvmrc` must reach the
Launch Template before a commit that depends on it reaches `main`, because a
replacement instance runs whatever UserData the template holds against
whatever `main` holds. Run `cd infrastructure && ./deploy.sh deploy`, then
confirm the new UserData is in the latest version:

```bash
aws ec2 describe-launch-template-versions --region us-west-2 \
  --launch-template-name RentCoordinator-production --versions '$Latest' \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.UserData' --output text | base64 -d | less
```

Renovate does nothing until Robert installs the Renovate GitHub App on
rdeforest/RentCoordinator; once it is installed, a Dependency Dashboard issue
appears. Major bumps (express 5, Node 26) wait there for approval instead of
arriving as PRs.

Supply-chain policy (Robert, 2026-10-23): nobody here can vet upstream diffs,
so routine npm updates bake for 90 days (`minimumReleaseAge`) before Renovate
proposes them. Most hijacked releases are caught and pulled well inside that,
and an attacker who waits it out still has to get a patch accepted upstream
and then cause a real advisory that requires it. Advisories override the bake
(`vulnerabilityAlerts.minimumReleaseAge: null`). Node itself waits only
3 days: its releases come from the Node.js release team, not the npm registry,
and its security fixes carry no npm advisory to trigger the override.
`.npmrc` sets `ignore-scripts=true`, so no dependency runs code at install
time (none of the current ones needs to).

`main` is what the next new instance runs — any replacement clones it — so
merge only what is ready to deploy. There is no CI: before merging a Renovate
PR, check out its branch and run `nvm install && npm ci && npm run test:all`.

Known holes:

- `static/vendor/coffeescript.js` (served at `/vendor/coffeescript.js`,
  loaded only by `test.html`) is vendored, so Renovate never sees it.
- The nvm installer is pinned at v0.40.1 in UserData and CLAUDE.md's local
  setup, and nothing tracks it.

`unattended-upgrades` never reboots (`Unattended-Upgrade::Automatic-Reboot
"false"` in `/etc/apt/apt.conf.d/51rent-coordinator`), deliberately: a reboot
fails the ELB health check, and with `ReplaceUnhealthy` active the ASG
replaces the instance and restores from the last S3 backup. So a kernel
update — including the one the boot-time run installs on every new instance,
whose AMI kernel is older — leaves `/var/run/reboot-required` behind, and
nothing reports it: check for it when on the box
(`ls /var/run/reboot-required`), and reboot by hand:

```bash
# Workstation: suspend replacement; do not go on until both processes are listed.
aws autoscaling suspend-processes --auto-scaling-group-name RentCoordinator-production \
  --scaling-processes HealthCheck ReplaceUnhealthy
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names RentCoordinator-production \
  --query 'AutoScalingGroups[0].SuspendedProcesses'

# On the box: stop the service so the backup is quiescent, back up, reboot.
# backup-now.sh exits 0 even when the S3 upload fails; reboot only if it
# printed "Backup uploaded successfully to S3".
sudo /etc/init.d/rent-coordinator stop
sudo -u rent-coordinator /opt/rent-coordinator/scripts/backup-now.sh
sudo reboot

# Workstation: repeat until it prints 200, then resume replacement.
curl -fsS -o /dev/null -w '%{http_code}\n' https://rent.thatsnice.org/health
aws autoscaling resume-processes --auto-scaling-group-name RentCoordinator-production \
  --scaling-processes HealthCheck ReplaceUnhealthy
```

If `/health` is not 200 within about 10 minutes, SSH in and check
`sudo /etc/init.d/rent-coordinator status` and the app log. On a reboot the
app is started by init.d, not cloud-init, so the cloud-init workaround in
[disaster-recovery.md](disaster-recovery.md) does not apply (it would re-run
the whole bootstrap). Do not resume replacement while the box is down unless
you intend the ASG to replace it from the backup just taken.

## Finding the current instance

```bash
aws ec2 describe-instances --region us-west-2 \
  --filters Name=tag:Name,Values=RentCoordinator-production \
            Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].{Id:InstanceId,IP:PublicIpAddress}' --output table
```

SSH user is `admin` on the current Devuan AMI.

## Logs and monitoring

**CloudWatch log shipping is not working** on the Devuan AMI (the agent needs
systemd) — don't rely on `aws logs tail`. Review logs via:

- The **`/admin/logs`** page (robert only) — tails the app log, with a
  "client errors only" filter for browser beacons.
- Or SSH: `sudo tail -f /var/log/rent-coordinator/application.log`.

## Backups

`./scripts/backup-now.sh` on the instance is the server-side path (calls the
backup service directly — `/api/backup` is auth-gated and not for cron). A
nightly cron (02:00 UTC) and an in-app idle-backup (after ~1h of write
inactivity) both run it. Local copies in `./backups/`; S3 at
`rent-coordinator-backups-822812818413` (us-west-2, 30-day retention). API
reference: [../scripts/BACKUP-API.md](../scripts/BACKUP-API.md).

## Secrets

AWS Secrets Manager, `rent-coordinator/config` (us-west-2). Loaded into each
instance's `.env` generically at boot (every key in the secret). To push to a
running host: `./scripts/restore-secrets.sh <host>`.

## Running locally

```bash
npm install
npm start        # compiles client CoffeeScript to static/js/ on startup, then runs
```

Environment variables and their defaults are defined in `lib/config.coffee`
(and summarized in the project `CLAUDE.md`); production values come from
Secrets Manager.

## Legacy

An older remote-install ("vault2") deployment path exists under `scripts/`
(`deploy-upgrade.sh`, `scripts/deployment.md`, `scripts/quick-start.md`). It
is **not** how production runs today and is kept only for reference.
