# Bug 34 — Backup restore isn't atomic; fixed safety-copy name self-clobbers

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

Two problems in the restore paths:

1. The pre-restore safety copy always uses the same fixed name, so a
   second restore overwrites the copy taken before the first restore. The
   undo only ever reaches back one restore.
2. Restore overwrites the live DB with a plain `copyFileSync`. A crash
   mid-copy leaves a truncated, corrupt live database with no lock or
   swap protecting it.

## Reproduction

N/A — latent; triggered on the second consecutive restore (loses the
original safety copy), or by a crash/interruption during the
`copyFileSync` onto the live DB.

## Root cause

Both `restoreFromS3` (`lib/services/backup.coffee:199-206`) and
`restoreFromFile` (`lib/services/backup.coffee:252-258`) copy the current
DB to a fixed `#{dbPath}.before-restore`, then `copyFileSync` the backup
directly over the live `dbPath`. The fixed name self-clobbers across
restores, and copy-over-live is non-atomic.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

- Timestamp the pre-restore copy (`#{dbPath}.before-restore-<iso>`) so
  each restore keeps its own safety copy.
- Restore atomically: write the incoming DB to a temp file on the same
  filesystem, then `rename` it onto `dbPath` (rename is atomic within a
  filesystem) instead of copying over the live file.

## Risk

Low. Both changes touch only the restore paths. Ensure the temp file and
`dbPath` are on the same filesystem so `rename` stays atomic rather than
falling back to a copy.
