# Bug 39 — period.coffee DEFAULT_CONFIG duplicates config.coffee constants

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

The business-rule constants exist in two places. `/rent/constants`
(served from `config.coffee`) can disagree with the amounts the period
fold actually computes, because the fold reads its own private copy.

## Reproduction

N/A — latent; triggered when someone changes a business rule (base rent,
hourly credit, agreed payment, due day) in one file and not the other.

## Root cause

`lib/services/period.coffee:6-13` defines `DEFAULT_CONFIG` with hardcoded
literals: `base_rent 1600`, `hourly_credit 50`, `max_monthly_hours 8`,
`agreed_monthly_payment 950`, `rent_due_day 15`. These are a second copy
of `BASE_RENT`, `HOURLY_CREDIT`, `MAX_MONTHLY_HOURS`,
`AGREED_MONTHLY_PAYMENT`, `RENT_DUE_DAY` in `lib/config.coffee:14-18`.

The route handlers read the constants from `config.coffee`; the period
fold reads `DEFAULT_CONFIG`. Nothing keeps the two in sync.

## Proposed fix

(No docs/fixes/ file exists yet — describe the fix inline.)

Source `DEFAULT_CONFIG`'s numbers from `config.coffee` instead of
re-declaring them. `period.coffee` is otherwise pure (no DB, no
persistence), so either import the constants module directly or inject
the config values at the call site so the file stays free of side
effects. Single source of truth in `config.coffee`.

## Risk

Low. Mechanical change; the values are currently identical, so behavior
does not change today.
