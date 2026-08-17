# Bug 18 — /rent/summary uses raw amount_due, not display_amount_due

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

The summary "Outstanding Balance" card jumps to include the full base rent
(~$1,600) for the current month the instant a new month begins, before the
rent is actually due. This is exactly the "$1,600 overdue!" broadcast the
display logic was written to avoid — it just leaks through the summary
totals instead of the per-month row.

## Reproduction

1. Be in the current month, before the 15th (`RENT_DUE_DAY`).
2. Load `/rent` and read the Outstanding Balance card.

Expected: the current month contributes $0 (its `display_amount_due` before
the due date), matching the per-month row.
Actual: the current month contributes its full calculated `amount_due`
(~$1,600), overstating the outstanding balance.

## Root cause

`GET /rent/summary` (`lib/routes/rent.coffee:216-225`) sums the raw
`amount_due`:

```coffee
total_amount_due:    rows.reduce ((s, p) -> s + p.amount_due),  0
outstanding_balance: rows.reduce ((s, p) -> s + p.amount_due - p.amount_paid), 0
```

`amount_due` is the honest calculated (or pinned) value. `display_amount_due`
(period.coffee:117-121) is the value the dashboard is supposed to show, and
for the current month before the 15th it's $0. The summary ignores it.

`GET /rent/outstanding` (rent.coffee:109-123) already does the right thing —
it filters out `NOT DUE` months and computes against `display_amount_due` —
so the two endpoints disagree about what's owed.

## Proposed fix

(No docs/fixes/ file exists yet.)

Sum `display_amount_due` in the summary so it matches the display logic and
the `/rent/outstanding` handler:

```coffee
total_amount_due:    rows.reduce ((s, p) -> s + p.display_amount_due), 0
outstanding_balance: rows.reduce ((s, p) -> s + p.display_amount_due - p.amount_paid), 0
```

Consider clamping `outstanding_balance` at 0 per month the way
`/rent/outstanding` does (`Math.max 0, owed - paid`), so an overpaid month
doesn't subtract from the total.

## Risk

Low. It's a read-only endpoint and `display_amount_due` is already computed
for every period. Watch that "total amount due" is still meaningful for
past months — for those, `display_amount_due` equals `amount_due`, so the
change only affects the current-month-before-due-date case, which is the
intended fix.
