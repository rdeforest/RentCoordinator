# Bug 46 — boot-time migration loop swallows migration failures

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

If a non-final migration fails during instance boot, the loop keeps
going, the service starts anyway, and the app serves a schema the code
doesn't expect. The failure just scrolls past in the cloud-init log.

## Reproduction

N/A — latent; triggered when any migration except the last one exits
non-zero (throws, rolls back) during boot.

## Root cause

`infrastructure/cloudformation/rent-coordinator-infrastructure.yaml:335-344`
runs migrations inside `sudo -u rent-coordinator bash -c '...'` with no
`set -e`:

```
for migration in $(ls migrations/*.coffee | sort); do
  echo "Running migration: $migration"
  npx coffee "$migration"
done
```

Without `set -e`, a failing `npx coffee` in the middle of the list
doesn't stop the loop, and the `bash -c` exit status reflects only the
last migration. Boot proceeds to start the service. Since (per the
comment at `:330-333`) this is the only place that closes the schema gap
between an old S3 backup and the deployed code, a swallowed failure means
the app runs against a partially-migrated DB.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Add `set -e` inside the `bash -c` block so any failing migration aborts
the boot, and ideally check each migration's exit status explicitly and
stop the loop on the first failure.

## Risk

Medium, but infra-only. A bad migration should fail loudly and stop the
instance from serving, not silently degrade.
