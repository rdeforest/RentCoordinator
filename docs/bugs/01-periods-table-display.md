# Bug 01 — Periods table shows raw amount_due

**Reported:** 2026-05-19
**Status:** fix-proposed

## Symptom

On the rent dashboard, the "All Rent Periods" table's "Amount Due" column
shows the full $1,600 base rent for past months that should show the
stress-free $950 (or whatever the agreed payment is). Meanwhile, the
"Status" column on the same row correctly says PAID based on the $950
threshold. The two columns disagree.

## Reproduction

1. Have at least one past month in `rent_periods` with `amount_due = 1600`
   and a payment of $950 or more recorded against it.
2. Load `/rent`.
3. Look at the "All Rent Periods" table row for that month.

Expected: Amount Due column shows $950 (matches Status: PAID).
Actual: Amount Due column shows $1,600.

## Root cause

In `static/coffee/rent.coffee::loadAllPeriods`, the function computes the
stress-free display value into a local variable `displayDue` but the HTML
template uses `period.amount_due` (the raw DB value) for the displayed
text.

## Proposed fix

See [fixes/01-periods-table-display.md](../fixes/01-periods-table-display.md).
