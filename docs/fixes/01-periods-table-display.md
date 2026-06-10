# Fix 1 — Periods table shows raw amount_due instead of stress-free display

## What's broken

In `static/coffee/rent.coffee`, the `loadAllPeriods` function computes
`displayDue = getDisplayAmountDue period` and then never uses it. The HTML
template uses `period.amount_due` (the raw database value) for the displayed
text. Meanwhile, `getPaymentStatus` *does* use the stress-free display value,
so the Status column says PAID while the Amount Due column shows the full
$1,600. They disagree.

## Why it matters

- Visual contradiction undermines trust in the page.
- The whole point of the stress-free display is to avoid showing the full
  obligation in everyday navigation; this regression defeats that.

## What the fix does

- Display `displayDue` (stress-free value) in the cell text.
- Keep `data-value="#{period.amount_due}"` so that inline-edit operates on
  the real underlying value.
- Add a `title` attribute that reveals the underlying raw value on hover,
  so the override behavior isn't hidden — just de-emphasized.

## The patch

In `static/coffee/rent.coffee`, inside `loadAllPeriods`, change the
`map((period) ->` block so the Amount Due cell reads:

```coffee
<td class="editable-cell"
    contenteditable="false"
    data-field="amount_due"
    data-value="#{period.amount_due}"
    title="Underlying value: #{formatCurrency period.amount_due} (click to edit)">#{formatCurrency displayDue}</td>
```

Everything else in the row stays the same. The Amount Paid cell does not
need to change.

## How to verify

1. Load the rent page in a state with at least two prior months and one
   current month.
2. The Amount Due column for a past month with the override on should show
   $950 (or the configured override value), not $1,600.
3. Hover should reveal the underlying $1,600.
4. Click into the cell — the edit field should show 1600, not 950.
5. The Status column should be consistent: if Status shows PAID, Amount Due
   should be ≤ Amount Paid.

## Risk

Trivial — single-cell display change. No data path is altered.
