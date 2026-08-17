# Bug 45 — backup-*.sh parse .env via `export $(cat .env | xargs)` and mangle secrets

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

The three backup shell scripts load `.env` in a way that corrupts any
value containing a space, quote, `#`, or `=`. The backup then runs with
wrong or missing credentials and can fail S3 auth without a clear error.

## Reproduction

1. Put a value with a space or `#` in `.env` (Stripe keys, `SMTP_PASS`,
   `SESSION_SECRET`, base64 secrets qualify).
2. Run `./scripts/backup-now.sh`.

Expected: env loaded verbatim, backup authenticates.
Actual: `xargs` word-splits the value into bogus vars or truncates it;
the real credential is mangled.

## Root cause

`scripts/backup-now.sh:13`, `scripts/backup-list.sh:11`,
`scripts/backup-restore.sh:11` all use:

```
export $(cat .env | grep -v '^#' | xargs)
```

`xargs` splits on whitespace and strips quotes, so any non-trivial value
breaks. The CloudFormation userdata and the init unit already use the
correct `set -a; . .env; set +a` pattern — these three scripts are
inconsistent with that and buggy.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Replace the `export $(cat .env | ... | xargs)` line in all three scripts
with:

```
set -a && . ./.env && set +a
```

Matches the pattern already used everywhere else.

## Risk

Low-medium. Silent credential corruption; the backup path is exactly
where you don't want a quiet failure.
