# Bug 47 — scripts/upgrade.sh is empty but the docs say it runs migrations

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

`migrations/README.md` tells you migrations run via `scripts/upgrade.sh`.
That file is empty — running it does nothing, silently, and looks like
success.

## Reproduction

1. Follow `migrations/README.md:11` and run `scripts/upgrade.sh` to apply
   migrations.
2. `wc -c scripts/upgrade.sh` → `0`.

Expected: migrations applied.
Actual: no-op; exit 0; you believe migrations ran.

## Root cause

`scripts/upgrade.sh` is a 0-byte file. `migrations/README.md:11` states
"Migrations are executed manually or by `scripts/upgrade.sh` in
alphabetical order." The real migration runner lives in the
CloudFormation userdata (see bug 46), not here.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Either restore a real `upgrade.sh` that runs `migrations/*.coffee` in
order (mirroring the CloudFormation loop, with `set -e`), or delete the
empty file and point `migrations/README.md` at the actual runner.

## Risk

Low. Documentation/tooling gap, but it invites a false "migrations ran"
belief.
