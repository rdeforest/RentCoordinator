# Known Bugs

This directory tracks active and recently-resolved bugs. Each bug has its
own file with reproduction steps, root cause, and (when known) a link to
the proposed fix in `docs/fixes/`.

## Active

| # | Title | Severity | Fix |
|---|---|---|---|
| 01 | Periods table shows raw `amount_due` instead of stress-free display | Low (UX) | [fixes/01](../fixes/01-periods-table-display.md) |
| 02 | Cannot delete rent period (FK constraint) | High | [fixes/02](../fixes/02-cascade-delete-migration.md) |
| 03 | Soft-delete UI wired to hard-delete model | Medium | [fixes/03](../fixes/03-soft-delete-events.md) |
| 04 | Lyndzie's work hours not appearing in rent periods | High | [fixes/04](../fixes/04-missing-work-hours.md) |
| 05 | `recalculateAllRent` retroactive logic discarded | Medium | [fixes/05](../fixes/05-recalculate-persists-retroactive.md) |

## Resolved

(none recorded yet — start adding when you fix the active ones)

## Adding a bug

Use this template:

```markdown
# Bug NN — Short title

**Reported:** YYYY-MM-DD by whoever
**Status:** active | investigating | fix-proposed | resolved

## Symptom

What the user sees.

## Reproduction

1. ...
2. ...

## Root cause

What's actually wrong. Often this needs a paragraph; sometimes it's "we
don't know yet".

## Proposed fix

Link to `docs/fixes/NN-...md` once you have one.

## Risk

What could go wrong applying the fix.
```
