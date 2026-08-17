# Bug 17 — Rent events table is always empty (client/server field mismatch)

**Reported:** 2026-08-15 by codebase audit
**Status:** active

## Symptom

The "Rent Events" table on `/rent` always shows "No events found", even
when events exist and are being folded into the period math.

## Reproduction

1. Create any rent event (payment, adjustment, etc.).
2. Reload `/rent` and look at the Rent Events table.

Expected: the event listed with date, type, period, amount, description.
Actual: "No events found".

## Root cause

`GET /rent/events` (`lib/routes/rent.coffee:239-259`) returns the folded
event shape: `{ id, occurred_at, effective_for, actor, actor_user, action,
payload, target_event_id, deleted }`. The amount, note, year, and month all
live *inside* `payload`, and the top-level names differ (`action` not
`type`, `occurred_at` not `date`).

The client filters and renders on the legacy flat shape. In
`loadEvents` (`static/coffee/rent.coffee:312-314`) and again in
`renderEventsTable` (`static/coffee/rent.coffee:336-339`) it requires:

```coffee
event.type? and event.date? and event.year? and event.month? and
event.amount? and event.description? and event.id?
```

Of those, only `event.id` exists on the server payload. `type`, `date`,
`year`, `month`, `amount`, and `description` are all `undefined`, so every
event fails the guard and the table falls through to "No valid events
found" / "No events found". This is the same migration gap as bug 01, but
for the events list rather than the periods table.

## Proposed fix

(No docs/fixes/ file exists yet.)

Pick one side to own the wire contract. Cleanest is to project events onto
the flat shape the client already expects, server-side in `GET
/rent/events` — map `action`→`type`, `occurred_at`→`date`, and lift
`payload.amount`/`payload.note`/the `effective_for` year+month up to top
level. That keeps the client untouched and matches how `toWireShape`
already bridges periods. Alternatively, update `loadEvents` /
`renderEventsTable` (and the `editEvent`/`deleteEvent` accessors that read
`event.type`, `event.year`, etc.) to read the event-sourced shape. The
server-side projection is the smaller, more contained change.

## Risk

The client reads these same fields in several places beyond the table —
`editEvent` (rent.coffee:394-401), `deleteEvent` (rent.coffee:418-424), the
type filter — so whichever side is chosen, all of them must agree. A
server-side projection fixes them all at once; a client-side rewrite has to
touch each. Verify the exact field set by reading those handlers before
committing to the mapping.
