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
  `systemctl`.
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

```bash
# 1. Back up prod first (see Backups) and confirm it's in S3.

# 2. Ship code to main (instances track main):
git push origin <branch>:main

# 3. On the instance (find IP below):
ssh -i ~/.ssh/id_aws_rdeforest admin@<INSTANCE_IP>
cd /opt/rent-coordinator && sudo -u rent-coordinator git pull --ff-only

# 4. If Secrets Manager gained a new key since the instance booted, append it
#    to .env (a running instance's .env is only written once, at boot).

# 5. Guard against replacement during the restart, then restart:
#    (run the suspend/resume from your workstation; the restart on the box)
aws autoscaling suspend-processes --auto-scaling-group-name RentCoordinator-production \
  --scaling-processes HealthCheck ReplaceUnhealthy
sudo /etc/init.d/rent-coordinator restart      # cycles cleanly since the pidfile fix

# 6. Verify, then resume:
curl -s http://localhost:8080/health           # on the box; or the ALB /health
aws autoscaling resume-processes --auto-scaling-group-name RentCoordinator-production \
  --scaling-processes HealthCheck ReplaceUnhealthy
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
