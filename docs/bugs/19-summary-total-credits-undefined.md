# Bug 19 — Summary "total credits" renders undefined

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

The "Total Credits" card in the rent summary shows a garbage/blank value
(whatever `formatCurrency undefined` produces), while the other summary
cards render fine.

## Reproduction

1. Load `/rent`.
2. Read the Total Credits summary card.

Expected: the sum of discounts applied across all periods.
Actual: an undefined/blank value.

## Root cause

Name mismatch between the response and the client accessor. `GET
/rent/summary` (`lib/routes/rent.coffee:223`) returns the key
`total_discount`:

```coffee
total_discount: rows.reduce ((s, p) -> s + p.discount_applied), 0
```

The client (`static/coffee/rent.coffee:87`) reads a different key:

```coffee
document.getElementById('total-credits').textContent =
  formatCurrency summary.total_discount_applied
```

`summary.total_discount_applied` is `undefined`, so `formatCurrency` gets
`undefined`. The other three cards work because their names match on both
sides — `outstanding_balance` (rent.coffee:224 / rent.coffee:86),
`total_amount_paid` (rent.coffee:222 / rent.coffee:88), and `total_periods`
(rent.coffee:220 / rent.coffee:89). Only credits is affected.

## Proposed fix

(No docs/fixes/ file exists yet.)

Align the names. Simplest is to rename the response key to match the client:
`total_discount_applied` in `lib/routes/rent.coffee:223`. (Equivalently,
change the client accessor to `summary.total_discount` — either works;
pick whichever keeps the wire contract consistent with the other keys,
which use the `total_amount_*` / full-word style.)

## Risk

Very low. Confirm no other consumer reads `total_discount` before renaming
it; a grep of the client and any tests covers that. Read
`static/coffee/rent.coffee` to confirm the accessor before changing the
server side.
