# Bug 24 — Edit-work billable checkbox uses `isnt false`, flips non-billable to billable

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

Editing a work entry that was marked non-billable shows the "Billable"
checkbox as checked. If the user saves without noticing, the entry is
stored as billable — silently converting non-billable work to billable.

## Reproduction

1. Create or have a work log with `billable = 0`.
2. Click Edit on that entry.
3. Look at the Billable checkbox in the modal.

Expected: unchecked.
Actual: checked. Saving sends `billable: true`, and the server stores 1.

## Root cause

`static/coffee/work.coffee:121` (`editWork`) sets:

```coffee
document.getElementById('work-billable').checked = log.billable isnt false
```

SQLite stores `billable` as an integer (0/1), so the value arriving in the
JSON payload is `0` or `1` — never the boolean `false`. In JavaScript
`0 !== false` is `true`, so `log.billable isnt false` is always truthy and
the box is always checked, including when `billable` is 0.

This is the same integer-vs-boolean class as the earlier server-side
billable binding fix (noted in CLAUDE.md, 2025-12-29). The submit handler
then reads `.checked` (line 139) and posts `billable: true`, and the PUT
handler stores `if billable then 1 else 0` (`lib/routes/work.coffee:92`),
persisting the flip.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Compare truthily instead of against `false`:

```coffee
document.getElementById('work-billable').checked = !!log.billable
```

`log.billable` alone (or `log.billable is 1`) is equivalent. This makes 0
uncheck the box and 1 check it.

## Risk

Low. Single-line, display-only change. Any entries already flipped to
billable by this bug are not corrected retroactively and would need manual
review.
