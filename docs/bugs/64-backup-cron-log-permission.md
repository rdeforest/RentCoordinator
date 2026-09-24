# Bug 64 — The nightly backup cron has never run: its log redirect is refused

**Reported:** 2026-09-24, found while preparing the 2026-09 sweep deploy
**Status:** resolved 2026-09-24 (live crontab fixed; Launch Template needs `deploy.sh deploy`)

## Symptom

The newest S3 backup was 2026-09-08, sixteen days old, with a nightly backup
supposedly running at 02:00 UTC. Every backup in S3 had an odd timestamp
(09-04 13:37, 09-08 17:00 and 18:10): those were the in-app idle backups,
which only fire after writes. No 02:00 backup had ever landed.
`/var/log/rent-coordinator-backup.log` did not exist.

## Root cause

The UserData crontab line, installed as the `rent-coordinator` user, was

    0 2 * * * cd /opt/rent-coordinator && bash scripts/backup-now.sh >> /var/log/rent-coordinator-backup.log 2>&1

`/var/log` is root-owned, so the shell refuses the redirect and never runs
`backup-now.sh`. Cron mailed the error to `/var/mail/rent-coordinator` every
night since the instance booted on 2026-09-03. Nobody reads that mailbox.

The 2026-09-03 fix verified `backup-now.sh` under a cron-like environment,
but not the redirect around it, which is where it fails.

## Resolution

The log moves to `/var/log/rent-coordinator/backup.log`, a directory the app
user owns, in both the live crontab and the CloudFormation UserData. The live
line was tested by running the exact crontab command under cron's
environment (`env -i SHELL=/bin/sh HOME=… PATH=/usr/bin:/bin`) as the app
user: exit 0, backup uploaded to S3.

## What still lets this happen

A failing backup is only visible in a local mailbox. Backup age belongs in
bug 62's consistency check (the landlord's warning icon should light when the
newest S3 backup is older than ~26 hours).
