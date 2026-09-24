# Bug 53 — Missing SESSION_SECRET surfaces only as a silent failed restart

**Reported:** 2026-09-23 by architectural review
**Status:** resolved 2026-09-24

## Resolution

`scripts/upgrade.sh` now checks, right after it sources the environment
file, that `SESSION_SECRET` is present and non-empty — the same
`grep -q '^SESSION_SECRET=.\+'` check the CloudFormation instance bootstrap
already runs against a fresh `.env`
(`infrastructure/cloudformation/rent-coordinator-infrastructure.yaml`), with
a matching `FATAL:` message. A missing or empty secret now stops the
in-place upgrade procedure at step 5 (docs/deployment.md), before step 6
restarts the service, rather than surfacing only as a restart that silently
did not come back up.

## Symptom

If a production `.env` was missing `SESSION_SECRET` — or had it truncated to
an empty value — `docs/deployment.md`'s in-place upgrade procedure gave no
indication anything was wrong until step 7's health check. Step 6 restarts
the service with `sudo /etc/init.d/rent-coordinator restart`, which uses
`start-stop-daemon --background`; that returns 0 whether or not the process
it launched actually stayed running. The app itself refuses to start without
`SESSION_SECRET` outside development/test (`lib/config.coffee`) — correctly
— but by the time that happens, the operator already believes the restart
succeeded.

## Reproduction

1. Have a production `.env` with `SESSION_SECRET` missing or empty (drift
   from Secrets Manager, or manual editing).
2. Follow the in-place upgrade procedure through step 6.
3. `restart` reports success. The process is not actually listening —
   `config.coffee` threw before `app.listen` — and nothing before step 7's
   health check would say so.

## Root cause

Nothing in the upgrade path validated the precondition the app itself
enforces. `scripts/upgrade.sh` sourced the environment file and moved
straight to migrations without checking it for the one variable the app is
known to refuse to start without.

## Risk

None identified — this narrows an existing silent failure into a loud, early
one at the same point in the procedure. Local development is unaffected:
`config.coffee` only requires `SESSION_SECRET` outside `development`/`test`,
and `upgrade.sh` is a deployment/bootstrap tool, not part of `npm start`.
