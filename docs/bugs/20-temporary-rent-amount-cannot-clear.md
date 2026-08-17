# Bug 20 — temporary_rent_amount can never be cleared

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

Once a temporary rent override amount has been set, emptying the input and
saving doesn't clear it. Un-checking "apply override" masks it, but the
stale amount is still there — re-checking the box resurrects the old value.

## Reproduction

1. Set the temporary override input to, say, `1200`, check apply, and save.
2. Clear the input (leave it blank), keep apply checked or not, and save.
3. Re-check "apply override" and save (or just reload the configuration).

Expected: the override amount is gone; re-checking apply has nothing to
apply.
Actual: the folded config still carries `1200`; re-checking apply brings
$1,200 back.

## Root cause

When the input is empty the client (`static/coffee/rent.coffee:660-663`)
explicitly sends `null`:

```coffee
if overrideInput.value
  updates.temporary_rent_amount = parseFloat overrideInput.value
else
  updates.temporary_rent_amount = null
```

But `PUT /rent/configuration` (`lib/routes/rent.coffee:52-61`) guards the
write with `if req.body.temporary_rent_amount?`. `null` fails the existence
check, so no `config-changed` event is recorded and the last non-null value
persists in the fold (`resolveConfig`, period.coffee:47-55, which only ever
assigns `snapshot[field] = new_value` for events that exist).

`apply_override` doesn't have this problem because it's written with a
separate `if req.body.apply_override?` guard and coerced with `Boolean`
(rent.coffee:62-70) — so it can be turned off. The amount can only be
masked (via apply_override), never actually cleared.

## Proposed fix

(No docs/fixes/ file exists yet.)

Distinguish "field absent from the request" from "field present and
explicitly null". Change the guard to check for the property's presence
rather than a non-null value, e.g. `if 'temporary_rent_amount' of req.body`,
and record a `config-changed` event with `new_value: null` when the caller
clears it. `resolveConfig` already assigns whatever `new_value` is, so a
recorded `null` correctly resets the snapshot field to null.

## Risk

Low, but check every caller of `PUT /rent/configuration` sends the field
only when it means to change it — switching from a null-check to a
presence-check means an accidentally-included `temporary_rent_amount: null`
now clears the value where before it was ignored. The client only sends it
from the save-override handler, so the surface is small.
