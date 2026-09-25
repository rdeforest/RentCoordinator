# Bug 66 — Loose ends in the override rules after bug 56

**Reported:** 2026-09-24 by the post-fix review of the 2026-09 sweep
**Status:** resolved 2026-09-24

## Resolution

1. **Redundant August pin removed.** Migration
   `migrations/2026-09-24_100000_delete_redundant_august_amount_paid_override.coffee`
   records a `deleted` event targeting the specific `amount_paid` override
   (id `01a06834-16fc-73ff-a366-e2c1ae188cde`) that pinned 2026-08 at 1200 —
   the same shape `DELETE /rent/events/:id` writes, not a row mutation.
   Idempotent: no-op if the event is absent (fresh DBs, tests) or already
   deleted (re-runs). Tested in `test/services/migrations.coffee`.

2. **`amount_paid` pins now follow the `amount_due` rule.**
   `lib/services/period.coffee::computeMonth` picks the latest override for
   both fields the same way — `latestFieldOverride`, by `occurred_at`, not
   array position — via a shared `latestByOccurredAt` helper. A
   `payment-made` event with `occurred_at` after the latest `amount_paid`
   pin now applies on top of it, exactly as an `adjustment` after an
   `amount_due` pin does (bug 56); a payment at or before the pin is
   superseded. Equal `occurred_at` counts as *not* after, so a same-instant
   payment is superseded rather than added on top — same tie rule as
   adjustments.

   Verified against production-shaped data: April, May and June 2026 (pins
   of 1200 with no later payments) still show 1200 paid; August, after the
   migration removes its pin, shows 1200 paid from the `payment-made` event
   alone.

3. **Editing a superseded adjustment now refuses.** `PUT /rent/events/:id`
   400s when the target is an `adjustment` on `amount_due` whose
   `occurred_at` is not after the month's latest `amount_due` override,
   with a message naming the override and pointing at adding a new
   adjustment instead. Uses the `err.status = 400` convention `asyncRoute`
   already handles.

4. **Tests added** in `test/services/period.coffee` pinning:
   - the later override wins by `occurred_at`, not array position (for
     both `amount_due` and `amount_paid`);
   - an adjustment/payment at the same `occurred_at` as the override is
     superseded, not applied on top (for both fields);
   - a payment after an `amount_paid` override applies on top of it.

   Each was verified to fail against the reverted behavior it guards (see
   commit history for this bug).

5. **Smaller items:**
   - `PUT /rent/period`'s per-field override writes are now wrapped in
     `transaction`, matching `PUT /rent/configuration`.
   - `static/coffee/payment.coffee`'s "X through Y" label for
     `/rent/outstanding` now excludes corrupt months (bug 59) from the
     range, not just from the total.
   - `PUT`/`DELETE /work-logs/:id` no longer call
     `rentService.createOrUpdateRentPeriod` — the legacy `rent_periods`
     write bug 55 already removed from the timer. `recalculateAllRent` and
     `createOrUpdateRentPeriod` are deleted from
     `lib/services/rent.coffee` as now-unused; `calculateRent` and
     `getRentSummary` stay, since `scripts/recalculate-rent-periods.coffee`
     still calls them against the legacy tables.
   - `MIN_DURATION_MINUTES` moved from `lib/routes/work.coffee` to
     `lib/config.coffee`, next to `MIN_WORK_LOG_DURATION`, with a line
     saying why manual entries and timer sessions have different minimums.

---

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
