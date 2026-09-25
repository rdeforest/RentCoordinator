# Bug 66 — Loose ends in the override rules after bug 56

**Reported:** 2026-09-24 by the post-fix review of the 2026-09 sweep
**Status:** open (August confirmed paid once; delete its pin, then change the rule)

Bug 56 made adjustments recorded after an `amount_due` override apply on top
of it. The same review found the neighbouring cases still inconsistent.

## 1. An `amount_paid` override discards every later payment

`computeMonth` still takes `amount_paid` from an override outright, so a
payment recorded after the pin is summed and then overwritten. If the tenant
pays a month the landlord pinned as partly paid, the month keeps showing the
pinned figure and "pay everything" bills the difference again.

The obvious fix (later payments apply on top, as with bug 56) **changes a real
month**. Production, 2026-09-24:

| Month | Pinned `amount_paid` | Pinned at | `payment-made` events |
|---|---|---|---|
| 2026-04 | 1200 | 2026-07-01 | none |
| 2026-05 | 1200 | 2026-07-01 | none |
| 2026-06 | 1200 | 2026-09-03 | none |
| 2026-08 | 1200 | 2026-09-03 16:57 | 1200 on 2026-09-04 |

August shows $1,200 paid today; under the new rule it would show $2,400. If
August was paid once, the pin was a stopgap during the 09-03 recovery and the
data fix is to delete the pin, which should happen before the rule changes.
**Confirmed 2026-09-24:** Stripe shows one $1,200 payment for August,
initiated 08-30; the `payment-made` dated 09-04 is its ACH settlement arriving
by webhook. The August pin is redundant. Order of work: record a `deleted`
event for the August `amount_paid` override (display unchanged: 1200 either
way), then apply later payments on top of `amount_paid` pins. April-June pins
have no later payments and are unaffected.

July, for the record: its $1,200 `payment-made` was entered manually on
07-01 with method `other` and no Stripe intent, and Stripe has no July
transaction. Robert is confirming with Lyndzie how it was paid.

The pin also picks by array position where the `amount_due` pin picks by
`occurred_at`; the fix should give both one rule.

## 2. Editing a superseded adjustment is accepted and ignored

An edit keeps the adjustment's original `occurred_at`, so an adjustment made
before an override stays superseded however it is edited. `PUT
/rent/events/:id` returns 200 and nothing moves. Smallest fix: refuse (400)
edits to an adjustment older than the month's latest `amount_due` override.
Production has no adjustments yet, so this cannot happen today.

## 3. Smaller

- Tests do not pin "latest override wins" or the tie at equal `occurred_at`;
  both can be flipped with all 60 period tests green.
- `PUT /rent/period` writes its fields in a loop without `transaction`, so a
  bad second field leaves the first committed behind a 400. The
  configuration route already wraps the same loop.
- The payment page labels the range from all months in `/rent/outstanding`,
  including corrupt ones the allocation excludes (bug 59).
- `PUT`/`DELETE /work-logs/:id` still write the legacy `rent_periods` table,
  which bug 55 stopped the timer doing.
- `MIN_DURATION_MINUTES` (1, manual entries) sits beside
  `config.MIN_WORK_LOG_DURATION` (60, timer) with nothing saying the
  difference is intended.
