# Bug 44 — dist build never copies package.json; dist runtime crashes on load

**Reported:** 2026-08-15 by codebase audit
**Status:** resolved 2026-09-23

## Resolution

Three things were wrong, not one. `package.json` was never copied into `dist/`; `fixImportPaths` rewrote ESM `import`/`from` but not `require './x.coffee'`, which is how this codebase imports, so every compiled module asked for a file `dist/` does not contain; and the compiled output is CommonJS under a `"type": "module"` manifest, so the artifact described itself as something it is not. The build also compiled `.`, which swept in scratch directories — a stale copy of the repo under `tmp/` had been failing the build since May, which is why none of this had been noticed. `npx coffee scripts/build.coffee` now produces a `dist/` that starts and serves.

## Symptom

An app started from the compiled `dist/` artifact fails to load the
routing module, because it can't resolve `package.json`. The health check
and startup both reference `pkg.version`.

## Reproduction

N/A — latent; only the dist path. Triggered by running the compiled
`dist/` output (the deploy-upgrade artifact). The CloudFormation
production path avoids it by running from source
(`npx coffee main.coffee`).

## Root cause

`lib/routing.coffee:14` does `pkg = require '../package.json'`. Compiled,
this becomes `dist/lib/routing.js` resolving `require('../package.json')`
→ `dist/package.json`.

`scripts/build.coffee` compiles sources into `dist/` and, at `:56-57`,
copies only `static` → `dist/static`. It never copies `package.json` into
`dist/`. So the file `dist/lib/routing.js` requires does not exist, and
the module fails to load.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Have `build.coffee` copy `package.json` into `dist/` alongside the static
copy, or read the version some other way that survives compilation.
Longer term, reconcile the two deploy mechanisms — production runs from
source while the dist artifact is built but apparently not exercised — so
one of them isn't quietly broken.

## Risk

Low-medium. Latent today because production runs from source; becomes a
hard startup failure the moment anything runs from `dist/`.
