# Bug 58 — PUT /work-logs accepts a zero or empty duration

**Reported:** 2026-09-24 by architectural review
**Status:** resolved 2026-09-24

## Resolution

`lib/routes/work.coffee` now has one `parseDuration` validator (`Number`,
finite, `>= 1`) shared by `POST /work-logs` and `PUT /work-logs/:id`. Both
reject anything that doesn't parse to at least one minute.

Covered by `test/integration/work-log-duration-validation.coffee`: create a
2-hour log, then attempt `PUT { duration: 0 }` and `PUT { duration: '' }` —
both now 400, and `/rent/period` still shows the original 2-hour credit
afterward. A legitimate edit (`duration: 180`) still succeeds. Verified by
reverting the `PUT` handler back to its old check: both rejection cases
come back 200 instead of 400.

## Symptom

Editing a work log's duration to `0` or `''` (an empty form field) silently
succeeded and zeroed the rent credit for that log, though `POST
/work-logs` already refused to create a log with a duration under one
minute.

## Reproduction

1. Create a work log with `duration: 120`.
2. `PUT /work-logs/:id { duration: 0 }` (or `{ duration: '' }`).
3. `GET /rent/period/:year/:month`.

Expected: the request is rejected; the credit stays at 2 hours.
Actual: 200; the log's `work-reported` event now carries 0 hours.

## Root cause

`PUT /work-logs/:id` gated the update on `duration?` — CoffeeScript's
existential operator, true for `0` and `''` alike, since neither is `null`
or `undefined`. `Number ''` is `0`, and `Number.isFinite(0)` is `true`, so
an empty field passed the only check the route ran and was written straight
through as `updates.duration = 0`. `POST /work-logs` had already been fixed
to require `duration >= 1` (a comment there notes the `'abc' < 1` gap it
closed); the `PUT` path never got the same floor.

## Risk

Low. Tightens validation on a path that previously accepted a value no
legitimate client would intentionally send.
