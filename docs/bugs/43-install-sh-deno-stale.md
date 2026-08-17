# Bug 43 — scripts/install.sh targets the abandoned Deno stack

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

`./scripts/install.sh` — which `CLAUDE.md` still lists as the current
local-install path — fails partway through. It is written for a Deno
build that no longer exists.

## Reproduction

1. Run `./scripts/install.sh` against a fresh checkout.
2. It clones, then verifies `deno.json` exists.

Expected: a working local install.
Actual: exits at the clone-verification step because there is no
`deno.json`. If that check were removed it would next fail at
`deno task build` / the `dist/main.js` check.

## Root cause

`scripts/install.sh` assumes the old Deno stack:

- `:149` hard-exits unless `$PREFIX/deno.json` exists.
- `:169-199` `build_application` runs `deno task build` and verifies
  `dist/main.js`.
- `:14` defaults `DB_PATH=/var/lib/rentcoordinator/db.kv`.

The current project is npm + `coffee main.coffee` + `node:sqlite`, with
the database at `tenant-coordinator.db`. There is no `deno.json` and no
Deno build.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Either retire the Deno installer outright, or rewrite it against the
npm/coffee reality (npm install, `coffee main.coffee`, correct DB path).
Until then, stop pointing `CLAUDE.md` at `./scripts/install.sh` as a
working path.

## Risk

Low. Stale infra, but actively misleading — the doc promises a path that
does not run.
