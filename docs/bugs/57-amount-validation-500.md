# Bug 57 — Amount validation errors surface as 500

**Reported:** 2026-09-24 by architectural review
**Status:** resolved 2026-09-24 (partially — see note on `asyncRoute`)

## Resolution

`checkFields`/`validateAmounts` in `lib/models/events.coffee` now throw
through a `badRequest` helper that sets `err.status = 400`, instead of a
plain `Error`.

`PUT /rent/period/:year/:month` in `lib/routes/rent.coffee` (~213) now
`parseFloat`s `updates[field]` before writing it as the override's
`new_value`, matching what `buildEventPayload` already does for
`POST /rent/events`. Before this, a string-typed amount — what a plain HTML
form field or any client that doesn't coerce JSON types sends — failed
`validateAmounts`' `typeof value is 'number'` check on every call, even for
a value that parses cleanly (`"1200"`).

Covered by:
- `test/services/events.coffee` — calls `recordEvent` directly with a
  non-numeric `payment-made` amount and a `NaN` `adjustment` delta, and
  asserts `err.status is 400` on both. This is a model-level test and does
  not depend on `lib/middleware.coffee`.
- `test/integration/rent-period-put-parses-amount.coffee` — `PUT
  /rent/period/2026/8 { amount_due: '1234.50' }` now returns 200 with
  `amount_due: 1234.5` instead of failing.

Both reproduce the bug when reverted (verified: reverting the
`events.coffee` change makes `err.status` undefined again; reverting the
`rent.coffee` `parseFloat` makes the PUT route 500).

## Important dependency: `asyncRoute` does not yet honor `err.status`

**A parallel worktree is changing `lib/middleware.coffee`'s `asyncRoute` to
respond with `err.status` for 4xx errors — that change is absent here, by
design (this worktree was told not to touch `lib/middleware.coffee`).**

As things stand in this worktree, `asyncRoute` (lib/middleware.coffee ~120)
picks a status by pattern-matching `err.message` against
`/not found/i` and `/already deleted|not deleted/i`; anything else is a
500, regardless of `err.status`. Confirmed directly: `POST /rent/events`
with a non-numeric amount currently returns **500** with body
`{"error":"payment-made payload.amount must be a finite number, got NaN"}`,
even with this fix in place, because `err.status = 400` never gets read.

So: `lib/models/events.coffee` now carries the correct contract
(`err.status = 400`), and the model-level test proves it without touching
`asyncRoute`. The HTTP-level behavior (an actual 400 response from
`POST /rent/events` or `PUT /rent/events/:id` on a bad amount) will only
be correct once the other worktree's `asyncRoute` change lands and reads
`err.status`. No HTTP-level 400 test was added for this path for that
reason — it would fail today through no fault of this fix, and pass once
both changes are merged.

## Symptom

Posting a non-numeric amount to `POST /rent/events`, or a nonsensical
`amount_due`/`amount_paid` to `PUT /rent/period/:year/:month`, returned a
500 with a message that was in fact a straightforward, client-caused
validation failure — logged and reported as an internal server error.

## Reproduction

1. `POST /rent/events { type: 'payment', year, month, amount: 'abc',
   description: 'x' }`.

Expected (once `asyncRoute` reads `err.status`): 400.
Actual today: 500 — `asyncRoute` doesn't look at `err.status` yet.

2. `PUT /rent/period/2026/8 { amount_due: '1234.50' }` (a string, as an
   HTML form or a loosely-typed client would send).

Expected: 200, `amount_due: 1234.5`.
Actual (before this fix): 500 — the string failed the `typeof` check that
only ever expected a number, because nothing parsed it first.

## Root cause

Two separate gaps stacked:

1. `checkFields`/`validateAmounts` threw plain `Error`s with no `status`,
   so even a perfect `asyncRoute` would have nothing to read.
2. `PUT /rent/period/:year/:month` wrote `req.body`'s raw value as the
   override's `new_value` without parsing it, unlike `buildEventPayload`
   (used by `POST /rent/events`), which always `parseFloat`s the incoming
   amount. A string that represented a perfectly valid number was rejected
   by the numeric-type check the same way a genuinely bad value would be.

## Risk

Low. The `events.coffee` change only adds a `status` property to errors
that were already being thrown; nothing currently reads it except the
model-level test until `asyncRoute` changes. The `rent.coffee` `parseFloat`
change only accepts input that was previously rejected outright.
